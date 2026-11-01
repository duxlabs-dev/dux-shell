import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DModal {
    id: root

    layerNamespace: "dms:wifi-password"
    keepPopoutsOpen: true
    allowStacking: true
    shouldBeVisible: false
    modalWidth: Math.min(Theme.dialogMaxWidth, screenWidth - Theme.spacingXL * 2)
    modalHeight: Math.min(contentFocusScope.implicitHeight, screenHeight - Theme.spacingXL * 2)
    enableShadow: true
    onBackgroundClicked: clearAndClose()
    directContent: contentFocusScope

    property bool disablePopupTransparency: true
    property string wifiPasswordSSID: ""
    property string wifiPasswordInput: ""
    property string wifiUsernameInput: ""
    property bool requiresEnterprise: false
    property bool isHiddenNetwork: false

    property string wifiAnonymousIdentityInput: ""
    property string wifiDomainInput: ""
    property string eapMethodValue: "peap"
    property string phase2AuthValue: "mschapv2"

    property bool isPromptMode: false
    property string promptToken: ""
    property string promptReason: ""
    property var promptFields: []
    property var promptHints: []
    property string promptSetting: ""

    property bool isVpnPrompt: false
    property string connectionName: ""
    property string vpnServiceType: ""
    property string connectionType: ""
    property var fieldsInfo: []
    property var secretValues: ({})

    readonly property bool isCertificateChangedPrompt: promptReason === "server-certificate-changed"
    readonly property bool isCertificatePrompt: promptReason === "server-certificate" || isCertificateChangedPrompt
    readonly property string serverCertificateFingerprint: promptHints.length > 0 ? promptHints[0] : ""
    readonly property string vpnPromptMessage: {
        const hint = promptHints.find(h => typeof h === "string" && h.startsWith("x-vpn-message:"));
        return hint ? hint.slice("x-vpn-message:".length) : "";
    }
    readonly property bool isChallengePrompt: promptHints.some(h => typeof h === "string" && h.startsWith("x-dynamic-challenge"))
    readonly property bool showUsernameField: requiresEnterprise && !isVpnPrompt && fieldsInfo.length === 0
    readonly property bool showPasswordField: fieldsInfo.length === 0 && !isCertificatePrompt
    readonly property bool showEapFields: requiresEnterprise && !isVpnPrompt && !isPromptMode
    readonly property bool showPhase2Dropdown: eapMethodValue === "peap" || eapMethodValue === "ttls"
    readonly property bool showAnonField: requiresEnterprise && !isVpnPrompt && !isPromptMode && eapMethodValue !== "pwd"
    readonly property bool showDomainField: showAnonField
    readonly property bool showSavePasswordCheckbox: (isVpnPrompt || fieldsInfo.length > 0) && promptReason !== "pkcs11" && !isCertificatePrompt && !isChallengePrompt

    readonly property int certificateWarningHeight: certificateWarningColumn.implicitHeight + Theme.spacingM * 2

    function focusFirstField() {
        if (isCertificatePrompt) {
            connectButton.forceActiveFocus();
            return;
        }
        if (fieldsInfo.length > 0) {
            if (dynamicFieldsRepeater.count > 0) {
                const firstItem = dynamicFieldsRepeater.itemAt(0);
                if (firstItem)
                    firstItem.forceActiveFocus();
            }
            return;
        }
        if (isHiddenNetwork) {
            ssidInput.forceActiveFocus();
            return;
        }
        if (requiresEnterprise && !isVpnPrompt) {
            usernameInput.forceActiveFocus();
            return;
        }
        passwordInput.forceActiveFocus();
    }

    function show(ssid) {
        wifiPasswordSSID = ssid;
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        wifiAnonymousIdentityInput = "";
        wifiDomainInput = "";
        eapMethodValue = "peap";
        phase2AuthValue = "mschapv2";
        isPromptMode = false;
        isHiddenNetwork = false;
        promptToken = "";
        promptReason = "";
        promptFields = [];
        promptHints = [];
        promptSetting = "";
        isVpnPrompt = false;
        connectionName = "";
        vpnServiceType = "";
        connectionType = "";
        fieldsInfo = [];
        secretValues = {};

        const network = NetworkService.wifiNetworks.find(n => n.ssid === ssid);
        requiresEnterprise = network?.enterprise || false;

        open();
        Qt.callLater(focusFirstField);
    }

    function showHidden() {
        wifiPasswordSSID = "";
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        wifiAnonymousIdentityInput = "";
        wifiDomainInput = "";
        eapMethodValue = "peap";
        phase2AuthValue = "mschapv2";
        isPromptMode = false;
        isHiddenNetwork = true;
        promptToken = "";
        promptReason = "";
        promptFields = [];
        promptHints = [];
        promptSetting = "";
        isVpnPrompt = false;
        connectionName = "";
        vpnServiceType = "";
        connectionType = "";
        fieldsInfo = [];
        secretValues = {};
        requiresEnterprise = false;

        open();
        Qt.callLater(focusFirstField);
    }

    function showFromPrompt(token, ssid, setting, fields, hints, reason, connType, connName, vpnService, fInfo) {
        isPromptMode = true;
        promptToken = token;
        promptReason = reason;
        promptFields = fields || [];
        promptHints = hints || [];
        promptSetting = setting || "802-11-wireless-security";
        connectionType = connType || "802-11-wireless";
        connectionName = connName || ssid || "";
        vpnServiceType = vpnService || "";
        fieldsInfo = fInfo || [];
        secretValues = {};

        isVpnPrompt = (connectionType === "vpn" || connectionType === "wireguard");
        wifiPasswordSSID = isVpnPrompt ? connectionName : ssid;
        savePasswordCheckbox.checked = !isVpnPrompt;

        requiresEnterprise = setting === "802-1x";

        wifiPasswordInput = "";
        wifiUsernameInput = "";
        wifiAnonymousIdentityInput = "";
        wifiDomainInput = "";
        eapMethodValue = "peap";
        phase2AuthValue = "mschapv2";

        open();
        Qt.callLater(() => {
            if (reason === "wrong-password" && fieldsInfo.length === 0) {
                passwordInput.text = "";
            }
            focusFirstField();
        });
    }

    function hide() {
        close();
    }

    function getFieldLabel(fieldName) {
        switch (fieldName) {
        case "username":
        case "identity":
            return I18n.tr("Username");
        case "password":
            return I18n.tr("Password");
        case "cert-pass":
        case "certpass":
            return I18n.tr("Certificate Password");
        case "private-key-password":
            return I18n.tr("Private Key Password");
        case "pin":
        case "key_pass":
            return I18n.tr("PIN", "noun, numeric personal identification number for a smart card");
        case "psk":
            return I18n.tr("Password");
        case "anonymous-identity":
            return I18n.tr("Anonymous Identity");
        default:
            return fieldName.charAt(0).toUpperCase() + fieldName.slice(1).replace(/-/g, " ");
        }
    }

    function submitCredentialsAndClose() {
        if (!connectButton.enabled)
            return;
        if (fieldsInfo.length > 0) {
            NetworkService.submitCredentials(promptToken, secretValues, savePasswordCheckbox.checked);
            hide();
            secretValues = {};
            return;
        }

        if (isPromptMode) {
            const secrets = {};
            if (isVpnPrompt) {
                if (passwordInput.text)
                    secrets["password"] = passwordInput.text;
            } else if (promptSetting === "802-11-wireless-security") {
                secrets["psk"] = passwordInput.text;
            } else if (promptSetting === "802-1x") {
                if (usernameInput.text)
                    secrets["identity"] = usernameInput.text;
                if (passwordInput.text)
                    secrets["password"] = passwordInput.text;
                if (wifiAnonymousIdentityInput)
                    secrets["anonymous-identity"] = wifiAnonymousIdentityInput;
            }
            NetworkService.submitCredentials(promptToken, secrets, savePasswordCheckbox.checked);
        } else {
            const ssid = isHiddenNetwork ? ssidInput.text : wifiPasswordSSID;
            const username = requiresEnterprise ? usernameInput.text : "";
            const anonIdentity = showAnonField ? wifiAnonymousIdentityInput : "";
            const domainMatch = showDomainField ? wifiDomainInput : "";
            const eap = requiresEnterprise ? eapMethodValue : "";
            const phase2 = requiresEnterprise && showPhase2Dropdown ? phase2AuthValue : "";
            NetworkService.connectToWifi(ssid, passwordInput.text, username, anonIdentity, domainMatch, isHiddenNetwork, eap, phase2);
        }

        hide();
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        wifiAnonymousIdentityInput = "";
        wifiDomainInput = "";
        passwordInput.text = "";
        if (requiresEnterprise)
            usernameInput.text = "";
        if (isHiddenNetwork)
            ssidInput.text = "";
    }

    function clearAndClose() {
        if (isPromptMode)
            NetworkService.cancelCredentials(promptToken);
        hide();
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        wifiAnonymousIdentityInput = "";
        wifiDomainInput = "";
        secretValues = {};
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            Qt.callLater(focusFirstField);
            return;
        }
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        wifiAnonymousIdentityInput = "";
        wifiDomainInput = "";
        secretValues = {};
        passwordInput.text = "";
        usernameInput.text = "";
        anonInput.text = "";
        domainMatchInput.text = "";
        ssidInput.text = "";
        for (var i = 0; i < dynamicFieldsRepeater.count; i++) {
            const item = dynamicFieldsRepeater.itemAt(i);
            if (item)
                item.text = "";
        }
    }

    Connections {
        target: NetworkService

        function onPasswordDialogShouldReopenChanged() {
            if (!NetworkService.passwordDialogShouldReopen || NetworkService.connectingSSID === "")
                return;
            wifiPasswordSSID = NetworkService.connectingSSID;
            wifiPasswordInput = "";
            open();
            NetworkService.passwordDialogShouldReopen = false;
        }
    }

    DDialog {
        id: contentFocusScope

        anchors.fill: parent
        focus: root.shouldBeVisible
        acceptEnabled: connectButton.enabled
        onAccepted: submitCredentialsAndClose()
        onRejected: clearAndClose()
        title: {
            if (promptReason === "pkcs11")
                return I18n.tr("Smartcard Authentication");
            if (isCertificatePrompt)
                return I18n.tr("Untrusted VPN certificate", "Title for VPN server certificate trust confirmation");
            if (isVpnPrompt)
                return I18n.tr("Connect to VPN");
            if (isHiddenNetwork)
                return I18n.tr("Connect to Hidden Network");
            return I18n.tr("Connect to Wi-Fi");
        }
        supportingText: {
            if (promptReason === "pkcs11")
                return I18n.tr("Enter PIN for %1", "%1 is the device or network name").arg(wifiPasswordSSID);
            if (isCertificatePrompt)
                return wifiPasswordSSID;
            if (vpnPromptMessage)
                return vpnPromptMessage;
            if (fieldsInfo.length > 0)
                return I18n.tr("Enter credentials for %1", "%1 is the network name").arg(wifiPasswordSSID);
            if (isVpnPrompt)
                return I18n.tr("Enter password for %1", "%1 is the network name").arg(wifiPasswordSSID);
            if (isHiddenNetwork)
                return I18n.tr("Enter network name and password");
            return (requiresEnterprise ? I18n.tr("Enter credentials for %1", "%1 is the network name") : I18n.tr("Enter password for %1", "%1 is the network name")).arg(wifiPasswordSSID);
        }

        Rectangle {
            id: certificateWarningBox

            readonly property color warningTone: isCertificateChangedPrompt ? Theme.error : Theme.warning

            width: parent.width
            height: certificateWarningHeight
            radius: Theme.cornerRadius
            color: Theme.withAlpha(warningTone, 0.12)
            border.color: Theme.withAlpha(warningTone, 0.5)
            border.width: 1
            visible: isCertificatePrompt

            Column {
                id: certificateWarningColumn

                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: isCertificateChangedPrompt ? I18n.tr("The server certificate has changed since it was last trusted. Only continue if you recognize the new fingerprint.", "Warning shown when a trusted VPN server certificate no longer matches") : I18n.tr("Only continue if you recognize this server certificate fingerprint.", "Warning shown before trusting an unverified VPN server certificate")
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                StyledText {
                    width: parent.width
                    text: serverCertificateFingerprint
                    wrapMode: Text.WrapAnywhere
                    font.family: SettingsData.monoFontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: certificateWarningBox.warningTone
                }
            }
        }

        DTextField {
            id: ssidInput
            visible: isHiddenNetwork
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            leftIconName: "wifi"

            width: parent.width
            font.pixelSize: Theme.fontSizeMedium
            textColor: Theme.surfaceText
            labelText: I18n.tr("Network Name (SSID)")
            enabled: root.shouldBeVisible

            onAccepted: passwordInput.forceActiveFocus()
        }

        Repeater {
            id: dynamicFieldsRepeater
            model: fieldsInfo

            delegate: DTextField {
                id: fieldInput
                required property var modelData
                required property int index
                outlined: true
                controlHeight: Theme.fieldHeightLarge
                leftIconName: modelData.isSecret ? "lock" : "person"
                width: contentFocusScope.contentItem.width
                font.pixelSize: Theme.fontSizeMedium
                textColor: Theme.surfaceText
                showPasswordToggle: modelData.isSecret
                isError: modelData.isSecret && isPromptMode && promptReason === "wrong-password" && text.length === 0
                supportingText: isError ? I18n.tr("Incorrect password") : ""
                echoMode: modelData.isSecret && !passwordVisible ? TextInput.Password : TextInput.Normal
                labelText: getFieldLabel(modelData.name)
                enabled: root.shouldBeVisible

                onTextEdited: {
                    let updated = Object.assign({}, root.secretValues);
                    updated[modelData.name] = text;
                    root.secretValues = updated;
                }

                onAccepted: {
                    if (index < fieldsInfo.length - 1) {
                        const nextItem = dynamicFieldsRepeater.itemAt(index + 1);
                        if (nextItem)
                            nextItem.forceActiveFocus();
                        return;
                    }
                    submitCredentialsAndClose();
                }
            }
        }

        Row {
            id: eapSelectorRow

            visible: showEapFields
            width: parent.width
            spacing: Theme.spacingM

            Column {
                width: showPhase2Dropdown ? (parent.width - Theme.spacingM) / 2 : parent.width
                spacing: Theme.spacingXS

                StyledText {
                    text: I18n.tr("Authentication")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                DDropdown {
                    width: parent.width
                    dropdownWidth: parent.width
                    compactMode: true
                    options: ["PEAP", "TTLS", "PWD"]
                    currentValue: eapMethodValue.toUpperCase()
                    onValueChanged: value => {
                        eapMethodValue = value.toLowerCase();
                        phase2AuthValue = eapMethodValue === "ttls" ? "pap" : "mschapv2";
                    }
                }
            }

            Column {
                visible: showPhase2Dropdown
                width: (parent.width - Theme.spacingM) / 2
                spacing: Theme.spacingXS

                StyledText {
                    text: I18n.tr("Inner authentication", "802.1X phase 2 authentication method")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                DDropdown {
                    width: parent.width
                    dropdownWidth: parent.width
                    compactMode: true
                    options: eapMethodValue === "ttls" ? ["PAP", "MSCHAPv2", "MSCHAP", "CHAP", "GTC", "MD5"] : ["MSCHAPv2", "GTC", "MD5"]
                    currentValue: phase2AuthValue === "mschapv2" ? "MSCHAPv2" : phase2AuthValue.toUpperCase()
                    onValueChanged: value => phase2AuthValue = value.toLowerCase()
                }
            }
        }

        DTextField {
            id: usernameInput
            visible: showUsernameField
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            leftIconName: "person"

            width: parent.width
            font.pixelSize: Theme.fontSizeMedium
            textColor: Theme.surfaceText
            text: wifiUsernameInput
            labelText: I18n.tr("Username", "text field label for network, vpn and account forms")
            enabled: root.shouldBeVisible

            onTextEdited: wifiUsernameInput = text
            onAccepted: passwordInput.forceActiveFocus()
        }

        DTextField {
            id: passwordInput
            visible: showPasswordField
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            leftIconName: "lock"

            width: parent.width
            font.pixelSize: Theme.fontSizeMedium
            textColor: Theme.surfaceText
            text: wifiPasswordInput
            showPasswordToggle: true
            isError: isPromptMode && promptReason === "wrong-password" && text.length === 0
            supportingText: isError ? I18n.tr("Incorrect password") : ""
            echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
            labelText: promptReason === "pkcs11" ? I18n.tr("PIN", "noun, numeric personal identification number for a smart card") : I18n.tr("Password")
            enabled: root.shouldBeVisible

            onTextEdited: wifiPasswordInput = text
            onAccepted: {
                if (showAnonField) {
                    anonInput.forceActiveFocus();
                    return;
                }
                submitCredentialsAndClose();
            }
        }

        DTextField {
            id: anonInput
            visible: showAnonField
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            leftIconName: "person_off"

            width: parent.width
            font.pixelSize: Theme.fontSizeMedium
            textColor: Theme.surfaceText
            text: wifiAnonymousIdentityInput
            labelText: I18n.tr("Anonymous Identity (optional)")
            enabled: root.shouldBeVisible

            onTextEdited: wifiAnonymousIdentityInput = text
            onAccepted: domainMatchInput.forceActiveFocus()
        }

        DTextField {
            id: domainMatchInput
            visible: showDomainField
            outlined: true
            controlHeight: Theme.fieldHeightLarge
            leftIconName: "domain"

            width: parent.width
            font.pixelSize: Theme.fontSizeMedium
            textColor: Theme.surfaceText
            text: wifiDomainInput
            labelText: I18n.tr("Domain (optional)")
            enabled: root.shouldBeVisible

            onTextEdited: wifiDomainInput = text
            onAccepted: submitCredentialsAndClose()
        }

        DToggle {
            id: savePasswordCheckbox

            width: parent.width
            text: I18n.tr("Save password")
            visible: showSavePasswordCheckbox
            checked: !isVpnPrompt
            onToggled: checked => savePasswordCheckbox.checked = checked
        }

        actions: [
            DButton {
                maximumWidth: contentFocusScope.actionWidth
                wrapText: true
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: clearAndClose()
            },
            DButton {
                id: connectButton
                maximumWidth: contentFocusScope.actionWidth
                wrapText: true

                text: isCertificatePrompt ? I18n.tr("Trust", "Button that approves a VPN server certificate fingerprint") : I18n.tr("Connect", "verb, connect to a network or device")
                enabled: {
                    if (fieldsInfo.length > 0) {
                        for (var i = 0; i < fieldsInfo.length; i++) {
                            if (!fieldsInfo[i].isSecret)
                                continue;
                            const fieldName = fieldsInfo[i].name;
                            if (!secretValues[fieldName] || secretValues[fieldName].length === 0)
                                return false;
                        }
                        return true;
                    }
                    if (isCertificatePrompt)
                        return serverCertificateFingerprint.length > 0;
                    if (isVpnPrompt)
                        return passwordInput.text.length > 0;
                    if (isHiddenNetwork)
                        return ssidInput.text.length > 0;
                    return requiresEnterprise ? (usernameInput.text.length > 0 && passwordInput.text.length > 0) : passwordInput.text.length > 0;
                }
                onClicked: submitCredentialsAndClose()
            }
        ]
    }
}
