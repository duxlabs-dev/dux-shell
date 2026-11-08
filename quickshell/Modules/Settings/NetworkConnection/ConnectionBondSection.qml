pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property int rev: editor.revision
    readonly property var options: {
        rev;
        return editor.draft?.bond?.options ?? {};
    }
    // The host assigns a new draft object on discard and reload.
    readonly property var draftObject: editor.draft

    // Not derived from the options: ARP with an empty interval would read back as MII.
    property string monitoring: "mii"
    property var rows: []
    property bool rowsOk: true
    // Bumped by in-place row edits so validity bindings re-evaluate.
    property int rowsRev: 0
    signal reset

    readonly property bool arp: monitoring === "arp"
    readonly property var modes: CE.withChoice(CE.BOND_MODES.map(m => ({
                "label": m,
                "value": m
            })), options.mode ?? "balance-rr")
    readonly property var monitoringChoices: [
        {
            "label": "MII",
            "value": "mii"
        },
        {
            "label": "ARP",
            "value": "arp"
        }
    ]
    readonly property bool delaysSet: updelayRow.value.trim() !== "" || downdelayRow.value.trim() !== ""
    // NM rejects ARP monitoring with balance-tlb and balance-alb.
    readonly property bool arpModeBad: arp && ["balance-tlb", "balance-alb"].indexOf(options.mode ?? "balance-rr") >= 0
    // MII with an empty interval writes the default (100 ms). NM rejects delays without it,
    // and ARP without both an interval and valid targets.
    readonly property bool monitoringOk: {
        const n = parseInt(intervalRow.value.trim()) || 0;
        if (arp)
            return n > 0 && !arpModeBad && CE.isValidArpTargets(targetsRow.value);
        return !delaysSet || intervalRow.value.trim() === "" || n > 0;
    }
    readonly property bool valid: ifaceRow.ok && intervalRow.ok && updelayRow.ok && downdelayRow.ok && monitoringOk && rowsOk

    title: I18n.tr("Bond", "network connection type: bonded interfaces")
    enabled: !editor.readOnly

    function load() {
        const opts = editor.draft?.bond?.options ?? {};
        monitoring = CE.bondMonitoring(opts);
        rows = CE.kvRows(opts, CE.BOND_FORM_KEYS);
        rowsOk = true;
        reset();
    }

    // Writes the whole options dict: form-owned keys through the helpers, everything else from the rows.
    function write(mode) {
        const base = Object.assign({}, options);
        base.mode = mode ?? options.mode ?? "balance-rr";
        const out = CE.kvFromRows(rows, CE.applyBondMonitoring(base, monitoring, {
            "interval": intervalRow.value,
            "updelay": updelayRow.value,
            "downdelay": downdelayRow.value,
            "targets": targetsRow.value
        }), CE.BOND_FORM_KEYS);
        rowsOk = out !== null;
        if (out !== null)
            editor.setValue("bond", "options", out);
    }

    function setMonitoring(m) {
        monitoring = m;
        intervalRow.value = "";
        write();
    }

    function addRow() {
        rows = rows.concat([
            {
                "key": "",
                "value": ""
            }
        ]);
        write();
    }

    function removeRow(index) {
        rows = rows.filter((_, i) => i !== index);
        write();
    }

    // Edits mutate the row in place so the Repeater keeps its delegates (and focus) while typing.
    function editRow(index, field, text) {
        rows[index][field] = text;
        rowsRev++;
        write();
    }

    function rowInvalid(index) {
        rowsRev;
        const key = rows[index]?.key?.trim();
        if (key === undefined)
            return false;
        return key === "" || CE.BOND_FORM_KEYS.indexOf(key) >= 0 || rows.some((r, i) => i !== index && r.key.trim() === key);
    }

    onDraftObjectChanged: load()
    Component.onCompleted: load()

    component DigitsRow: ConnectionSyncedRow {
        resetOn: root
        maximumLength: 9
        validator: RegularExpressionValidator {
            regularExpression: /^\d*$/
        }
        check: t => /^\d*$/.test(t)
        onValueEdited: if (!syncing) root.write()
    }

    ConnectionSyncedRow {
        id: ifaceRow
        resetOn: root
        text: I18n.tr("Interface")
        stored: {
            root.rev;
            return String(root.editor.value("connection", "interface-name", ""));
        }
        check: t => CE.isValidIfname(t)
        commit: t => root.editor.setValue("connection", "interface-name", t)
    }

    SettingsDropdownRow {
        text: I18n.tr("Mode")
        titleColor: root.arpModeBad ? Theme.error : contentColor
        options: root.modes.map(c => c.label)
        currentValue: CE.choiceLabel(root.modes, root.options.mode ?? "balance-rr")
        onValueChanged: value => {
            const v = CE.choiceValue(root.modes, value);
            if (v !== undefined && v !== (root.options.mode ?? "balance-rr"))
                root.write(v);
        }
    }

    SettingsDropdownRow {
        text: I18n.tr("Link monitoring", "bond link failure detection method")
        titleColor: root.arpModeBad ? Theme.error : contentColor
        options: root.monitoringChoices.map(c => c.label)
        currentValue: CE.choiceLabel(root.monitoringChoices, root.monitoring)
        onValueChanged: value => {
            const v = CE.choiceValue(root.monitoringChoices, value);
            if (v !== undefined && v !== root.monitoring)
                root.setMonitoring(v);
        }
    }

    DigitsRow {
        id: intervalRow
        text: I18n.tr("Interval")
        isError: !ok || root.arpModeBad
        same: (typed, s) => typed === s || (!root.arp && typed === "" && s === "100")
        placeholderText: root.arp ? "" : "100"
        stored: {
            root.rev;
            return String(root.options[root.arp ? "arp_interval" : "miimon"] ?? "");
        }
    }

    DigitsRow {
        id: updelayRow
        visible: !root.arp
        text: I18n.tr("Link up delay", "bond, milliseconds")
        same: (typed, s) => typed === s || (s === "" && intervalRow.value.trim() !== "" && !(parseInt(intervalRow.value.trim()) > 0))
        stored: {
            root.rev;
            return String(root.options.updelay ?? "");
        }
    }

    DigitsRow {
        id: downdelayRow
        visible: !root.arp
        text: I18n.tr("Link down delay", "bond, milliseconds")
        same: (typed, s) => typed === s || (s === "" && intervalRow.value.trim() !== "" && !(parseInt(intervalRow.value.trim()) > 0))
        stored: {
            root.rev;
            return String(root.options.downdelay ?? "");
        }
    }

    ConnectionSyncedRow {
        id: targetsRow
        resetOn: root
        visible: root.arp
        text: I18n.tr("ARP targets", "bond ARP monitoring IP addresses")
        placeholderText: "192.168.1.1, 192.168.1.2"
        isError: root.arp && !CE.isValidArpTargets(value)
        same: (typed, stored) => typed.split(/[,\s]+/).filter(t => t !== "").join(",") === stored
        stored: {
            root.rev;
            return String(root.options.arp_ip_target ?? "");
        }
        onValueEdited: if (!targetsRow.syncing) root.write()
    }

    DCollapsibleSection {
        width: parent.width
        title: I18n.tr("Options")

        Column {
            width: parent.width
            spacing: Theme.spacingS

            SettingsRow {
                title: I18n.tr("Options")

                DButton {
                    text: I18n.tr("Add entry")
                    iconName: "add"
                    buttonHeight: Theme.buttonHeightXS
                    variant: "text"
                    onClicked: root.addRow()
                }
            }

            Repeater {
                model: root.rows

                delegate: SettingsRow {
                    id: kvRow

                    required property var modelData
                    required property int index

                    body: Row {
                        id: kvFields

                        width: parent.width
                        spacing: Theme.spacingS

                        DTextField {
                            width: Math.round((kvFields.width - kvFields.spacing * 2 - Theme.iconButtonSize) * 2 / 5)
                            outlined: true
                            labelText: I18n.tr("Key")
                            text: kvRow.modelData.key
                            isError: root.rowInvalid(kvRow.index)
                            onTextEdited: root.editRow(kvRow.index, "key", text)
                        }

                        DTextField {
                            width: Math.round((kvFields.width - kvFields.spacing * 2 - Theme.iconButtonSize) * 3 / 5)
                            outlined: true
                            labelText: I18n.tr("Value", "value of a key-value entry")
                            text: kvRow.modelData.value
                            onTextEdited: root.editRow(kvRow.index, "value", text)
                        }

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: Theme.iconButtonSize
                            iconName: "close"
                            tooltipText: I18n.tr("Remove", "verb, button that removes an item from a list")
                            onClicked: root.removeRow(kvRow.index)
                        }
                    }
                }
            }
        }
    }
}
