pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
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
    function _putData(key, v) {
        const out = Object.assign({}, vpnData);
        if (v === undefined)
            delete out[key];
        else
            out[key] = v;
        editor.setValue("vpn", "data", Object.keys(out).length === 0 ? undefined : out);
    }

    function setData(key, text) {
        const t = text.trim();
        _putData(key, t === "" ? undefined : t);
    }

    function setNumber(key, text) {
        const n = parseInt(text, 10);
        _putData(key, n > 0 ? String(n) : undefined);
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

    function browse(key) {
        browseTarget = key;
        fileBrowserLoader.active = true;
        if (fileBrowserLoader.item)
            fileBrowserLoader.item.open();
    }

    property string browseTarget: ""
    property var fileBrowserLoader: LazyLoader {
        active: false

        FileBrowserModal {
            bucket: "certificate"
            filters: ["*.pem", "*.crt", "*.cer", "*.der", "*.p12", "*.pfx", "*.key", "*"]
            onAccepted: paths => root.setData(root.browseTarget, paths[0])
        }
    }

    component TextRow: ConnectionSyncedRow {
        id: textRow
        required property var host
        required property string dataKey

        stored: host.vpnData[dataKey] ?? ""
        commit: t => textRow.host.setData(textRow.dataKey, t)
    }

    component PathRow: TextRow {
        id: pathRow

        actions: DActionButton {
            iconName: "folder_open"
            tooltipText: I18n.tr("Select File")
            Accessible.name: tooltipText
            onClicked: pathRow.host.browse(pathRow.dataKey)
        }
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

    component ChoiceRow: SettingsDropdownRow {
        required property var host
        required property string dataKey
        required property var list
        property string fallback: ""
        readonly property string current: host.vpnData[dataKey] ?? fallback
        readonly property var choices: CE.withChoice(list, current)

        options: choices.map(c => c.label)
        currentValue: CE.choiceLabel(choices, current)
        onValueChanged: value => {
            const v = CE.choiceValue(choices, value);
            if (v === undefined || v === current)
                return;
            host.setData(dataKey, v === fallback ? "" : v);
        }
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
            leftIconName: "lock"
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

    SettingsDropdownRow {
        readonly property var choices: CE.withChoice(root.typeChoices, root.type)
        text: I18n.tr("Type")
        options: choices.map(c => c.label)
        currentValue: CE.choiceLabel(choices, root.type)
        onValueChanged: value => {
            const v = CE.choiceValue(choices, value);
            if (v !== undefined && v !== root.type)
                root.setData("connection-type", v);
        }
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
        list: root.directionChoices
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

    DCollapsibleSection {
        width: parent.width
        title: I18n.tr("Advanced")

        Column {
            width: parent.width
            spacing: Theme.spacingS

            NumberRow {
                width: parent.width
                host: root
                dataKey: "port"
                text: I18n.tr("Port")
            }

            ChoiceRow {
                width: parent.width
                host: root
                dataKey: "proto-tcp"
                fallback: "no"
                list: root.protocolChoices
                text: I18n.tr("Protocol")
            }

            ChoiceRow {
                width: parent.width
                host: root
                dataKey: "dev-type"
                fallback: "tun"
                list: root.deviceChoices
                text: I18n.tr("Device")
            }

            TextRow {
                width: parent.width
                host: root
                dataKey: "cipher"
                text: I18n.tr("Cipher")
            }

            TextRow {
                width: parent.width
                host: root
                dataKey: "auth"
                text: I18n.tr("Auth")
            }

            NumberRow {
                width: parent.width
                host: root
                dataKey: "tunnel-mtu"
                text: "MTU"
            }

            PathRow {
                width: parent.width
                host: root
                dataKey: "ta"
                text: I18n.tr("TLS authentication key", "OpenVPN key file field")
            }

            ChoiceRow {
                width: parent.width
                host: root
                dataKey: "ta-dir"
                list: root.directionChoices
                text: I18n.tr("Direction")
            }
        }
    }
}
