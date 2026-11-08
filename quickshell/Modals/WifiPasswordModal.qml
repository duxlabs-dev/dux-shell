import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.Common
import qs.Modules.Network
import qs.Services

DModal {
    id: root

    layerNamespace: "dms:wifi-password"
    keepPopoutsOpen: true
    allowStacking: true
    shouldBeVisible: false
    modalWidth: Math.min(Theme.dialogMaxWidth, screenWidth - Theme.spacingXL * 2)
    modalHeight: Math.min(dialog.implicitHeight, screenHeight - Theme.spacingXL * 2)
    enableShadow: true
    onBackgroundClicked: form.clearAndClose()
    directContent: dialog

    property bool disablePopupTransparency: true

    function show(ssid) {
        form.show(ssid);
        open();
    }

    function showHidden() {
        form.showHidden();
        open();
    }

    function showFromPrompt(token, ssid, setting, fields, hints, reason, connType, connName, vpnService, fInfo) {
        form.showFromPrompt(token, ssid, setting, fields, hints, reason, connType, connName, vpnService, fInfo);
        open();
    }

    function hide() {
        close();
    }

    Connections {
        target: NetworkService

        function onPasswordDialogShouldReopenChanged() {
            if (!NetworkService.passwordDialogShouldReopen || NetworkService.connectingSSID === "")
                return;
            root.show(NetworkService.connectingSSID);
            NetworkService.passwordDialogShouldReopen = false;
        }
    }

    DDialog {
        id: dialog
        opened: root.shouldBeVisible
        focus: root.shouldBeVisible
        title: form.title
        supportingText: form.supportingText
        acceptEnabled: form.canConnect
        onAccepted: form.submitCredentialsAndClose()
        onRejected: form.clearAndClose()
        onOpenedChanged: {
            if (opened) {
                Qt.callLater(form.focusFirstField);
                return;
            }
            form.clearInputs();
        }

        WifiConnectForm {
            id: form
            inputEnabled: dialog.opened
            onCloseRequested: root.close()
            onFocusSubmitRequested: connectButton.forceActiveFocus()
        }

        actions: [
            DButton {
                maximumWidth: dialog.actionWidth
                wrapText: true
                text: I18n.tr("Cancel")
                variant: "text"
                onClicked: form.clearAndClose()
            },
            DButton {
                id: connectButton
                maximumWidth: dialog.actionWidth
                wrapText: true
                text: form.submitText
                enabled: form.canConnect
                onClicked: form.submitCredentialsAndClose()
            }
        ]
    }
}
