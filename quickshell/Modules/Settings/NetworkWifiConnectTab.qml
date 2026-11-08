pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Network
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool _initialFocusDone: false

    // Settings enables the page once it is presented, after it has parked or moved focus.
    onEnabledChanged: {
        if (enabled && !_initialFocusDone) {
            _initialFocusDone = true;
            Qt.callLater(() => Qt.callLater(form.focusFirstField));
        }
    }

    Component.onCompleted: {
        switch (SettingsUiState.wifiConnectMode) {
        case "password":
            form.show(SettingsUiState.wifiConnectSsid);
            break;
        case "hidden":
            form.showHidden();
            break;
        case "import":
            form.showImport(SettingsUiState.wifiConnectProfile, SettingsUiState.wifiConnectFileName);
            break;
        default:
            parentModal?.setPage("network_wifi");
        }
        // Keep the title; the header reads it while this page is open.
        SettingsUiState.wifiConnectMode = "";
        SettingsUiState.wifiConnectSsid = "";
        SettingsUiState.wifiConnectProfile = null;
        SettingsUiState.wifiConnectFileName = "";
    }

    // Enter that no field consumed; the form submits at most once per show.
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && form.canConnect && !event.isAutoRepeat) {
            form.submitCredentialsAndClose();
            event.accepted = true;
        }
    }

    SettingsPage {
        SettingsRow {
            visible: form.supportingText !== "" && !form.isHiddenNetwork
            subtitle: form.supportingText
        }

        WifiConnectForm {
            id: form

            onCloseRequested: root.parentModal?.goBack()
            onRevealRequested: item => {
                root.parentModal?.revealItem(item);
                item.forceActiveFocus();
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Cancel")
                iconName: "close"
                colorRole: "secondaryContainer"
                onClicked: form.clearAndClose()
            }

            DFab {
                text: form.submitText
                iconName: "wifi"
                colorRole: "primary"
                enabled: form.submitEnabled
                onClicked: form.submitCredentialsAndClose()
            }
        }
    }
}
