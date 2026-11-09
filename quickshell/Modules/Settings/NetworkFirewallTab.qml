pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property var parentModal: null

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool isFirewalld: FirewallService.isFirewalld
    readonly property bool canUnlock: FirewallService.locked && (!isFirewalld || FirewallService.active)
    readonly property bool showRules: !FirewallService.locked && (!isFirewalld || FirewallService.active) && FirewallService.stateError === ""
    readonly property bool showZones: isFirewalld && showRules
    readonly property color statusColor: {
        if (FirewallService.stateError !== "" || FirewallService.conflict || (FirewallService.active && FirewallService.locked && !isFirewalld))
            return Theme.warning;
        return FirewallService.active ? Theme.success : Theme.error;
    }

    readonly property string selectedZoneName: SettingsUiState.selectedFirewallZone
    readonly property string internetInterface: {
        switch (NetworkService.networkStatus) {
        case "ethernet":
            return NetworkService.ethernetInterface;
        case "wifi":
            return NetworkService.wifiInterface;
        case "cellular":
            return NetworkService.cellularInterface;
        }
        return "";
    }
    readonly property string internetZone: FirewallService.zones.find(z => z.interfaces.includes(internetInterface))?.name ?? FirewallService.defaultZone
    readonly property string zoneName: FirewallService.zones.some(z => z.name === selectedZoneName) ? selectedZoneName : internetZone
    property bool showAllZones: false
    // Only unused zones firewalld ships with are hidden, custom zones and the default zone always show.
    readonly property var listedZones: FirewallService.zones.filter(z => showAllZones || z.interfaces.length > 0 || (!z.builtin && !z.readOnly) || z.name === zoneName || z.name === FirewallService.defaultZone).sort((a, b) => isCustomZone(a) - isCustomZone(b) || a.name.localeCompare(b.name))
    readonly property var movableInterfaces: {
        const list = [];
        for (const z of FirewallService.zones) {
            if (z.readOnly || z.name === zoneName)
                continue;
            for (const name of z.interfaces)
                list.push(name);
        }
        return list;
    }
    readonly property var zone: FirewallService.zones.find(z => z.name === zoneName) ?? null
    readonly property var visibleRules: isFirewalld ? (zone?.rules ?? []) : FirewallService.rules
    readonly property bool readOnly: zone?.readOnly ?? false
    readonly property var assignableZones: FirewallService.zones.filter(z => !z.readOnly).map(z => z.name)

    onShowRulesChanged: {
        if (showRules && isFirewalld)
            FirewallService.loadServices();
    }

    Component.onCompleted: {
        FirewallService.refCount++;
        if (showRules && isFirewalld)
            FirewallService.loadServices();
    }
    Component.onDestruction: FirewallService.refCount--

    property var confirm: ConfirmModal {}

    function isCustomZone(z) {
        return !!z && !z.builtin && !z.readOnly;
    }

    // Mirrors the backend checks, so the controls only enable where the change can succeed.
    function canChangeZone(z) {
        return isCustomZone(z) && z.name !== FirewallService.defaultZone && z.interfaces.length === 0;
    }

    function zoneSummary(z) {
        const parts = [];
        if (z.name === FirewallService.defaultZone)
            parts.push(I18n.tr("Default"));
        const count = z.interfaces.length;
        if (count > 0)
            parts.push(count === 1 ? I18n.tr("%1 interface", "singular, firewall zone summary, %1 is 1").arg(count) : I18n.tr("%1 interfaces", "plural, firewall zone summary, %1 is a count").arg(count));
        return parts.join(" • ");
    }

    function actionIcon(rule) {
        switch (rule.action) {
        case "allow":
            return "check";
        case "drop":
            return "block";
        case "reject":
            return "close";
        }
        return "code";
    }

    function actionColor(rule) {
        switch (rule.action) {
        case "allow":
            return Theme.success;
        case "drop":
            return Theme.warning;
        case "reject":
            return Theme.error;
        }
        return Theme.surfaceVariantText;
    }

    function restoreDropdowns() {
        incomingRow.resync();
        outgoingRow.resync();
    }

    function restoreIfFailed(response) {
        if (!FirewallService.succeeded(response))
            restoreDropdowns();
    }

    function confirmDefaults(message, params, onCancel) {
        confirm.showWithOptions({
            title: I18n.tr("Change firewall default?", "confirm dialog title"),
            message: message,
            confirmText: I18n.tr("Confirm"),
            danger: true,
            onConfirm: () => FirewallService.setDefaults(params, root.restoreIfFailed),
            onCancel: onCancel
        });
    }

    function moveInterface(iface, zone) {
        if (zone !== "trusted") {
            FirewallService.setInterfaceZone(iface, zone);
            return;
        }
        confirm.showWithOptions({
            title: I18n.tr("Trust this network?", "confirm dialog title"),
            message: I18n.tr("Everything on \"%1\" will be able to reach this computer.", "%1 is a network interface name").arg(FirewallService.interfaceTitle(iface)),
            confirmText: I18n.tr("Confirm"),
            danger: true,
            onConfirm: () => FirewallService.setInterfaceZone(iface, zone)
        });
    }

    function saveZoneName(name) {
        const previous = zoneDialog.renaming;
        zoneDialog.hide();
        // The polkit prompt can outlast the page, so the answer lands in shared state.
        const done = response => {
            if (FirewallService.succeeded(response))
                SettingsUiState.selectedFirewallZone = name;
        };
        if (previous)
            FirewallService.renameZone(previous, name, done);
        else
            FirewallService.addZone(name, done);
    }

    function openRule(rule, keyboard) {
        SettingsUiState.selectedFirewallZone = zoneName;
        SettingsUiState.selectedFirewallRuleId = rule?.id ?? "";
        SettingsUiState.selectedFirewallRuleTitle = rule ? FirewallService.ruleTitle(rule) : I18n.tr("Add rule", "firewall rule add button");
        parentModal?.navigateTo("network_firewall_rule", keyboard);
    }

    SettingsRenameDialog {
        id: zoneDialog

        property string renaming: ""

        parent: root.parentModal?.modalFocusScope ?? root
        title: renaming ? I18n.tr("Rename") : I18n.tr("Add zone", "firewalld dialog title")
        supportingText: I18n.tr("Up to 17 letters, digits, dashes or underscores", "firewalld zone name rules")
        onAccepted: name => root.saveZoneName(name)
    }

    SettingsRenameDialog {
        id: interfaceDialog

        property string iface: ""

        parent: root.parentModal?.modalFocusScope ?? root
        supportingText: iface
        onAccepted: name => {
            FirewallService.setInterfaceLabel(iface, name);
            hide();
        }
    }

    SettingsPage {
        SettingsCard {
            title: I18n.tr("Status")
            settingKey: "networkFirewall"
            tags: ["firewall", "firewalld", "ufw", "network", "security", "ports", "rules", "zone"]

            SettingsRow {
                iconName: FirewallService.active ? "shield" : "remove_moderator"
                iconBox: true
                iconColor: root.statusColor
                title: I18n.tr("Firewall")
                subtitle: FirewallService.active ? I18n.tr("%1 is active", "firewall status, %1 is the backend name").arg(FirewallService.backend) : I18n.tr("%1 is inactive", "firewall status, %1 is the backend name").arg(FirewallService.backend)

                Rectangle {
                    width: Theme.iconSizeSmall / 2
                    height: width
                    radius: width / 2
                    color: root.statusColor
                }
            }

            SettingsRow {
                visible: root.canUnlock || root.showRules
                iconName: FirewallService.locked ? "lock" : "lock_open"
                title: FirewallService.locked ? I18n.tr("Rules are locked", "firewall status, a password is needed to see rules") : I18n.tr("Rules are unlocked", "firewall status, rules can be changed")
                subtitle: root.canUnlock ? I18n.tr("Unlock to view and change rules.", "firewall info message") : ""

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
                text: I18n.tr("Could not read the firewall rules: %1", "firewall info message").arg(FirewallService.stateError)
            }

            SettingsNoteRow {
                visible: FirewallService.conflict
                text: I18n.tr("firewalld and ufw are both running. They can override each other, so disable one of them.", "firewall info message")
            }

            SettingsNoteRow {
                visible: root.isFirewalld && !FirewallService.active
                text: I18n.tr("firewalld is not running, so no rules apply. Start it with: %1", "firewall info message").arg("systemctl enable --now firewalld")
            }

            SettingsNoteRow {
                visible: FirewallService.backend === "ufw" && !FirewallService.active
                text: I18n.tr("ufw is inactive, so saved rules do not apply. Turn it on with: %1", "firewall info message").arg("ufw enable")
            }

            SettingsNoteRow {
                visible: FirewallService.warnings.includes("dockerBypass")
                text: I18n.tr("Docker is present. Ports published by containers bypass ufw rules.", "firewall info message")
            }
        }

        SettingsCard {
            title: I18n.tr("Defaults", "firewall default behaviour section")
            visible: FirewallService.defaults !== null

            SettingsDropdownRow {
                id: incomingRow
                text: I18n.tr("Incoming traffic", "firewall tab, incoming traffic coming into the local network")
                options: [FirewallService.actionLabel("allow"), FirewallService.actionLabel("drop"), FirewallService.actionLabel("reject")]
                optionValues: ["allow", "drop", "reject"]
                enabled: !FirewallService.busy && !FirewallService.locked
                currentValue: FirewallService.defaults?.incoming ?? ""
                onValueChanged: value => {
                    if (value === FirewallService.defaults?.incoming)
                        return;
                    root.confirmDefaults(I18n.tr("Apply this to all incoming traffic that no rule matches?"), {
                        "incoming": value
                    }, root.restoreDropdowns);
                }
            }

            SettingsDropdownRow {
                id: outgoingRow
                text: I18n.tr("Outgoing traffic", "firewall tab, traffic going out from the pc to the internet")
                options: [FirewallService.actionLabel("allow"), FirewallService.actionLabel("drop"), FirewallService.actionLabel("reject")]
                optionValues: ["allow", "drop", "reject"]
                enabled: !FirewallService.busy && !FirewallService.locked
                currentValue: FirewallService.defaults?.outgoing ?? ""
                onValueChanged: value => {
                    if (value === FirewallService.defaults?.outgoing)
                        return;
                    root.confirmDefaults(I18n.tr("Apply this to all outgoing traffic that no rule matches?"), {
                        "outgoing": value
                    }, root.restoreDropdowns);
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Zones", "firewalld zones section")
            visible: root.showZones
            headerActions: DButton {
                text: I18n.tr("Add")
                iconName: "add"
                buttonHeight: Theme.buttonHeightXS
                enabled: !FirewallService.busy
                onClicked: {
                    zoneDialog.renaming = "";
                    zoneDialog.show("");
                }
            }

            Repeater {
                model: root.listedZones

                delegate: SettingsInstanceRow {
                    required property var modelData

                    title: modelData.name
                    summary: root.zoneSummary(modelData)
                    selected: root.zoneName === modelData.name
                    toggleVisible: false
                    deletable: root.isCustomZone(modelData)
                    deleteEnabled: root.canChangeZone(modelData) && !FirewallService.busy
                    onClicked: SettingsUiState.selectedFirewallZone = modelData.name
                    onDeleteRequested: FirewallService.removeZone(modelData.name)
                    renameVisible: root.isCustomZone(modelData)
                    renameEnabled: root.canChangeZone(modelData) && !FirewallService.busy
                    onRenameRequested: {
                        zoneDialog.renaming = modelData.name;
                        zoneDialog.show(modelData.name);
                    }
                    defaultVisible: !modelData.readOnly
                    defaultEnabled: modelData.name !== FirewallService.defaultZone && !FirewallService.busy
                    onDefaultRequested: root.confirmDefaults(I18n.tr("Interfaces without their own zone will move to \"%1\".", "%1 is a firewall zone name").arg(modelData.name), {
                        "zone": modelData.name
                    })
                }
            }

            SettingsToggleRow {
                text: I18n.tr("Show all zones", "firewall tab visibility setting")
                description: I18n.tr("Also list zones no interface uses", "firewall tab visibility setting")
                checked: root.showAllZones
                onToggled: value => root.showAllZones = value
            }
        }

        SettingsCard {
            title: I18n.tr("Interfaces", "firewalld network interfaces section")
            visible: root.showZones && root.zone !== null
            headerActions: DButton {
                id: moveHereHeaderButton
                visible: !root.readOnly && root.movableInterfaces.length > 0 && (root.zone?.interfaces.length ?? 0) > 0
                enabled: !FirewallService.busy
                text: I18n.tr("Move here", "firewalld button on a zone that already has interfaces")
                iconName: "swap_horiz"
                buttonHeight: Theme.buttonHeightXS
                onClicked: moveHereHeaderMenu.openDropdownMenu()

                DDropdown {
                    id: moveHereHeaderMenu
                    showTrigger: false
                    popupAnchorItem: moveHereHeaderButton
                    focusReturnTarget: moveHereHeaderButton
                    alignPopupRight: !I18n.isRtl
                    options: root.movableInterfaces.map(name => FirewallService.interfaceTitle(name))
                    optionValues: root.movableInterfaces
                    onValueChanged: value => {
                        currentValue = "";
                        root.moveInterface(value, root.zoneName);
                    }
                }
            }

            SettingsRow {
                visible: (root.zone?.interfaces.length ?? 0) === 0
                subtitle: I18n.tr("No interfaces use this zone", "firewalld zone status message")

                DButton {
                    id: moveHereButton
                    visible: !root.readOnly && root.movableInterfaces.length > 0
                    enabled: !FirewallService.busy
                    text: I18n.tr("Move an interface here", "firewalld button on a zone with no interfaces")
                    iconName: "swap_horiz"
                    buttonHeight: Theme.buttonHeightS
                    onClicked: moveHereMenu.openDropdownMenu()

                    DDropdown {
                        id: moveHereMenu
                        showTrigger: false
                        popupAnchorItem: moveHereButton
                        focusReturnTarget: moveHereButton
                        alignPopupRight: !I18n.isRtl
                        options: root.movableInterfaces.map(name => FirewallService.interfaceTitle(name))
                        optionValues: root.movableInterfaces
                        onValueChanged: value => {
                            currentValue = "";
                            root.moveInterface(value, root.zoneName);
                        }
                    }
                }
            }

            Repeater {
                model: root.zone?.interfaces ?? []

                delegate: SettingsRow {
                    id: interfaceRow

                    required property string modelData

                    readonly property var moveTargets: root.assignableZones.filter(name => name !== root.zoneName)

                    iconName: "lan"
                    title: FirewallService.interfaceTitle(modelData)
                    modified: !!SettingsData.firewallInterfaceNames[modelData]
                    onResetRequested: FirewallService.setInterfaceLabel(modelData, "")

                    DActionButton {
                        iconName: "edit"
                        tooltipText: I18n.tr("Rename")
                        onClicked: {
                            interfaceDialog.iface = interfaceRow.modelData;
                            interfaceDialog.show(FirewallService.interfaceLabel(interfaceRow.modelData));
                        }
                    }

                    DActionButton {
                        id: moveButton
                        visible: !root.readOnly && interfaceRow.moveTargets.length > 0
                        enabled: !FirewallService.busy
                        iconName: "swap_horiz"
                        tooltipText: I18n.tr("Move to another zone", "firewalld interface button")
                        onClicked: moveMenu.openDropdownMenu()

                        DDropdown {
                            id: moveMenu
                            showTrigger: false
                            popupAnchorItem: moveButton
                            focusReturnTarget: moveButton
                            alignPopupRight: !I18n.isRtl
                            options: interfaceRow.moveTargets
                            onValueChanged: value => {
                                // A cancelled or failed move must still let the same zone be picked again.
                                currentValue = "";
                                root.moveInterface(interfaceRow.modelData, value);
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Rules", "firewall rules section")
            visible: root.showRules
            headerActions: DButton {
                visible: !root.readOnly
                text: I18n.tr("Add")
                iconName: "add"
                buttonHeight: Theme.buttonHeightXS
                onClicked: root.openRule(null, false)
            }

            SettingsNoteRow {
                visible: root.readOnly
                noteIconName: "info"
                tint: Theme.surfaceVariantText
                tintBackground: SettingsMetrics.controlSurface
                text: I18n.tr("This zone is managed by another program, so its rules can't be edited here.", "firewall info message")
            }

            SettingsRow {
                visible: root.visibleRules.length === 0
                subtitle: I18n.tr("No rules", "firewall rules status message")
            }

            Repeater {
                model: root.visibleRules

                delegate: SettingsRow {
                    id: ruleRow

                    required property var modelData

                    readonly property bool editable: modelData.kind !== "raw" && !root.readOnly

                    iconBox: true
                    iconName: root.actionIcon(modelData)
                    iconColor: root.actionColor(modelData)
                    title: FirewallService.ruleTitle(modelData)
                    subtitle: deleteButton.confirming ? I18n.tr("Confirm Delete") : FirewallService.ruleSource(modelData)
                    subtitleColor: deleteButton.confirming ? Theme.error : Theme.surfaceVariantText
                    clickable: editable
                    onClicked: keyboard => root.openRule(modelData, keyboard)

                    DIcon {
                        name: "chevron_right"
                        size: Theme.iconSize
                        color: Theme.surfaceVariantText
                        rotation: I18n.isRtl ? 180 : 0
                        visible: ruleRow.editable
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    SettingsDivider {
                        vertical: true
                        visible: ruleRow.editable
                    }

                    SettingsDeleteButton {
                        id: deleteButton
                        visible: !root.readOnly
                        enabled: !FirewallService.busy
                        onDeleteRequested: FirewallService.removeRule(root.zoneName, ruleRow.modelData.id)
                    }
                }
            }
        }
    }
}
