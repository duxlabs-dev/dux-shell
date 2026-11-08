pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Network
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property string securitySection: "802-11-wireless-security"
    readonly property var modeChoices: [[I18n.tr("Open", "network security type", true), "none"], ["WPA/WPA2", "wpa-psk"], ["WPA3", "sae"], ["OWE", "owe"], [I18n.tr("Enterprise", "wifi security type value, 802.1x enterprise network"), "wpa-eap"]].map(c => ({
                "label": c[0],
                "value": c[1]
            }))

    readonly property bool isWifi: editor.revision >= 0 && editor.hasSection("802-11-wireless")
    readonly property string mode: editor.revision >= 0 ? CE.securityMode(editor.draft) : ""
    readonly property bool knownMode: modeChoices.some(c => c.value === mode)
    readonly property bool locked: editor.readOnly || (isWifi && !knownMode)
    readonly property bool personal: isWifi && (mode === "wpa-psk" || mode === "sae")

    property bool wiredEnterprise: false
    readonly property bool enterpriseActive: isWifi ? mode === "wpa-eap" : wiredEnterprise
    property var enterpriseBaseline: null
    property bool prefilled: false
    readonly property bool enterpriseDirty: enterpriseConfig() !== null

    property bool pskEdited: false
    readonly property string psk: editor.revision >= 0 ? String(editor.value(securitySection, "psk", "") ?? "") : ""
    // A stored or agent-owned key is left alone; a newly chosen personal mode needs one.
    readonly property bool pskRequired: personal && (pskEdited || (psk === "" && CE.securityMode(editor.original) !== mode))
    readonly property bool pskValid: !pskRequired || CE.isValidPsk(psk)

    readonly property bool valid: {
        if (enterpriseActive)
            return !enterpriseDirty || form.valid;
        return pskValid;
    }

    // Re-prefill whenever the host loads a profile.
    readonly property string prefillKey: JSON.stringify([editor.enterpriseOriginal ?? null, editor.original?.["802-1x"] ?? null])

    function enterpriseConfig() {
        if (!prefilled || !enterpriseActive)
            return null;
        const cfg = form.toConfig();
        if (!editor.isNew && enterpriseBaseline && CE.deepEqual(cfg, enterpriseBaseline))
            return null;
        // A path that is still the stored one stays a reference NM reads itself.
        const eo = editor.enterpriseOriginal;
        for (const k of ["caCertPath", "clientCertPath", "privateKeyPath"]) {
            if (!editor.isNew && cfg[k] && cfg[k] === eo?.[k])
                delete cfg[k];
        }
        return cfg;
    }

    function reset() {
        pskEdited = false;
        wiredEnterprise = editor.hasSection("802-1x");
        const stored = editor.original?.["802-1x"] ?? null;
        const eo = editor.enterpriseOriginal;
        form.storedFiles = {
            "ca": stored?.["ca-cert"] === "blob" || !!stored?.["ca-path"],
            "clientCert": stored?.["client-cert"] === "blob",
            "privateKey": stored?.["private-key"] === "blob"
        };
        form.caDisplayName = eo?.caCertPath ?? "";
        // getConnectionEnterprise omits secrets; the original was loaded with them.
        const cfg = eo ? Object.assign({}, eo) : null;
        if (cfg && stored?.password)
            cfg.password = stored.password;
        if (cfg && stored?.["private-key-password"])
            cfg.privateKeyPassword = stored["private-key-password"];
        form.reset(cfg);
        // A stored section is only resent once the user edits the form.
        enterpriseBaseline = stored ? form.toConfig() : null;
        prefilled = true;
    }

    function applyMode(newMode) {
        if (newMode === mode)
            return;
        const out = CE.applySecurityMode(editor.draft, newMode, pskField.text, editor.original);
        editor.setSection(securitySection, out[securitySection] ?? null);
        editor.setSection("802-1x", out["802-1x"] ?? null);
    }

    function setWiredEnterprise(on) {
        wiredEnterprise = on;
        const stored = editor.original?.["802-1x"];
        if (!on)
            editor.setSection("802-1x", null);
        else if (stored && !editor.hasSection("802-1x"))
            editor.setSection("802-1x", CE.copy(stored));
    }

    title: I18n.tr("Security")
    onPrefillKeyChanged: Qt.callLater(reset)
    Component.onCompleted: reset()

    ConnectionChoiceRow {
        visible: root.isWifi
        enabled: !root.locked
        text: I18n.tr("Security")
        choices: root.modeChoices
        stored: root.mode
        onPicked: value => root.applyMode(value)
    }

    SettingsRow {
        visible: root.personal
        enabled: !root.locked
        body: DTextField {
            id: pskField
            width: parent.width
            outlined: true
            labelText: I18n.tr("Password")
            echoMode: TextInput.Password
            showPasswordToggle: true
            isError: !root.pskValid
            supportingText: root.pskValid ? "" : I18n.tr("Password must be 8 to 63 characters, or a 64-digit hex key.", "hotspot password length requirement")
            text: root.psk
            onTextEdited: {
                if (text === root.psk)
                    return;
                root.pskEdited = true;
                // An agent-owned key would be ignored, so a typed one is stored with the profile.
                if (root.editor.value(root.securitySection, "psk-flags", 0) !== 0)
                    root.editor.setValue(root.securitySection, "psk-flags", 0);
                root.editor.setValue(root.securitySection, "psk", text);
            }
        }
    }

    SettingsToggleRow {
        visible: !root.isWifi
        enabled: !root.locked
        text: I18n.tr("Enterprise", "wifi security type value, 802.1x enterprise network")
        checked: root.wiredEnterprise
        onToggled: checked => root.setWiredEnterprise(checked)
    }

    EnterpriseAuthForm {
        id: form
        showIcons: false
        markInvalid: root.enterpriseDirty && root.editor.showErrors
        visible: root.enterpriseActive
        enabled: !root.locked
    }
}
