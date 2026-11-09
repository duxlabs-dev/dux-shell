pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    width: parent?.width ?? 0

    property string wifiPasswordSSID: ""
    property string wifiPasswordInput: ""
    property string wifiUsernameInput: ""
    property bool requiresEnterprise: false
    property bool isHiddenNetwork: false
    property string hiddenSecurity: "wpa-psk"
    property var importProfile: null
    property bool savePassword: true
    property bool inputEnabled: true
    property bool _submitted: false

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
    readonly property bool isWiredPrompt: isPromptMode && !isVpnPrompt && connectionType !== "802-11-wireless"
    readonly property string serverCertificateFingerprint: promptHints.length > 0 ? promptHints[0] : ""
    readonly property string vpnPromptMessage: {
        const hint = promptHints.find(h => typeof h === "string" && h.startsWith("x-vpn-message:"));
        return hint ? hint.slice("x-vpn-message:".length) : "";
    }
    readonly property bool isChallengePrompt: promptHints.some(h => typeof h === "string" && h.startsWith("x-dynamic-challenge"))
    readonly property bool showEnterpriseForm: requiresEnterprise && !isVpnPrompt && !isPromptMode
    readonly property bool hiddenNeedsPassword: hiddenSecurity === "wpa-psk" || hiddenSecurity === "sae"
    readonly property bool showUsernameField: requiresEnterprise && !isVpnPrompt && isPromptMode && fieldsInfo.length === 0
    readonly property bool showPasswordField: fieldsInfo.length === 0 && !isCertificatePrompt && !showEnterpriseForm && (!isHiddenNetwork || hiddenNeedsPassword)
    readonly property bool showSavePasswordCheckbox: isVpnPrompt && promptReason !== "pkcs11" && !isCertificatePrompt && !isChallengePrompt
    readonly property var hiddenSecurityChoices: {
        const choices = [[I18n.tr("Open", "network security type", true), "none"], ["WPA/WPA2", "wpa-psk"], ["WPA3", "sae"], ["OWE", "owe"]];
        if (NetworkService.connectionEditorSupported)
            choices.push([I18n.tr("Enterprise", "wifi security type value, 802.1x enterprise network"), "wpa-eap"]);
        return choices;
    }
    readonly property bool canConnect: {
        if (fieldsInfo.length > 0) {
            for (let i = 0; i < fieldsInfo.length; i++) {
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
        if (isHiddenNetwork && ssidInput.text.length === 0)
            return false;
        if (showEnterpriseForm)
            return enterpriseForm.valid;
        if (isHiddenNetwork)
            return !hiddenNeedsPassword || passwordInput.text.length >= (hiddenSecurity === "wpa-psk" ? 8 : 1);
        return showUsernameField ? (usernameInput.text.length > 0 && passwordInput.text.length > 0) : passwordInput.text.length > 0;
    }

    // An invalid enterprise form keeps Connect enabled; pressing it marks the fields that need input.
    readonly property bool submitEnabled: canConnect || showEnterpriseForm

    readonly property string submitText: isCertificatePrompt ? I18n.tr("Trust", "Button that approves a VPN server certificate fingerprint") : I18n.tr("Connect", "verb, connect to a network or device")

    signal closeRequested
    signal focusSubmitRequested
    signal revealRequested(Item item)

    readonly property string title: {
        if (promptReason === "pkcs11")
            return I18n.tr("Smartcard Authentication");
        if (isCertificatePrompt)
            return I18n.tr("Untrusted VPN certificate", "Title for VPN server certificate trust confirmation");
        if (isVpnPrompt)
            return I18n.tr("Connect to VPN");
        if (isWiredPrompt)
            return I18n.tr("Ethernet");
        if (importProfile)
            return importProfile.providerName || I18n.tr("Connect to Wi-Fi");
        if (isHiddenNetwork)
            return I18n.tr("Connect to Hidden Network");
        return I18n.tr("Connect to Wi-Fi");
    }
    readonly property string supportingText: {
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
            return hiddenNeedsPassword ? I18n.tr("Enter network name and password") : "";
        return (requiresEnterprise ? I18n.tr("Enter credentials for %1", "%1 is the network name") : I18n.tr("Enter password for %1", "%1 is the network name")).arg(wifiPasswordSSID);
    }

    function focusFirstField() {
        if (isCertificatePrompt) {
            focusSubmitRequested();
            return;
        }
        if (fieldsInfo.length > 0) {
            if (dynamicFieldsRepeater.count > 0) {
                const firstItem = dynamicFieldsRepeater.itemAt(0) as DynamicFieldRow;
                if (firstItem)
                    firstItem.field.forceActiveFocus();
            }
            return;
        }
        if (isHiddenNetwork) {
            ssidInput.forceActiveFocus();
            return;
        }
        if (showUsernameField) {
            usernameInput.forceActiveFocus();
            return;
        }
        if (showEnterpriseForm) {
            enterpriseForm.focusIdentity();
            return;
        }
        if (showPasswordField)
            passwordInput.forceActiveFocus();
    }

    function resetState() {
        _submitted = false;
        wifiPasswordSSID = "";
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        requiresEnterprise = false;
        isHiddenNetwork = false;
        hiddenSecurity = "wpa-psk";
        importProfile = null;
        savePassword = true;
        isPromptMode = false;
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
        enterpriseForm.usernameSuffix = "";
        enterpriseForm.usernameSuffixRequired = false;
        enterpriseForm.caDisplayName = "";
        enterpriseForm.markInvalid = false;
        enterpriseForm.reset();
    }

    function show(ssid) {
        resetState();
        wifiPasswordSSID = ssid;
        const network = NetworkService.wifiNetworks.find(n => n.ssid === ssid);
        requiresEnterprise = network?.enterprise || false;
        Qt.callLater(focusFirstField);
    }

    function showHidden() {
        resetState();
        isHiddenNetwork = true;
        Qt.callLater(focusFirstField);
    }

    function showImport(profile, fileName) {
        resetState();
        importProfile = profile;
        wifiPasswordSSID = profile.ssids?.[0] ?? "";
        requiresEnterprise = true;
        enterpriseForm.usernameSuffix = profile.usernameSuffix || "";
        enterpriseForm.usernameSuffixRequired = !!profile.usernameSuffix && !!profile.usernameHint;
        enterpriseForm.caDisplayName = fileName || "";
        enterpriseForm.reset(profile.enterprise);
        Qt.callLater(focusFirstField);
    }

    function showFromPrompt(token, ssid, setting, fields, hints, reason, connType, connName, vpnService, fInfo) {
        resetState();
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

        isVpnPrompt = (connectionType === "vpn" || connectionType === "wireguard");
        wifiPasswordSSID = connectionType === "802-11-wireless" ? ssid : connectionName;
        savePassword = !isVpnPrompt;

        requiresEnterprise = setting === "802-1x";

        Qt.callLater(() => {
            if (reason === "wrong-password" && fieldsInfo.length === 0)
                passwordInput.text = "";
            focusFirstField();
        });
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

    function submitImport() {
        const options = {
            "security": "wpa-eap",
            "enterprise": enterpriseForm.toConfig()
        };
        const ssids = importProfile?.ssids ?? [];
        const visible = ssids.find(s => NetworkService.wifiNetworks.some(n => n.ssid === s));
        if (visible)
            NetworkService.connectToWifi(visible, "", options);
        for (const ssid of ssids) {
            if (ssid !== visible)
                NetworkService.saveWifiProfile(ssid, options, null);
        }
    }

    function submitCredentialsAndClose() {
        if (_submitted)
            return;
        if (!canConnect) {
            if (showEnterpriseForm) {
                enterpriseForm.markInvalid = true;
                Qt.callLater(() => {
                    // A path row reports its field's error too; focus goes to the field.
                    const row = QmlUtils.firstInvalid(root);
                    if (row)
                        root.revealRequested(QmlUtils.firstInvalid(row) ?? row);
                });
            }
            return;
        }
        _submitted = true;
        if (fieldsInfo.length > 0) {
            NetworkService.submitCredentials(promptToken, secretValues, savePassword);
            closeRequested();
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
            }
            NetworkService.submitCredentials(promptToken, secrets, savePassword);
        } else if (importProfile) {
            submitImport();
        } else if (isHiddenNetwork) {
            const options = {
                "hidden": true,
                "security": hiddenSecurity
            };
            if (showEnterpriseForm)
                options.enterprise = enterpriseForm.toConfig();
            NetworkService.connectToWifi(ssidInput.text, hiddenNeedsPassword ? passwordInput.text : "", options);
        } else if (showEnterpriseForm) {
            NetworkService.connectToWifi(wifiPasswordSSID, "", {
                "security": "wpa-eap",
                "enterprise": enterpriseForm.toConfig()
            });
        } else {
            NetworkService.connectToWifi(wifiPasswordSSID, passwordInput.text);
        }

        closeRequested();
    }

    function clearAndClose() {
        if (isPromptMode)
            NetworkService.cancelCredentials(promptToken);
        closeRequested();
    }

    function clearInputs() {
        wifiPasswordInput = "";
        wifiUsernameInput = "";
        secretValues = {};
        enterpriseForm.reset();
        passwordInput.text = "";
        usernameInput.text = "";
        ssidInput.text = "";
        for (let i = 0; i < dynamicFieldsRepeater.count; i++) {
            const item = dynamicFieldsRepeater.itemAt(i) as DynamicFieldRow;
            if (item)
                item.field.text = "";
        }
    }

    component DynamicFieldRow: SettingsRow {
        id: fieldRow

        required property var modelData
        required property int index
        readonly property alias field: fieldInput

        body: DTextField {
            id: fieldInput
            width: parent.width
            outlined: true
            leftIconName: fieldRow.modelData.isSecret ? "lock" : "person"
            showPasswordToggle: fieldRow.modelData.isSecret
            isError: fieldRow.modelData.isSecret && root.isPromptMode && root.promptReason === "wrong-password" && text.length === 0
            supportingText: isError ? I18n.tr("Incorrect password") : ""
            echoMode: fieldRow.modelData.isSecret && !passwordVisible ? TextInput.Password : TextInput.Normal
            labelText: root.getFieldLabel(fieldRow.modelData.name)

            onTextEdited: {
                let updated = Object.assign({}, root.secretValues);
                updated[fieldRow.modelData.name] = text;
                root.secretValues = updated;
            }

            onAccepted: {
                if (fieldRow.index < root.fieldsInfo.length - 1) {
                    const nextItem = dynamicFieldsRepeater.itemAt(fieldRow.index + 1) as DynamicFieldRow;
                    if (nextItem)
                        nextItem.field.forceActiveFocus();
                    return;
                }
                root.submitCredentialsAndClose();
            }
        }
    }

    SettingsCard {
        enabled: root.inputEnabled

        SettingsNoteRow {
            visible: root.isCertificatePrompt
            text: root.isCertificateChangedPrompt ? I18n.tr("The server certificate has changed since it was last trusted. Only continue if you recognize the new fingerprint.", "Warning shown when a trusted VPN server certificate no longer matches") : I18n.tr("Only continue if you recognize this server certificate fingerprint.", "Warning shown before trusting an unverified VPN server certificate")
            tint: root.isCertificateChangedPrompt ? Theme.error : Theme.warning
            tintBackground: root.isCertificateChangedPrompt ? Theme.errorHover : Theme.warningHover
        }

        SettingsNoteRow {
            visible: root.isCertificatePrompt
            noteIconName: ""
            monospace: true
            text: root.serverCertificateFingerprint
            tint: root.isCertificateChangedPrompt ? Theme.error : Theme.warning
            tintBackground: root.isCertificateChangedPrompt ? Theme.errorHover : Theme.warningHover
        }

        SettingsRow {
            visible: root.isHiddenNetwork
            body: DTextField {
                id: ssidInput
                width: parent.width
                outlined: true
                leftIconName: "wifi"
                labelText: I18n.tr("Network Name (SSID)")
                isError: root.showEnterpriseForm && enterpriseForm.markInvalid && !text
                onAccepted: {
                    if (root.showPasswordField)
                        passwordInput.forceActiveFocus();
                }
            }
        }

        SettingsDropdownRow {
            visible: root.isHiddenNetwork
            text: I18n.tr("Security", "noun, settings page name and wifi security type label")
            options: root.hiddenSecurityChoices.map(c => c[0])
            currentValue: root.hiddenSecurityChoices.find(c => c[1] === root.hiddenSecurity)?.[0] ?? ""
            onValueChanged: value => {
                root.hiddenSecurity = root.hiddenSecurityChoices.find(c => c[0] === value)?.[1] ?? "wpa-psk";
                root.requiresEnterprise = root.hiddenSecurity === "wpa-eap";
            }
        }

        Repeater {
            id: dynamicFieldsRepeater
            model: root.fieldsInfo

            delegate: DynamicFieldRow {}
        }

        SettingsRow {
            visible: root.showUsernameField
            body: DTextField {
                id: usernameInput
                width: parent.width
                outlined: true
                leftIconName: "person"
                text: root.wifiUsernameInput
                labelText: I18n.tr("Username", "text field label for network, vpn and account forms")
                onTextEdited: root.wifiUsernameInput = text
                onAccepted: passwordInput.forceActiveFocus()
            }
        }

        SettingsRow {
            visible: root.showPasswordField
            body: DTextField {
                id: passwordInput
                width: parent.width
                outlined: true
                leftIconName: "lock"
                text: root.wifiPasswordInput
                showPasswordToggle: true
                isError: root.isPromptMode && root.promptReason === "wrong-password" && text.length === 0
                readonly property bool pskTooShort: root.isHiddenNetwork && root.hiddenSecurity === "wpa-psk" && text.length > 0 && text.length < 8
                supportingText: isError ? I18n.tr("Incorrect password") : (pskTooShort ? I18n.tr("Password must be 8 to 63 characters, or a 64-digit hex key.", "hotspot password length requirement") : "")
                echoMode: passwordVisible ? TextInput.Normal : TextInput.Password
                labelText: root.promptReason === "pkcs11" ? I18n.tr("PIN", "noun, numeric personal identification number for a smart card") : I18n.tr("Password")
                onTextEdited: root.wifiPasswordInput = text
                onAccepted: root.submitCredentialsAndClose()
            }
        }

        EnterpriseAuthForm {
            id: enterpriseForm
            // System CA needs a server domain, which most users don't know when connecting.
            defaultCa: "none"
            surfaceBrowser: true
            visible: root.showEnterpriseForm
            onSubmitRequested: root.submitCredentialsAndClose()
        }

        SettingsToggleRow {
            visible: root.showSavePasswordCheckbox
            text: I18n.tr("Save password")
            checked: root.savePassword
            onToggled: checked => root.savePassword = checked
        }
    }
}
