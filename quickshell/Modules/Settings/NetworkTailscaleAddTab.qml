pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Services

Item {
    id: root

    property var parentModal: null
    property bool _initialFocusDone: false

    readonly property bool writable: TailscaleService.canWritePrefs && TailscaleService.canOperate && TailscaleService.backendState !== "Unreachable"

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    // Settings enables the page once it is presented, after it has parked or moved focus.
    onEnabledChanged: {
        if (enabled && !_initialFocusDone) {
            _initialFocusDone = true;
            Qt.callLater(() => Qt.callLater(serverField.focusField));
        }
    }
    Component.onCompleted: TailscaleService.loadProfiles(true)

    function submit() {
        if (writable && !TailscaleService.addPending)
            TailscaleService.addProfile(serverField.value.trim(), null);
    }

    Ref {
        service: TailscaleService
    }

    // Back and Cancel give up the add; closing Settings or leaving elsewhere keeps the browser login pending.
    Connections {
        target: root.parentModal

        function onCurrentPageChanged() {
            if (root.parentModal.currentPage === "network_tailscale")
                TailscaleService.abandonAdd();
        }
    }

    Connections {
        target: TailscaleService

        function onAddCompleted() {
            root.parentModal?.goBack();
        }
    }

    SettingsPage {
        SettingsCard {
            SettingsTextFieldRow {
                id: serverField
                text: I18n.tr("Server", "Tailscale login server URL field label")
                placeholderText: I18n.tr("leave empty for default", "Tailscale login server placeholder")
                enabled: !TailscaleService.addPending
                onAccepted: root.submit()
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Cancel")
                iconName: "close"
                colorRole: "secondaryContainer"
                onClicked: root.parentModal?.goBack()
            }

            DFab {
                text: I18n.tr("Add")
                iconName: "person_add"
                colorRole: "primary"
                busy: TailscaleService.addPending
                enabled: root.writable && !TailscaleService.addPending
                onClicked: root.submit()
            }
        }
    }
}
