pragma ComponentBehavior: Bound

import QtQuick
import "../../Common/ConnectionEditor.js" as CE
import qs.Common
import qs.Modules.Settings.NetworkConnection
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property var parentModal: null

    readonly property string selectedUuid: SettingsUiState.selectedConnectionUuid
    readonly property string newType: SettingsUiState.newConnectionType

    property var original: ({})
    property var draft: null
    property int revision: 0
    property bool readOnly: false
    property bool isNew: false
    property bool unsupported: false
    property var profile: null
    property var profiles: []
    property var enterpriseOriginal: null

    property bool loaded: false
    property string loadError: ""
    property string saveError: ""
    property bool saving: false
    property int loadToken: 0
    property var sectionIds: []
    property var securitySection: null
    // Removed sections are only deleted later; their writes are dropped until the new ones exist.
    property bool swapping: false

    readonly property bool dirty: {
        revision;
        return CE.settingsDiff(original, draft) !== null || (securitySection?.enterpriseDirty ?? false);
    }

    function firstInvalid(item) {
        for (const child of item.children) {
            if (!child.visible)
                continue;
            if (child.isError === true)
                return child;
            const found = firstInvalid(child);
            if (found)
                return found;
        }
        return null;
    }

    function saveOrReveal(persist) {
        for (let i = 0; i < sectionRepeater.count; i++) {
            const section = (sectionRepeater.itemAt(i) as Loader)?.item;
            if (section && section.valid === false) {
                parentModal?.revealItem(firstInvalid(section) ?? section);
                return;
            }
        }
        save(persist);
    }

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    onSelectedUuidChanged: Qt.callLater(root.load)
    onNewTypeChanged: {
        if (selectedUuid === "")
            Qt.callLater(root.load);
    }
    onRevisionChanged: saveError = ""

    Component.onCompleted: {
        NetworkService.addRef();
        NetworkService.probeExternalConnectionEditor();
        Qt.callLater(root.load);
    }

    Component.onDestruction: NetworkService.removeRef()

    function typeLabel(type) {
        if (type === "802-11-wireless")
            return I18n.tr("Wi-Fi");
        if (type === "wireguard")
            return "WireGuard";
        if (type === "vlan")
            return "VLAN";
        if (type === "bridge")
            return I18n.tr("Bridge", "network connection type: network bridge");
        if (type === "pppoe")
            return "DSL";
        if (type === "gsm")
            return I18n.tr("Cellular");
        if (type === "vpn" || type.startsWith("vpn:"))
            return VPNService.getPluginName(type.slice(4)) || I18n.tr("VPN");
        return I18n.tr("Ethernet");
    }

    function value(section, key, fallback) {
        const v = draft?.[section]?.[key];
        return v === undefined || v === null ? fallback : v;
    }

    function setValue(section, key, v) {
        if (!draft || swapping)
            return;
        // Sections bind to draft[section]; a new object is what makes those bindings notify.
        const s = draft[section] && typeof draft[section] === "object" ? Object.assign({}, draft[section]) : {};
        if (v === undefined) {
            if (s[key] === undefined)
                return;
            delete s[key];
        } else {
            // Objects may have been mutated in place, so only primitives count as unchanged.
            if (typeof v !== "object" && s[key] === v)
                return;
            s[key] = v;
        }
        // Never send an empty section NM didn't have.
        if (Object.keys(s).length === 0 && !original?.[section])
            delete draft[section];
        else
            draft[section] = s;
        revision++;
    }

    function setSection(section, obj) {
        if (!draft || swapping)
            return;
        if (obj === null || obj === undefined)
            delete draft[section];
        else
            draft[section] = obj;
        revision++;
    }

    function hasSection(section) {
        const s = draft?.[section];
        return s !== undefined && s !== null;
    }

    function clearSections() {
        swapping = true;
        securitySection = null;
        sectionIds = [];
    }

    // Section components keep local state (pending text, form fields); re-creating them resets it.
    // Clearing sectionIds first forces re-creation when the id list is unchanged.
    function rebuild() {
        securitySection = null;
        revision++;
        // Mobile settings need a gsm or cdma section (Bluetooth DUN profiles may lack one).
        const hasMobile = hasSection("gsm") || hasSection("cdma");
        sectionIds = [];
        swapping = false;
        sectionIds = loaded && !unsupported ? CE.sectionsFor(draft?.connection?.type ?? "", draft).filter(id => id !== "mobile" || hasMobile) : [];
    }

    function resetNew(type) {
        const label = typeLabel(type);
        const settings = CE.newConnectionSettings(type, {
            "name": label
        });
        clearSections();
        isNew = true;
        unsupported = false;
        readOnly = false;
        profile = null;
        enterpriseOriginal = null;
        original = {};
        draft = settings;
        loaded = true;
        SettingsUiState.selectedConnectionTitle = label;
        rebuild();
    }

    function fail(error) {
        clearSections();
        saving = false;
        unsupported = false;
        loadError = String(error);
        loaded = false;
        rebuild();
    }

    function apply(settings, listed, enterprise) {
        clearSections();
        isNew = false;
        saving = false;
        profile = listed;
        readOnly = listed ? !listed.canModify : false;
        enterpriseOriginal = enterprise;
        original = CE.copy(settings);
        draft = CE.copy(settings);
        unsupported = !CE.isSupported(settings.connection?.type ?? "", CE.portOf(settings)?.type ?? "");
        loadError = "";
        loaded = true;
        rebuild();
    }

    function load() {
        const token = ++loadToken;
        const uuid = selectedUuid;
        NetworkService.listConnections(response => {
            if (token !== loadToken)
                return;
            profiles = response.result ?? [];
            if (uuid === "") {
                resetNew(SettingsUiState.newConnectionType || "802-3-ethernet");
                return;
            }
            const listed = profiles.find(p => p.uuid === uuid) ?? null;
            NetworkService.getConnection(uuid, true, got => {
                if (token !== loadToken)
                    return;
                if (got.error) {
                    fail(got.error);
                    return;
                }
                const settings = got.result ?? {};
                if (!settings["802-1x"]) {
                    apply(settings, listed, null);
                    return;
                }
                NetworkService.getConnectionEnterprise(uuid, ent => {
                    if (token === loadToken)
                        apply(settings, listed, ent.error ? null : (ent.result ?? null));
                });
            });
        });
    }

    function discard() {
        if (isNew) {
            parentModal?.goBack();
            return;
        }
        clearSections();
        draft = CE.copy(original);
        original = CE.copy(original);
        rebuild();
    }

    function finishSave(response, newName) {
        if (response.error) {
            saving = false;
            saveError = String(response.error);
            return;
        }
        ToastService.showInfo(I18n.tr("Saved"));
        const newUuid = response.result?.uuid;
        if (newUuid) {
            // Stays saving until the reload into edit mode (apply or fail) so Save can't add a duplicate.
            SettingsUiState.selectConnection(newUuid, newName, "");
            return;
        }
        saving = false;
        SettingsUiState.selectedConnectionTitle = newName;
        load();
    }

    function save(persist) {
        if (saving || readOnly)
            return;
        const enterprise = securitySection?.enterpriseConfig() ?? null;
        const name = String(value("connection", "id", ""));
        saving = true;
        saveError = "";
        if (isNew) {
            NetworkService.addConnection(CE.copy(draft), true, response => finishSave(response, name), enterprise);
            return;
        }
        let patch = CE.settingsDiff(original, draft);
        // An empty patch is rejected; resending the unchanged name only moves the profile to disk.
        if (patch === null)
            patch = persist && !enterprise ? {
                "connection": {
                    "id": original.connection?.id ?? name
                }
            } : {};
        NetworkService.updateConnection(selectedUuid, patch, persist, response => finishSave(response, name), enterprise);
    }

    SettingsPage {
        id: page

        SettingsNoteRow {
            visible: root.loadError !== ""
            text: root.loadError
            noteIconName: "error"
            tint: Theme.error
            tintBackground: Theme.errorHover
        }

        SettingsNoteRow {
            visible: root.loaded && root.readOnly
            text: I18n.tr("You don't have permission to change this connection.", "network connection editor note")
            noteIconName: "lock"
        }

        SettingsRow {
            visible: root.loaded && root.unsupported
            iconName: "info"
            title: I18n.tr("Not supported in Settings", "network connection list and editor: this connection type can only be edited in another tool")

            DButton {
                visible: NetworkService.externalConnectionEditor !== ""
                text: I18n.tr("Open in %1", "%1 is an application name").arg(NetworkService.externalConnectionEditor)
                iconName: "open_in_new"
                variant: "tonal"
                onClicked: NetworkService.openExternalConnectionEditor(root.selectedUuid)
            }
        }

        SettingsNoteRow {
            visible: root.loaded && !root.readOnly && !root.isNew && !root.unsupported && (root.profile?.unsaved ?? false)
            text: I18n.tr("This connection is temporary and is lost on reboot.", "network connection editor note")
            noteIconName: "info"
            tint: Theme.primary
            tintBackground: Theme.primaryHover
        }

        SettingsRow {
            visible: root.loaded && !root.readOnly && !root.isNew && !root.unsupported && (root.profile?.unsaved ?? false)

            DButton {
                text: I18n.tr("Save permanently", "network connection editor: keep the connection after reboot")
                iconName: "save"
                variant: "tonal"
                busy: root.saving
                enabled: !root.saving
                onClicked: root.saveOrReveal(true)
            }
        }

        SettingsNoteRow {
            visible: root.saveError !== ""
            text: root.saveError
            noteIconName: "error"
            tint: Theme.error
            tintBackground: Theme.errorHover
        }

        Repeater {
            id: sectionRepeater

            model: root.sectionIds

            delegate: Loader {
                id: sectionLoader

                required property string modelData

                width: parent?.width ?? 0
                sourceComponent: {
                    switch (modelData) {
                    case "general":
                        return generalSection;
                    case "ipv4":
                        return ipv4Section;
                    case "ipv6":
                        return ipv6Section;
                    case "ethernet":
                        return ethernetSection;
                    case "wifi":
                        return wifiSection;
                    case "security":
                        return securitySectionComponent;
                    case "wireguard":
                        return wireguardSection;
                    case "openvpn":
                        return openVpnSection;
                    case "openconnect":
                        return openConnectSection;
                    case "vpnData":
                        return vpnDataSection;
                    case "vlan":
                        return vlanSection;
                    case "bridge":
                        return bridgeSection;
                    case "ports":
                        return portsSection;
                    case "port":
                        return portSection;
                    case "mobile":
                        return mobileSection;
                    case "bluetooth":
                        return bluetoothSection;
                    case "pppoe":
                        return pppoeSection;
                    case "ppp":
                        return pppSection;
                    }
                    return null;
                }
                onLoaded: {
                    if (modelData === "security")
                        root.securitySection = item;
                }
            }
        }

        SettingsFabBar {
            shown: root.loaded && !root.readOnly && !root.unsupported && (root.dirty || root.isNew)

            DFab {
                text: I18n.tr("Discard", "verb, button to discard pending changes")
                iconName: "undo"
                colorRole: "secondaryContainer"
                enabled: !root.saving
                onClicked: root.discard()
            }

            DFab {
                text: I18n.tr("Save")
                iconName: "check"
                colorRole: "primary"
                busy: root.saving
                enabled: !root.saving
                onClicked: root.saveOrReveal(false)
            }
        }
    }

    Component {
        id: generalSection

        ConnectionGeneralSection {
            editor: root
        }
    }

    Component {
        id: ipv4Section

        ConnectionIpSection {
            editor: root
            family: 4
        }
    }

    Component {
        id: ipv6Section

        ConnectionIpSection {
            editor: root
            family: 6
        }
    }

    Component {
        id: ethernetSection

        ConnectionEthernetSection {
            editor: root
        }
    }

    Component {
        id: wifiSection

        ConnectionWifiSection {
            editor: root
        }
    }

    Component {
        id: securitySectionComponent

        ConnectionSecuritySection {
            editor: root
        }
    }

    Component {
        id: wireguardSection

        ConnectionWireGuardSection {
            editor: root
        }
    }

    Component {
        id: openVpnSection

        ConnectionOpenVpnSection {
            editor: root
        }
    }

    Component {
        id: openConnectSection

        ConnectionOpenConnectSection {
            editor: root
        }
    }

    Component {
        id: vpnDataSection

        ConnectionVpnDataSection {
            editor: root
        }
    }

    Component {
        id: vlanSection

        ConnectionVlanSection {
            editor: root
        }
    }

    Component {
        id: bridgeSection

        ConnectionBridgeSection {
            editor: root
        }
    }

    Component {
        id: portsSection

        ConnectionPortsSection {
            editor: root
        }
    }

    Component {
        id: portSection

        ConnectionPortSection {
            editor: root
        }
    }

    Component {
        id: mobileSection

        ConnectionMobileSection {
            editor: root
        }
    }

    Component {
        id: bluetoothSection

        ConnectionBluetoothSection {
            editor: root
        }
    }

    Component {
        id: pppoeSection

        ConnectionPppoeSection {
            editor: root
        }
    }

    Component {
        id: pppSection

        ConnectionPppSection {
            editor: root
        }
    }
}
