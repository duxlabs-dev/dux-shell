pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property string sectionKey: "wireguard"
    readonly property int rev: editor.revision
    readonly property var wg: {
        rev;
        return editor.draft?.[sectionKey] ?? {};
    }
    readonly property string originalKey: String(editor.original?.[sectionKey]?.["private-key"] ?? "")
    readonly property string keyValue: String(wg["private-key"] ?? "")

    property string keyText: ""
    property string keyStored: ""
    property string publicKey: ""
    property string publicKeyFor: ""

    property var peers: []
    property bool peersOk: true
    property int peersRev: 0

    // An empty key on a saved profile keeps the stored one.
    readonly property bool keyValid: keyText.trim() === "" ? !editor.isNew : CE.isValidWgKey(keyText.trim())
    readonly property bool valid: ifaceRow.ok && keyValid && portRow.ok && fwmarkRow.ok && mtuRow.ok && peersOk

    title: "WireGuard"
    enabled: !editor.readOnly

    function syncKey() {
        if (keyValue === keyStored)
            return;
        keyStored = keyValue;
        keyText = keyValue;
    }

    function writeKey(text) {
        keyText = text;
        const t = text.trim();
        let next;
        if (t === "")
            next = editor.isNew ? undefined : (originalKey || undefined);
        else if (CE.isValidWgKey(t))
            next = t;
        else
            return;
        keyStored = next ?? "";
        // NM ignores a key whose flags say an agent owns it, so a typed key is stored with the profile.
        if (t !== "" && Number(wg["private-key-flags"] ?? 0) !== 0)
            editor.setValue(sectionKey, "private-key-flags", 0);
        else if (t === "" && !editor.isNew)
            editor.setValue(sectionKey, "private-key-flags", editor.original?.[sectionKey]?.["private-key-flags"]);
        editor.setValue(sectionKey, "private-key", next);
    }

    function generate() {
        const draft = editor.draft;
        NetworkService.wireguardKeys("", response => {
            if (editor.draft !== draft)
                return;
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to generate key", "toast title when generating a WireGuard key pair fails"), String(response.error));
                return;
            }
            publicKey = response.result.publicKey;
            publicKeyFor = response.result.privateKey;
            writeKey(response.result.privateKey);
        });
    }

    function derivePublicKey() {
        const key = keyValue;
        if (!CE.isValidWgKey(key)) {
            publicKey = publicKeyFor = "";
            return;
        }
        if (key === publicKeyFor)
            return;
        publicKey = publicKeyFor = "";
        NetworkService.wireguardKeys(key, response => {
            if (key !== keyValue || response.error)
                return;
            publicKey = response.result.publicKey;
            publicKeyFor = key;
        });
    }

    function writePeers() {
        peersRev++;
        const data = CE.wgPeersFromRows(peers, editor.original?.[sectionKey]?.peers);
        peersOk = data !== null;
        if (data !== null)
            editor.setValue(sectionKey, "peers", data.length > 0 ? data : undefined);
    }

    function addPeer() {
        peers = peers.concat([
            {
                "publicKey": "",
                "allowedIps": "",
                "endpoint": "",
                "presharedKey": "",
                "keepalive": "",
                "extra": {}
            }
        ]);
        writePeers();
    }

    function removePeer(index) {
        peers = peers.filter((_, i) => i !== index);
        writePeers();
    }

    function editPeer(index, key, text) {
        if (String(peers[index][key] ?? "") === text)
            return;
        // Mutates the row in place so the Repeater keeps its delegates and focus.
        peers[index][key] = text;
        writePeers();
    }

    function peerTitle(row, index) {
        const key = String(row.publicKey ?? "").trim();
        const name = key === "" ? "#" + (index + 1) : key.slice(0, 8) + "…";
        const endpoint = String(row.endpoint ?? "").trim();
        return endpoint === "" ? name : name + " · " + endpoint;
    }

    function peerIpsValid(text) {
        // Validates through the peer parser with a dummy valid public key.
        return CE.wgPeersFromRows([
            {
                "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                "allowedIps": text
            }
        ]) !== null;
    }

    function copyPublicKey() {
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", publicKey]);
        ToastService.showInfo(I18n.tr("Copied to clipboard"));
    }

    onKeyValueChanged: {
        syncKey();
        derivePublicKey();
    }

    Component.onCompleted: {
        peers = CE.wgPeerRows(wg.peers);
        syncKey();
        if (editor.isNew && keyValue === "")
            generate();
        else
            derivePublicKey();
    }

    ConnectionSyncedRow {
        id: ifaceRow
        text: I18n.tr("Interface")
        stored: {
            root.rev;
            return String(root.editor.value("connection", "interface-name", ""));
        }
        check: t => CE.isValidIfname(t)
        commit: t => root.editor.setValue("connection", "interface-name", t)
    }

    SettingsRow {
        body: Row {
            width: parent.width
            spacing: Theme.spacingS

            DTextField {
                id: keyField
                width: parent.width - generateButton.width - parent.spacing
                outlined: true
                labelText: I18n.tr("Private key", "WireGuard interface private key field")
                echoMode: TextInput.Password
                showPasswordToggle: true
                isError: !root.keyValid && (root.keyText.trim() !== "" || root.editor.showErrors)
                text: root.keyText
                onTextEdited: {
                    if (text !== root.keyText)
                        root.writeKey(text);
                }
            }

            DActionButton {
                id: generateButton
                y: keyField.containerTop + (keyField.containerHeight - height) / 2
                buttonSize: Theme.iconButtonSize
                iconName: "autorenew"
                tooltipText: I18n.tr("Generate", "create a new WireGuard key pair")
                onClicked: root.generate()
            }
        }
    }

    SettingsRow {
        visible: root.publicKey !== ""
        title: I18n.tr("Public key", "WireGuard key field")
        subtitle: root.publicKey

        DActionButton {
            buttonSize: Theme.iconButtonSize
            iconName: "content_copy"
            tooltipText: I18n.tr("Copy")
            onClicked: root.copyPublicKey()
        }
    }

    ConnectionNumberRow {
        id: portRow
        text: I18n.tr("Listen port", "WireGuard interface field")
        editor: root.editor
        section: root.sectionKey
        key: "listen-port"
        max: 65535
        zeroUnset: true
        placeholderText: I18n.tr("Auto")
    }

    ConnectionNumberRow {
        id: fwmarkRow
        text: "fwmark"
        editor: root.editor
        section: root.sectionKey
        key: "fwmark"
        max: 4294967295
        zeroUnset: true
        placeholderText: I18n.tr("None")
    }

    ConnectionNumberRow {
        id: mtuRow
        text: "MTU"
        editor: root.editor
        section: root.sectionKey
        key: "mtu"
        max: 4294967295
        zeroUnset: true
        placeholderText: I18n.tr("Auto")
    }

    SettingsToggleRow {
        text: I18n.tr("Add routes for allowed IPs", "WireGuard option")
        checked: root.wg["peer-routes"] !== false
        onToggled: checked => {
            const stored = root.editor.original?.[root.sectionKey]?.["peer-routes"] !== undefined;
            root.editor.setValue(root.sectionKey, "peer-routes", checked && !stored ? undefined : checked);
        }
    }

    SettingsRow {
        title: I18n.tr("Peers", "WireGuard peers")

        DButton {
            text: I18n.tr("Add entry")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            variant: "text"
            onClicked: root.addPeer()
        }
    }

    Repeater {
        model: root.peers

        delegate: SettingsRow {
            id: peerRow

            required property var modelData
            required property int index

            title: {
                root.peersRev;
                return root.peerTitle(root.peers[peerRow.index], peerRow.index);
            }

            DActionButton {
                buttonSize: Theme.iconButtonSize
                iconName: "close"
                tooltipText: I18n.tr("Remove", "verb, button that removes an item from a list")
                onClicked: root.removePeer(peerRow.index)
            }

            body: [
                DTextField {
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Public key", "WireGuard key field")
                    text: peerRow.modelData.publicKey
                    isError: text.trim() === "" ? root.editor.showErrors : !CE.isValidWgKey(text.trim())
                    onTextEdited: root.editPeer(peerRow.index, "publicKey", text)
                },
                DTextField {
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Allowed IPs", "WireGuard peer field")
                    placeholderText: "0.0.0.0/0, ::/0"
                    text: peerRow.modelData.allowedIps
                    isError: !root.peerIpsValid(text)
                    onTextEdited: root.editPeer(peerRow.index, "allowedIps", text)
                },
                DTextField {
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Endpoint", "WireGuard peer address and port")
                    placeholderText: "vpn.example.com:51820"
                    text: peerRow.modelData.endpoint
                    isError: text.trim() !== "" && !CE.isValidEndpoint(text)
                    onTextEdited: root.editPeer(peerRow.index, "endpoint", text)
                },
                DTextField {
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Pre-shared key", "WireGuard peer field")
                    echoMode: TextInput.Password
                    showPasswordToggle: true
                    text: peerRow.modelData.presharedKey
                    isError: text.trim() !== "" && !CE.isValidWgKey(text.trim())
                    onTextEdited: root.editPeer(peerRow.index, "presharedKey", text)
                },
                DTextField {
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Persistent keepalive", "WireGuard peer field")
                    placeholderText: I18n.tr("Default")
                    maximumLength: 5
                    text: peerRow.modelData.keepalive
                    isError: !/^\d*$/.test(text.trim()) || Number(text.trim()) > 65535
                    onTextEdited: root.editPeer(peerRow.index, "keepalive", text)
                }
            ]
        }
    }
}
