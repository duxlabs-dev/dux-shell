pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool isFirewalld: FirewallService.backend === "firewalld"
    readonly property bool canUnlock: FirewallService.locked && (!isFirewalld || FirewallService.active)
    readonly property bool showRules: !FirewallService.locked && (!isFirewalld || FirewallService.active) && FirewallService.stateError === ""

    property string selectedZoneName: ""
    property bool showAllZones: false
    property bool adding: false
    property var services: []
    readonly property var serviceNames: services.map(s => s.name)
    readonly property var serviceLabels: services.map(s => portsSuffix(s.name, s.name))

    readonly property var networks: {
        const list = [];
        for (const z of FirewallService.zones) {
            if (z.readOnly)
                continue;
            for (const name of z.interfaces)
                list.push({
                    "name": name,
                    "zone": z.name
                });
        }
        return list.sort((a, b) => a.name.localeCompare(b.name));
    }
    readonly property var selectableZones: FirewallService.zones.filter(z => isSelectable(z))
    readonly property var assignableZones: selectableZones.filter(z => !z.readOnly).map(z => z.name)
    readonly property string zoneName: selectedZoneName !== "" ? selectedZoneName : (networks[0]?.zone ?? FirewallService.defaultZone)
    readonly property var zone: FirewallService.zones.find(z => z.name === zoneName) ?? null
    readonly property var zoneChoices: selectableZones.filter(z => showAllZones || z.active || z.name === FirewallService.defaultZone || z.name === zoneName).map(z => z.name)
    readonly property var visibleRules: isFirewalld ? (zone?.rules ?? []) : FirewallService.rules
    readonly property bool readOnly: zone?.readOnly ?? false

    onShowRulesChanged: {
        if (showRules && isFirewalld && services.length === 0)
            loadServices();
    }

    Component.onCompleted: {
        FirewallService.refCount++;
        if (showRules && isFirewalld)
            loadServices();
    }
    Component.onDestruction: FirewallService.refCount--

    property var confirm: ConfirmModal {}

    function isSelectable(z) {
        // external and dmz zones are only relevant on servers and routers
        if (z.name !== "external" && z.name !== "dmz")
            return true;
        return z.active || z.name === FirewallService.defaultZone || z.name === selectedZoneName;
    }

    function zoneChoiceLabel(name) {
        const interfaces = FirewallService.zones.find(z => z.name === name)?.interfaces ?? [];
        if (interfaces.length === 0)
            return name;
        if (interfaces.length > 3)
            return name + " (" + I18n.tr("%1 and %2 more", "%1 is a list of network interfaces, %2 is the number of interfaces that dont fit (e.g. and 12 more)").arg(interfaces.slice(0, 3).join(", ")).arg(interfaces.length - 3) + ")";
        return name + " (" + interfaces.join(", ") + ")";
    }

    function portsSuffix(name, label) {
        const ports = services.find(s => s.name === name)?.ports ?? [];
        return ports.length > 0 ? label + " (" + ports.join(", ") + ")" : label;
    }

    function ruleTitle(rule) {
        if (rule.kind === "raw")
            return rule.raw;
        if (rule.kind === "port" && rule.proto)
            return rule.target + "/" + rule.proto;
        if (rule.kind === "service")
            return portsSuffix(rule.target, rule.target);
        return rule.target;
    }

    function actionLabel(action) {
        switch (action) {
        case "allow":
            return I18n.tr("Allow", "firewall rule action");
        case "deny":
            return I18n.tr("Deny", "firewall rule action");
        case "reject":
            return I18n.tr("Reject", "firewall rule action");
        }
        return "";
    }

    function restoreDropdowns() {
        incomingRow.resync();
        outgoingRow.resync();
        defaultZoneRow.resync();
        // Looked up here because a state update can replace the delegates at any time.
        for (let i = 0; i < networkRepeater.count; i++)
            networkRepeater.itemAt(i)?.resync();
    }

    function restoreIfFailed(response) {
        if (response.error || response.result?.success === false)
            restoreDropdowns();
    }

    function confirmDefaults(message, params) {
        confirm.showWithOptions({
            title: I18n.tr("Change firewall default?", "confirm dialog title"),
            message: message,
            confirmText: I18n.tr("Confirm"),
            danger: true,
            onConfirm: () => FirewallService.setDefaults(params, root.restoreIfFailed),
            onCancel: root.restoreDropdowns
        });
    }

    function loadServices() {
        FirewallService.listServices(list => root.services = list);
    }

    function startAdding() {
        adding = true;
        loadServices();
    }

    SettingsPage {
        SettingsCard {
            title: I18n.tr("Status")
            settingKey: "networkFirewall"
            tags: ["firewall", "firewalld", "ufw", "network", "security", "ports", "rules", "zone"]

            SettingsRow {
                iconName: "shield"
                title: FirewallService.backend
                subtitle: {
                    if (FirewallService.active && FirewallService.locked && !root.isFirewalld)
                        return I18n.tr("Enabled, unlock to confirm it is running", "firewall status");
                    if (FirewallService.active)
                        return I18n.tr("Active", "firewall status");
                    return root.isFirewalld ? I18n.tr("Not running", "firewall status") : I18n.tr("Inactive", "firewall status");
                }

                DButton {
                    visible: root.canUnlock
                    text: I18n.tr("Unlock", "reveal firewall rules after entering a password")
                    iconName: "lock_open"
                    buttonHeight: Theme.buttonHeightS
                    busy: FirewallService.busy
                    enabled: !FirewallService.busy
                    onClicked: FirewallService.unlock()
                }
            }

            SettingsNoteRow {
                visible: FirewallService.stateError !== ""
                text: I18n.tr("Could not read the firewall rules: %1").arg(FirewallService.stateError)
            }

            SettingsNoteRow {
                visible: FirewallService.conflict
                text: I18n.tr("firewalld and ufw are both running. They can override each other, so disable one of them.")
            }

            SettingsNoteRow {
                visible: root.isFirewalld && !FirewallService.active
                text: I18n.tr("firewalld is not running, so no rules apply. Start it with: %1").arg("systemctl enable --now firewalld")
            }

            SettingsNoteRow {
                visible: FirewallService.backend === "ufw" && !FirewallService.active
                text: I18n.tr("ufw is inactive, so saved rules do not apply. Turn it on with: %1").arg("ufw enable")
            }

            SettingsNoteRow {
                visible: FirewallService.warnings.includes("dockerBypass")
                text: I18n.tr("Docker is present. Ports published by containers bypass ufw rules.")
            }

            SettingsNoteRow {
                visible: root.canUnlock
                noteIconName: "lock"
                tint: Theme.surfaceVariantText
                tintBackground: SettingsMetrics.controlSurface
                text: I18n.tr("Unlock to view and change rules. You will be asked for your password.")
            }
        }

        SettingsCard {
            title: I18n.tr("Defaults", "firewall default behaviour section")
            visible: FirewallService.defaults !== null

            SettingsDropdownRow {
                id: incomingRow
                visible: FirewallService.defaults !== null
                text: I18n.tr("Incoming traffic")
                options: [root.actionLabel("allow"), root.actionLabel("deny"), root.actionLabel("reject")]
                optionValues: ["allow", "deny", "reject"]
                enabled: !FirewallService.busy
                currentValue: FirewallService.defaults?.incoming ?? ""
                onValueChanged: value => {
                    if (value === FirewallService.defaults?.incoming)
                        return;
                    root.confirmDefaults(I18n.tr("Apply this to all incoming traffic that no rule matches?"), {
                        "incoming": value
                    });
                }
            }

            SettingsDropdownRow {
                id: outgoingRow
                visible: FirewallService.defaults !== null
                text: I18n.tr("Outgoing traffic")
                options: [root.actionLabel("allow"), root.actionLabel("deny"), root.actionLabel("reject")]
                optionValues: ["allow", "deny", "reject"]
                enabled: !FirewallService.busy
                currentValue: FirewallService.defaults?.outgoing ?? ""
                onValueChanged: value => {
                    if (value === FirewallService.defaults?.outgoing)
                        return;
                    root.confirmDefaults(I18n.tr("Apply this to all outgoing traffic that no rule matches?"), {
                        "outgoing": value
                    });
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Networks", "firewalld network interfaces section")
            visible: root.isFirewalld && FirewallService.active && root.networks.length > 0

            Repeater {
                id: networkRepeater
                model: root.networks

                SettingsDropdownRow {
                    required property var modelData

                    text: modelData.name
                    enabled: !FirewallService.busy
                    options: root.assignableZones
                    optionValues: root.assignableZones
                    currentValue: modelData.zone
                    onValueChanged: value => {
                        if (value === modelData.zone)
                            return;
                        const iface = modelData.name;
                        if (value !== "trusted") {
                            FirewallService.setInterfaceZone(iface, value, root.restoreIfFailed);
                            return;
                        }
                        root.confirm.showWithOptions({
                            title: I18n.tr("Trust this network?", "confirm dialog title"),
                            message: I18n.tr("Everything on \"%1\" will be able to reach this computer.", "%1 is a network interface name").arg(iface),
                            confirmText: I18n.tr("Confirm"),
                            danger: true,
                            onConfirm: () => FirewallService.setInterfaceZone(iface, value, root.restoreIfFailed),
                            onCancel: root.restoreDropdowns
                        });
                    }
                }
            }
        }


        SettingsCard {
            id: addCard
            title: I18n.tr("Add rule")
            visible: root.adding && root.showRules && !root.readOnly

            property bool isService: true
            property string service: ""
            property string port: ""
            property string proto: "tcp"
            property string action: "allow"
            property string source: ""

            function resetAddRuleForm() {
                service = "";
                port = "";
                proto = "tcp";
                action = "allow";
                source = "";
            }

            readonly property bool portValid: /^[0-9]{1,5}(-[0-9]{1,5})?$/.test(port)
            readonly property bool canSubmit: !FirewallService.busy && (isService ? service !== "" : portValid)

            function submit() {
                FirewallService.addRule({
                    "zone": root.zoneName,
                    "kind": isService ? "service" : "port",
                    "action": action,
                    "target": isService ? service : port,
                    "proto": proto,
                    "source": source.trim()
                }, response => {
                    if (response.error || response.result?.success === false)
                        return;
                    root.adding = false;
                    addCard.resetAddRuleForm()
                });
            }

            SettingsRow {
                iconName: "add_circle"
                title: I18n.tr("Configure a new rule")

                DActionButton {
                    iconName: "close"
                    Accessible.name: I18n.tr("Cancel")
                    onClicked: {
                        root.adding = false;
                        addCard.resetAddRuleForm();
                    }
                }
            }

            SettingsButtonGroupRow {
                text: I18n.tr("Type", "firewall rule target type")
                model: [I18n.tr("Service", "firewall rule target type"), I18n.tr("Port", "firewall rule target type")]
                currentIndex: addCard.isService ? 0 : 1
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        addCard.isService = index === 0;
                }
            }

            SettingsDropdownRow {
                visible: addCard.isService
                text: I18n.tr("Service", "firewall rule target type")
                enableFuzzySearch: true
                popupWidth: Math.round(root.width * 0.6)
                options: root.serviceLabels
                optionValues: root.serviceNames
                currentValue: addCard.service
                onValueChanged: value => addCard.service = value
            }

            SettingsRow {
                visible: !addCard.isService
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Port or range", "firewall rule field")
                    placeholderText: "8080, 6000-6007"
                    text: addCard.port
                    isError: addCard.port !== "" && !addCard.portValid
                    onTextEdited: addCard.port = text
                }
            }

            SettingsButtonGroupRow {
                visible: !addCard.isService
                text: I18n.tr("Protocol", "firewall rule field")
                model: ["TCP", "UDP", I18n.tr("Both", "firewall rule protocol")]
                currentIndex: ["tcp", "udp", "both"].indexOf(addCard.proto)
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        addCard.proto = ["tcp", "udp", "both"][index];
                }
            }

            SettingsButtonGroupRow {
                text: I18n.tr("Action", "firewall rule field")
                model: [root.actionLabel("allow"), root.actionLabel("deny"), root.actionLabel("reject")]
                currentIndex: ["allow", "deny", "reject"].indexOf(addCard.action)
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        addCard.action = ["allow", "deny", "reject"][index];
                }
            }

            SettingsRow {
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Source (optional)", "firewall rule field")
                    placeholderText: "192.168.1.0/24"
                    text: addCard.source
                    onTextEdited: addCard.source = text
                }
            }

            SettingsRow {
                DButton {
                    text: I18n.tr("Add rule")
                    buttonHeight: Theme.buttonHeightS
                    busy: FirewallService.busy
                    enabled: addCard.canSubmit
                    onClicked: addCard.submit()
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Rules", "firewall rules section")
            visible: root.showRules

            SettingsDropdownRow {
                visible: root.isFirewalld && (root.zoneChoices.length > 1 || root.showAllZones)
                text: I18n.tr("Zone")
                enableFuzzySearch: true
                options: root.zoneChoices.map(name => root.zoneChoiceLabel(name))
                optionValues: root.zoneChoices
                currentValue: root.zoneName
                onValueChanged: value => root.selectedZoneName = value
            }

            SettingsNoteRow {
                visible: root.readOnly
                noteIconName: "info"
                tint: Theme.surfaceVariantText
                tintBackground: SettingsMetrics.controlSurface
                text: I18n.tr("This zone is managed by another program, so its rules can't be edited here.")
            }

            SettingsRow {
                visible: root.visibleRules.length === 0
                subtitle: I18n.tr("No rules")
            }

            Repeater {
                model: root.visibleRules

                SettingsRow {
                    id: ruleRow
                    required property var modelData

                    title: root.ruleTitle(modelData)
                    subtitle: modelData.kind === "raw" ? I18n.tr("Custom rule") : root.actionLabel(modelData.action) + " · " + (modelData.source ? I18n.tr("From %1", "firewall rule source, %1 is an address").arg(modelData.source) : I18n.tr("From anywhere"))

                    DActionButton {
                        visible: !root.readOnly
                        enabled: !FirewallService.busy
                        buttonSize: Theme.buttonHeightXXS
                        iconName: "delete"
                        iconColor: Theme.surfaceVariantText
                        stateColor: Theme.error
                        tooltipText: I18n.tr("Delete")
                        onClicked: {
                            // Copied because a state update can destroy this delegate while the dialog is open.
                            const zoneName = root.zoneName;
                            const ruleId = ruleRow.modelData.id;
                            root.confirm.showWithOptions({
                                title: I18n.tr("Delete rule"),
                                message: I18n.tr("Delete \"%1\"?", "delete confirmation, %1 is a vpn profile or printer name").arg(root.ruleTitle(ruleRow.modelData)),
                                confirmText: I18n.tr("Delete"),
                                danger: true,
                                onConfirm: () => FirewallService.removeRule(zoneName, ruleId)
                            });
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Advanced", "firewalld advanced section")
            visible: root.isFirewalld && FirewallService.active
            collapsible: true
            expanded: false

            SettingsDropdownRow {
                id: defaultZoneRow
                text: I18n.tr("Default zone")
                description: I18n.tr("Used by interfaces with no zone of their own")
                enabled: !FirewallService.busy
                options: root.selectableZones.map(z => z.name)
                optionValues: root.selectableZones.map(z => z.name)
                currentValue: FirewallService.defaultZone
                onValueChanged: value => {
                    if (value === FirewallService.defaultZone)
                        return;
                    root.confirmDefaults(I18n.tr("Interfaces without their own zone will move to \"%1\".", "%1 is a firewall zone name").arg(value), {
                        "zone": value
                    });
                }
            }

            SettingsToggleRow {
                text: I18n.tr("Show all zones")
                checked: root.showAllZones
                onToggled: value => root.showAllZones = value
            }
        }

        SettingsFabBar {
            shown: root.showRules && !root.readOnly && !root.adding

            DFab {
                text: I18n.tr("Add rule")
                iconName: "add"
                onClicked: root.startAdding()
            }
        }
    }
}
