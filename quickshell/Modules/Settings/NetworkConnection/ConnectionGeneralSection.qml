import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as ConnectionEditor

SettingsCard {
    id: root

    required property var editor
    readonly property bool valid: name !== ""

    readonly property int rev: editor.revision
    readonly property string name: {
        rev;
        return String(editor.value("connection", "id", "")).trim();
    }
    readonly property bool editable: !editor.readOnly
    property var zones: []

    readonly property string connType: {
        rev;
        return String(editor.value("connection", "type", ""));
    }
    readonly property string serviceType: {
        rev;
        return String(editor.value("vpn", "service-type", ""));
    }
    readonly property string uuid: {
        rev;
        return String(editor.profile?.uuid ?? editor.value("connection", "uuid", ""));
    }
    readonly property bool vpnTypes: NetworkService.connectionEditorSupported
    readonly property bool vpnKind: ConnectionEditor.groupOf(connType) === "vpn"
    readonly property var typeOptions: {
        const out = ConnectionEditor.CONNECTION_TYPES.filter(t => t.addable && t.group !== "vpn").map(t => ({
                    "value": t.type,
                    "label": editor.typeLabel(t.type)
                }));
        if (vpnTypes)
            out.push({
                "value": "vpn",
                "label": I18n.tr("VPN", "connection editor: VPN kind dropdown label")
            });
        return out;
    }
    readonly property var vpnKindOptions: [
        {
            "value": "wireguard",
            "label": editor.typeLabel("wireguard")
        }
    ].concat((VPNService.plugins ?? []).map(p => ({
                "value": "vpn:" + p.serviceType,
                "label": VPNService.getPluginName(p.serviceType)
            })))
    readonly property string typeValue: connType === "vpn" ? "vpn:" + serviceType : connType
    readonly property var meteredLabels: [I18n.tr("Auto"), I18n.tr("Yes"), I18n.tr("No")]
    readonly property var vpnProfiles: {
        rev;
        return (editor.profiles ?? []).filter(p => ConnectionEditor.groupOf(p.type) === "vpn");
    }

    // Export writes the saved profile, so the name comes from it rather than the draft.
    function exportFileName() {
        const saved = editor.original?.connection ?? {};
        const id = String(saved.id ?? "");
        if (connType === "wireguard")
            return String(saved["interface-name"] || id) + ".conf";
        return id + (serviceType.endsWith(".openvpn") ? ".ovpn" : ".conf");
    }

    function openExport() {
        exportBrowser.active = true;
        if (exportBrowser.item)
            exportBrowser.item.open();
    }

    // 3 and 4 (guess yes/no) display as Auto
    function meteredIndex() {
        const m = Number(editor.value("connection", "metered", 0));
        return m === 1 ? 1 : (m === 2 ? 2 : 0);
    }

    function storedZone() {
        return String(editor.value("connection", "zone", ""));
    }

    function zoneOptions() {
        const stored = storedZone();
        const opts = [I18n.tr("Default")].concat(zones);
        if (stored !== "" && zones.indexOf(stored) < 0)
            opts.push(stored);
        return opts;
    }

    function storedVpn() {
        const list = editor.value("connection", "secondaries", []);
        return list && list.length > 0 ? String(list[0]) : "";
    }

    // Index 0 is None; repeated names get a " (n)" suffix so each label maps to one profile.
    function vpnOptions() {
        const seen = {};
        return [I18n.tr("None")].concat(vpnProfiles.map(p => {
            const n = seen[p.id] = (seen[p.id] || 0) + 1;
            return n > 1 ? p.id + " (" + n + ")" : p.id;
        }));
    }

    function vpnLabel() {
        const uuid = storedVpn();
        if (uuid === "")
            return I18n.tr("None");
        const i = vpnProfiles.findIndex(x => x.uuid === uuid);
        return i >= 0 ? vpnOptions()[i + 1] : uuid;
    }

    title: I18n.tr("General")

    headerActions: Row {
        spacing: Theme.spacingXS

        DActionButton {
            visible: !root.editor.isNew && (root.connType === "wireguard" || root.connType === "vpn")
            iconName: "file_save"
            iconSize: Theme.iconSizeSmall
            tooltipText: I18n.tr("Export", "save a connection profile to a file")
            onClicked: root.openExport()
        }

        DActionButton {
            visible: !root.editor.isNew && NetworkService.externalConnectionEditor !== ""
            iconName: "open_in_new"
            iconSize: Theme.iconSizeSmall
            tooltipText: I18n.tr("Open in %1", "%1 is an application name").arg(NetworkService.externalConnectionEditor)
            onClicked: NetworkService.openExternalConnectionEditor(root.uuid)
        }
    }

    LazyLoader {
        id: exportBrowser
        active: false

        FileBrowserModal {
            browserTitle: I18n.tr("Export", "save a connection profile to a file")
            bucket: "vpn"
            saveMode: true
            defaultFileName: root.exportFileName()
            onAccepted: paths => {
                NetworkService.exportConnection(root.uuid, paths[0], r => {
                    if (r?.error)
                        ToastService.showError(I18n.tr("Failed to export", "toast title when exporting a network connection fails"), r.error);
                    else
                        ToastService.showInfo(I18n.tr("Saved"));
                });
            }
        }
    }

    Component.onCompleted: {
        if (vpnTypes && (VPNService.plugins ?? []).length === 0)
            VPNService.fetchPlugins();
        NetworkService.listFirewallZones(response => {
            const list = response?.result;
            if (Array.isArray(list))
                root.zones = list;
        });
    }

    SettingsDropdownRow {
        visible: root.editor.isNew && ConnectionEditor.groupOf(SettingsUiState.newConnectionType) !== "vpn"
        enabled: root.editable
        text: I18n.tr("Type")
        options: root.typeOptions.map(t => t.label)
        currentValue: root.typeOptions.find(t => t.value === (root.vpnKind ? "vpn" : root.connType))?.label ?? ""
        onValueChanged: value => {
            const t = root.typeOptions.find(x => x.label === value);
            if (!t || (t.value === "vpn" ? root.vpnKind : t.value === root.connType))
                return;
            root.editor.resetNew(t.value === "vpn" ? "wireguard" : t.value, true);
        }
    }

    SettingsDropdownRow {
        visible: root.editor.isNew && root.vpnKind
        enabled: root.editable
        text: I18n.tr("VPN", "connection editor: VPN kind dropdown label")
        options: root.vpnKindOptions.map(t => t.label)
        currentValue: root.vpnKindOptions.find(t => t.value === root.typeValue)?.label ?? ""
        onValueChanged: value => {
            const t = root.vpnKindOptions.find(x => x.label === value);
            if (t && t.value !== root.typeValue)
                root.editor.resetNew(t.value, true);
        }
    }

    SettingsTextFieldRow {
        enabled: root.editable
        text: I18n.tr("Name")
        value: {
            root.rev;
            return String(root.editor.value("connection", "id", ""));
        }
        isError: root.name === ""
        onValueEdited: value => root.editor.setValue("connection", "id", value)
    }

    SettingsToggleRow {
        enabled: root.editable
        text: I18n.tr("Autoconnect")
        checked: {
            root.rev;
            return root.editor.value("connection", "autoconnect", true) !== false;
        }
        onToggled: checked => root.editor.setValue("connection", "autoconnect", checked)
    }

    SettingsTextFieldRow {
        enabled: root.editable
        text: I18n.tr("Priority")
        value: {
            root.rev;
            return String(root.editor.value("connection", "autoconnect-priority", 0));
        }
        validator: IntValidator {
            bottom: -999
            top: 999
        }
        onEditingFinished: value => {
            const current = Number(root.editor.value("connection", "autoconnect-priority", 0));
            const n = value.trim() === "" ? 0 : parseInt(value, 10);
            if (!isNaN(n) && n !== current)
                root.editor.setValue("connection", "autoconnect-priority", n);
        }
    }

    SettingsDropdownRow {
        enabled: root.editable
        text: I18n.tr("Metered", "network connection setting")
        options: root.meteredLabels
        currentValue: {
            root.rev;
            return root.meteredLabels[root.meteredIndex()];
        }
        onValueChanged: value => {
            const i = root.meteredLabels.indexOf(value);
            if (i >= 0 && i !== root.meteredIndex())
                root.editor.setValue("connection", "metered", i);
        }
    }

    SettingsDropdownRow {
        visible: root.zones.length > 0
        enabled: root.editable
        text: I18n.tr("Firewall zone", "network connection setting")
        options: {
            root.rev;
            return root.zoneOptions();
        }
        currentValue: {
            root.rev;
            return root.storedZone() === "" ? I18n.tr("Default") : root.storedZone();
        }
        onValueChanged: value => {
            const zone = value === I18n.tr("Default") ? "" : value;
            if (zone !== root.storedZone())
                root.editor.setValue("connection", "zone", zone === "" ? undefined : zone);
        }
    }

    SettingsDropdownRow {
        visible: !(root.editor.isNew && root.vpnKind)
        enabled: root.editable
        text: I18n.tr("VPN")
        options: {
            root.rev;
            return root.vpnOptions();
        }
        currentValue: {
            root.rev;
            return root.vpnLabel();
        }
        onValueChanged: value => {
            const i = root.vpnOptions().indexOf(value);
            const uuid = i > 0 ? root.vpnProfiles[i - 1].uuid : "";
            if (uuid !== root.storedVpn())
                root.editor.setValue("connection", "secondaries", uuid === "" ? undefined : [uuid]);
        }
    }

    SettingsNoteRow {
        visible: {
            root.rev;
            const users = root.editor.value("connection", "permissions", []);
            return !users || users.length === 0;
        }
        text: I18n.tr("Available to all users", "network connection editor note, connection is shared with every user of the computer")
        noteIconName: "info"
        tint: Theme.primary
        tintBackground: Theme.primaryHover
    }
}
