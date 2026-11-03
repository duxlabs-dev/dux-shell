import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../Common/PamStack.js" as PamStack

DDialog {
    id: root

    property var currentFlow: PolkitService.agent?.flow
    property string passwordInput: ""
    property bool isLoading: false
    property bool awaitingFprintForPassword: false
    readonly property string inputPromptLabel: (root.currentFlow?.inputPrompt ?? "").replace(/[\s:]+$/, "")

    property string polkitEtcPamText: ""
    property string polkitLibPamText: ""
    property string systemAuthPamText: ""
    property string commonAuthPamText: ""
    property string passwordAuthPamText: ""
    readonly property bool polkitPamHasFprint: {
        const polkitText = polkitEtcPamText !== "" ? polkitEtcPamText : polkitLibPamText;
        if (!polkitText)
            return false;
        return PamStack.moduleEnabled(polkitText, "pam_fprintd") || (polkitText.includes("system-auth") && PamStack.moduleEnabled(systemAuthPamText, "pam_fprintd")) || (polkitText.includes("common-auth") && PamStack.moduleEnabled(commonAuthPamText, "pam_fprintd")) || (polkitText.includes("password-auth") && PamStack.moduleEnabled(passwordAuthPamText, "pam_fprintd"));
    }

    signal cancelRequested
    signal closeRequested
    signal authenticationSucceeded

    focus: true

    title: I18n.tr("Authentication Required")
    supportingText: root.currentFlow?.message ?? ""
    iconName: "lock"
    acceptEnabled: !root.isLoading
    onRejected: cancelAuth()
    onAccepted: submitAuth()

    function focusPasswordField() {
        passwordField.forceActiveFocus();
    }

    function reset() {
        passwordInput = "";
        isLoading = false;
        awaitingFprintForPassword = false;
    }

    function _commitSubmit() {
        isLoading = true;
        awaitingFprintForPassword = false;
        currentFlow.submit(passwordInput);
        passwordInput = "";
    }

    function submitAuth() {
        if (!currentFlow || isLoading)
            return;
        if (!currentFlow.isResponseRequired) {
            awaitingFprintForPassword = true;
            return;
        }
        _commitSubmit();
    }

    function cancelAuth() {
        awaitingFprintForPassword = false;
        cancelRequested();
    }

    Connections {
        target: root.currentFlow
        enabled: root.currentFlow !== null

        function onIsResponseRequiredChanged() {
            if (!root.currentFlow.isResponseRequired)
                return;
            if (root.awaitingFprintForPassword && root.passwordInput !== "") {
                root._commitSubmit();
                return;
            }
            root.awaitingFprintForPassword = false;
            root.isLoading = false;
            passwordField.forceActiveFocus();
        }

        function onAuthenticationSucceeded() {
            root.authenticationSucceeded();
            root.closeRequested();
        }

        function onAuthenticationFailed() {
            root.isLoading = false;
        }

        function onAuthenticationRequestCancelled() {
            root.closeRequested();
        }
    }

    FileView {
        path: "/etc/pam.d/polkit-1"
        printErrors: false
        onLoaded: root.polkitEtcPamText = text()
        onLoadFailed: root.polkitEtcPamText = ""
    }

    FileView {
        path: "/usr/lib/pam.d/polkit-1"
        printErrors: false
        onLoaded: root.polkitLibPamText = text()
        onLoadFailed: root.polkitLibPamText = ""
    }

    FileView {
        path: "/etc/pam.d/system-auth"
        printErrors: false
        onLoaded: root.systemAuthPamText = text()
        onLoadFailed: root.systemAuthPamText = ""
    }

    FileView {
        path: "/etc/pam.d/common-auth"
        printErrors: false
        onLoaded: root.commonAuthPamText = text()
        onLoadFailed: root.commonAuthPamText = ""
    }

    FileView {
        path: "/etc/pam.d/password-auth"
        printErrors: false
        onLoaded: root.passwordAuthPamText = text()
        onLoadFailed: root.passwordAuthPamText = ""
    }

    StyledText {
        text: root.currentFlow?.supplementaryMessage ?? ""
        font.pixelSize: Theme.fontSizeSmall
        color: (root.currentFlow?.supplementaryIsError ?? false) ? Theme.error : Theme.onSurfaceVariant
        width: parent.width
        wrapMode: Text.Wrap
        visible: text !== ""
    }

    DTextField {
        id: passwordField

        width: parent.width
        outlined: true
        controlHeight: Theme.fieldHeightLarge
        labelText: root.inputPromptLabel || I18n.tr("Password")
        isError: PolkitService.authFailed
        supportingText: isError ? I18n.tr("Authentication failed - try again") : ""
        leftIconName: root.polkitPamHasFprint ? "fingerprint" : "lock"
        font.pixelSize: Theme.fontSizeMedium
        textColor: Theme.surfaceText
        text: root.passwordInput
        showPasswordToggle: !(root.currentFlow?.responseVisible ?? false)
        echoMode: (root.currentFlow?.responseVisible ?? false) || passwordVisible ? TextInput.Normal : TextInput.Password
        placeholderText: ""
        enabled: !root.isLoading
        onTextEdited: root.passwordInput = text
        onAccepted: root.submitAuth()
    }

    actions: [
        DButton {
            maximumWidth: root.actionWidth
            wrapText: true
            text: I18n.tr("Cancel")
            backgroundColor: "transparent"
            textColor: Theme.primary
            onClicked: root.cancelAuth()
        },
        DButton {
            maximumWidth: root.actionWidth
            wrapText: true
            text: I18n.tr("Authenticate", "verb, polkit password dialog submit button")
            enabled: !root.isLoading
            busy: root.isLoading
            onClicked: root.submitAuth()
        }
    ]
}
