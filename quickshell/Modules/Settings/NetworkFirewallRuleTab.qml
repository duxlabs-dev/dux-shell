pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    property var parentModal: null
    property string zone: ""
    property string ruleId: ""

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property bool isNew: ruleId === ""
    readonly property var rule: isNew ? null : FirewallService.findRule(zone, ruleId)
    readonly property bool gone: !isNew && rule === null
    readonly property bool shouldLeave: gone && !FirewallService.busy
    readonly property bool canName: FirewallService.backend === "ufw"

    property bool isService: true
    property string service: ""
    property string port: ""
    property string proto: "tcp"
    property string action: "allow"
    property string source: ""
    property string name: ""

    readonly property bool portValid: /^[0-9]{1,5}(-[0-9]{1,5})?$/.test(port) && !(proto === "both" && port.includes("-"))
    readonly property bool canSave: !FirewallService.busy && (isService ? service !== "" : portValid)
    readonly property var draft: ({
            "kind": isService ? "service" : "port",
            "target": isService ? service : port,
            "proto": proto === "both" ? "" : proto,
            "name": name
        })
    readonly property var serviceLabels: FirewallService.services.map(s => s.ports.length > 0 ? s.name + " (" + s.ports.join(", ") + ")" : s.name)

    // The save answer may already have gone back; a second goBack would leave the Firewall page too.
    onShouldLeaveChanged: {
        if (shouldLeave && parentModal?.currentPage === "network_firewall_rule")
            parentModal.goBack();
    }

    Component.onCompleted: {
        FirewallService.refCount++;
        FirewallService.loadServices();
        if (!rule)
            return;
        isService = rule.kind === "service";
        service = isService ? rule.target : "";
        port = isService ? "" : rule.target;
        proto = rule.proto || "both";
        action = rule.action;
        source = rule.source ?? "";
        name = rule.name ?? "";
    }
    Component.onDestruction: FirewallService.refCount--

    function save() {
        const modal = parentModal;
        const params = {
            "zone": zone,
            "kind": isService ? "service" : "port",
            "action": action,
            "target": isService ? service : port,
            "proto": proto,
            "source": source.trim(),
            "name": canName ? name.trim() : ""
        };
        const done = response => {
            if (FirewallService.succeeded(response) && modal?.currentPage === "network_firewall_rule")
                modal.goBack();
        };
        if (isNew) {
            FirewallService.addRule(params, done);
            return;
        }
        params.id = ruleId;
        FirewallService.updateRule(params, done);
    }

    SettingsRenameDialog {
        id: nameDialog

        parent: root.parentModal?.modalFocusScope ?? root
        onAccepted: value => {
            root.name = value;
            hide();
        }
    }

    SettingsPage {
        SettingsCard {
            title: I18n.tr("General", "adjective, settings page and section title for general options")

            SettingsRow {
                title: I18n.tr("Name")
                subtitle: FirewallService.ruleTitle(root.draft)
                modified: root.name !== ""
                onResetRequested: root.name = ""

                DActionButton {
                    visible: root.canName
                    iconName: "edit"
                    tooltipText: I18n.tr("Rename")
                    onClicked: nameDialog.show(root.name)
                }
            }

            SettingsButtonGroupRow {
                text: I18n.tr("Type", "firewall rule target type")
                model: [I18n.tr("Service", "firewall rule target type"), I18n.tr("Port", "firewall rule target type")]
                currentIndex: root.isService ? 0 : 1
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        root.isService = index === 0;
                }
            }
        }

        SettingsCard {
            title: I18n.tr("Details")

            SettingsDropdownRow {
                visible: root.isService
                text: I18n.tr("Service", "firewall rule target type")
                enableFuzzySearch: true
                popupWidth: Math.round(root.width * 0.6)
                emptyText: FirewallService.servicesLoading ? I18n.tr("Loading...") : ""
                options: root.serviceLabels
                optionValues: FirewallService.services.map(s => s.name)
                currentValue: root.service
                onValueChanged: value => root.service = value
            }

            SettingsRow {
                visible: !root.isService
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Port or range", "firewall rule field")
                    placeholderText: "8080, 6000-6007"
                    text: root.port
                    isError: root.port !== "" && !root.portValid
                    onTextEdited: root.port = text
                }
            }

            SettingsButtonGroupRow {
                visible: !root.isService
                text: I18n.tr("Protocol", "firewall rule field")
                model: ["TCP", "UDP", I18n.tr("Both", "firewall rule protocol")]
                currentIndex: ["tcp", "udp", "both"].indexOf(root.proto)
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        root.proto = ["tcp", "udp", "both"][index];
                }
            }

            SettingsButtonGroupRow {
                text: I18n.tr("Action", "firewall rule field")
                model: [FirewallService.actionLabel("allow"), FirewallService.actionLabel("drop"), FirewallService.actionLabel("reject")]
                currentIndex: ["allow", "drop", "reject"].indexOf(root.action)
                onSelectionChanged: (index, selected) => {
                    if (selected)
                        root.action = ["allow", "drop", "reject"][index];
                }
            }

            SettingsRow {
                body: DTextField {
                    outlined: true
                    width: parent.width
                    labelText: I18n.tr("Source (optional)", "firewall rule field")
                    placeholderText: "192.168.1.0/24"
                    text: root.source
                    onTextEdited: root.source = text
                }
            }
        }

        SettingsFabBar {
            DFab {
                text: root.isNew ? I18n.tr("Add rule", "firewall rule add button") : I18n.tr("Save")
                iconName: root.isNew ? "add" : "check"
                busy: FirewallService.busy
                enabled: root.canSave
                onClicked: root.save()
            }
        }
    }
}
