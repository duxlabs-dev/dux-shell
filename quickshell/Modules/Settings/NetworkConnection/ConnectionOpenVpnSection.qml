pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property int rev: editor.revision
    readonly property var vpnData: {
        rev;
        return editor.draft?.vpn?.data ?? {};
    }
    readonly property var secrets: {
        rev;
        return editor.draft?.vpn?.secrets ?? {};
    }

    readonly property string type: vpnData["connection-type"] ?? "tls"
    property bool advancedOpen: false
    readonly property bool usesCerts: type === "tls" || type === "password-tls"
    readonly property bool usesPassword: type === "password" || type === "password-tls"
    readonly property bool valid: String(vpnData.remote ?? "").trim() !== ""

    readonly property var typeChoices: [
        {
            "label": I18n.tr("Certificates (TLS)", "OpenVPN authentication type"),
            "value": "tls"
        },
        {
            "label": I18n.tr("Password"),
            "value": "password"
        },
        {
            "label": I18n.tr("Password and certificates", "OpenVPN authentication type"),
            "value": "password-tls"
        },
        {
            "label": I18n.tr("Static key", "OpenVPN key file field"),
            "value": "static-key"
        }
    ]
    readonly property var directionChoices: [
        {
            "label": I18n.tr("None"),
            "value": ""
        },
        {
            "label": "0",
            "value": "0"
        },
        {
            "label": "1",
            "value": "1"
        }
    ]
    readonly property var protocolChoices: [
        {
            "label": "UDP",
            "value": "no"
        },
        {
            "label": "TCP",
            "value": "yes"
        }
    ]
    readonly property var deviceChoices: [
        {
            "label": "TUN",
            "value": "tun"
        },
        {
            "label": "TAP",
            "value": "tap"
        }
    ]

    // Only the keys this form owns are ever written; the rest of vpn.data/secrets is copied as is.
    function setData(key, text) {
        editor.setValue("vpn", "data", CE.withDataEntry(vpnData, key, text));
    }

    function setNumber(key, text) {
        const n = parseInt(text, 10);
        setData(key, n > 0 ? String(n) : "");
    }

    function setSecret(key, text) {
        if (String(secrets[key] ?? "") === text)
            return;
        editor.setValue("vpn", "secrets", CE.secretsWith(secrets, key, text, editor.original?.vpn?.secrets));
    }

    function setSaved(key, saved) {
        editor.setValue("vpn", "data", CE.withSecretSaved(vpnData, key, saved));
        // An unsaved secret is asked on connect, so neither a typed nor a stored one is kept.
        const stored = editor.original?.vpn?.secrets?.[key];
        if (!saved)
            setSecret(key, "");
        else if (secrets[key] === null && stored)
            setSecret(key, stored);
    }

    ConnectionCertBrowser {
        id: certBrowser
        onPicked: (key, path) => root.setData(key, path)
    }

    component TextRow: ConnectionSyncedRow {
        id: textRow
        required property var host
        required property string dataKey

        stored: host.vpnData[dataKey] ?? ""
        commit: t => textRow.host.setData(textRow.dataKey, t)
    }

    component PathRow: ConnectionPathRow {
        id: pathRow
        required property var host
        required property string dataKey

        browser: certBrowser
        target: dataKey
        stored: host.vpnData[dataKey] ?? ""
        commit: t => pathRow.host.setData(pathRow.dataKey, t)
    }

    component NumberRow: ConnectionSyncedRow {
        id: numberRow
        required property var host
        required property string dataKey

        stored: host.vpnData[dataKey] ?? ""
        validator: IntValidator {
            bottom: 0
        }
        commit: t => numberRow.host.setNumber(numberRow.dataKey, t)
    }

    component ChoiceRow: ConnectionChoiceRow {
        id: choiceRow
        required property var host
        required property string dataKey
        property string fallback: ""

        stored: host.vpnData[dataKey] ?? fallback
        onPicked: v => choiceRow.host.setData(choiceRow.dataKey, v === choiceRow.fallback ? "" : v)
    }

    component SecretRow: SettingsRow {
        id: secretRow
        required property var host
        required property string secretKey
        property alias label: field.labelText

        body: DTextField {
            id: field
            width: parent.width
            outlined: true
            echoMode: TextInput.Password
            showPasswordToggle: true
            enabled: CE.secretSaved(secretRow.host.vpnData, secretRow.secretKey)
            text: secretRow.host.secrets[secretRow.secretKey] ?? ""
            onTextEdited: secretRow.host.setSecret(secretRow.secretKey, text)
        }
    }

    component SavedRow: SettingsToggleRow {
        required property var host
        required property string secretKey

        text: I18n.tr("Save password")
        checked: CE.secretSaved(host.vpnData, secretKey)
        onToggled: checked => host.setSaved(secretKey, checked)
    }

    title: "OpenVPN"
    enabled: !editor.readOnly

    TextRow {
        host: root
        dataKey: "remote"
        text: I18n.tr("Gateway", "network IP setting label")
        isError: !root.valid
    }

    ConnectionChoiceRow {
        text: I18n.tr("Type")
        choices: root.typeChoices
        stored: root.type
        onPicked: value => root.setData("connection-type", value)
    }

    PathRow {
        visible: root.usesCerts || root.type === "password"
        host: root
        dataKey: "ca"
        text: I18n.tr("CA certificate", "network authentication certificate file field")
    }

    PathRow {
        visible: root.usesCerts
        host: root
        dataKey: "cert"
        text: I18n.tr("Client certificate", "network authentication certificate file field")
    }

    PathRow {
        visible: root.usesCerts
        host: root
        dataKey: "key"
        text: I18n.tr("Private key", "network authentication key file field")
    }

    SecretRow {
        visible: root.usesCerts
        host: root
        secretKey: "cert-pass"
        label: I18n.tr("Private Key Password")
    }

    SavedRow {
        visible: root.usesCerts
        host: root
        secretKey: "cert-pass"
    }

    TextRow {
        visible: root.usesPassword
        host: root
        dataKey: "username"
        text: I18n.tr("Username")
    }

    SecretRow {
        visible: root.usesPassword
        host: root
        secretKey: "password"
        label: I18n.tr("Password")
    }

    SavedRow {
        visible: root.usesPassword
        host: root
        secretKey: "password"
    }

    PathRow {
        visible: root.type === "static-key"
        host: root
        dataKey: "static-key"
        text: I18n.tr("Static key", "OpenVPN key file field")
    }

    ChoiceRow {
        visible: root.type === "static-key"
        host: root
        dataKey: "static-key-direction"
        choices: root.directionChoices
        text: I18n.tr("Direction")
    }

    TextRow {
        visible: root.type === "static-key"
        host: root
        dataKey: "local-ip"
        text: I18n.tr("Local IP address", "OpenVPN tunnel field")
    }

    TextRow {
        visible: root.type === "static-key"
        host: root
        dataKey: "remote-ip"
        text: I18n.tr("Remote IP address", "OpenVPN tunnel field")
    }

    SettingsFoldRow {
        id: advanced
        title: I18n.tr("Advanced")
        open: root.advancedOpen
        onToggled: root.advancedOpen = !root.advancedOpen
    }

    NumberRow {
        visible: advanced.open
        host: root
        dataKey: "port"
        text: I18n.tr("Port")
    }

    ChoiceRow {
        visible: advanced.open
        host: root
        dataKey: "proto-tcp"
        fallback: "no"
        choices: root.protocolChoices
        text: I18n.tr("Protocol")
    }

    ChoiceRow {
        visible: advanced.open
        host: root
        dataKey: "dev-type"
        fallback: "tun"
        choices: root.deviceChoices
        text: I18n.tr("Device")
    }

    TextRow {
        visible: advanced.open
        host: root
        dataKey: "cipher"
        text: I18n.tr("Cipher")
    }

    TextRow {
        visible: advanced.open
        host: root
        dataKey: "auth"
        text: I18n.tr("Auth")
    }

    NumberRow {
        visible: advanced.open
        host: root
        dataKey: "tunnel-mtu"
        text: "MTU"
    }

    PathRow {
        visible: advanced.open
        host: root
        dataKey: "ta"
        text: I18n.tr("TLS authentication key", "OpenVPN key file field")
    }

    ChoiceRow {
        visible: advanced.open
        host: root
        dataKey: "ta-dir"
        choices: root.directionChoices
        text: I18n.tr("Direction")
    }
}
