pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property string sectionKey: "vpn"
    readonly property int revision: editor.revision
    readonly property var vpn: {
        revision;
        return editor.draft?.[sectionKey] ?? {};
    }
    // The host assigns a new draft object on discard and reload; rows re-prefill then
    readonly property var draftObject: editor.draft
    readonly property string serviceType: vpn["service-type"] ?? ""
    readonly property string form: CE.vpnForm(serviceType)
    readonly property bool locked: editor.readOnly

    property var dataRows: []
    property var secretRows: []
    property bool dataOk: true
    property bool secretsOk: true
    // Bumped by in-place row edits so validity bindings re-evaluate.
    property int rowsRev: 0
    property string timeoutText: ""
    property string timeoutStored: ""

    readonly property bool timeoutInvalid: !/^\d*$/.test(timeoutText.trim()) || Number(timeoutText.trim()) > 4294967295
    readonly property bool valid: dataOk && secretsOk && !timeoutInvalid

    title: form !== "" ? I18n.tr("Options") : VPNService.getPluginName(serviceType)
    collapsible: true
    expanded: false
    enabled: !locked

    function owned(kind, f) {
        return CE.VPN_FORM_KEYS[f ?? form]?.[kind] ?? [];
    }

    function rowsFor(kind) {
        return kind === "secrets" ? secretRows : dataRows;
    }

    function setRows(kind, rows) {
        if (kind === "secrets")
            secretRows = rows;
        else
            dataRows = rows;
    }

    // The `vpn` binding can still hold the old draft when draftObject changes.
    function load() {
        const v = editor.draft?.[sectionKey] ?? {};
        const f = CE.vpnForm(v["service-type"] ?? "");
        dataRows = CE.kvRows(v.data, owned("data", f));
        secretRows = CE.kvRows(v.secrets, owned("secrets", f));
        dataOk = secretsOk = true;
        timeoutText = timeoutStored = v.timeout > 0 ? String(v.timeout) : "";
    }

    function writeKv(kind) {
        const out = CE.kvFromRows(rowsFor(kind), vpn[kind], owned(kind), kind === "secrets" ? editor.original?.[sectionKey]?.secrets : undefined);
        if (kind === "secrets")
            secretsOk = out !== null;
        else
            dataOk = out !== null;
        if (out !== null)
            editor.setValue(sectionKey, kind, Object.keys(out).length === 0 ? undefined : out);
    }

    function addRow(kind) {
        setRows(kind, rowsFor(kind).concat([
            {
                "key": "",
                "value": ""
            }
        ]));
        writeKv(kind);
    }

    function removeRow(kind, index) {
        setRows(kind, rowsFor(kind).filter((_, i) => i !== index));
        writeKv(kind);
    }

    // Edits mutate the row in place so the Repeater keeps its delegates (and focus) while typing.
    function editRow(kind, index, field, text) {
        if (String(rowsFor(kind)[index][field] ?? "") === text)
            return;
        rowsFor(kind)[index][field] = text;
        rowsRev++;
        writeKv(kind);
    }

    function isDuplicateOrOwned(kind, index) {
        rowsRev;
        const key = rowsFor(kind)[index].key.trim();
        const rows = rowsFor(kind);
        return key === "" || owned(kind).indexOf(key) >= 0 || rows.some((r, i) => i !== index && r.key.trim() === key);
    }

    function syncTimeout() {
        const timeout = editor.draft?.[sectionKey]?.timeout;
        const t = timeout > 0 ? String(timeout) : "";
        if (t === timeoutStored)
            return;
        timeoutStored = t;
        if ((parseInt(timeoutText.trim()) || 0) !== (timeout > 0 ? timeout : 0))
            timeoutText = t;
    }

    onDraftObjectChanged: load()
    onRevisionChanged: syncTimeout()
    Component.onCompleted: {
        load();
        expanded = form === "";
    }

    component KvRepeater: Repeater {
        id: kv

        property string kind: "data"

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
                    isError: root.isDuplicateOrOwned(kv.kind, kvRow.index)
                    onTextEdited: root.editRow(kv.kind, kvRow.index, "key", text)
                }

                DTextField {
                    width: Math.round((kvFields.width - kvFields.spacing * 2 - Theme.iconButtonSize) * 3 / 5)
                    outlined: true
                    labelText: I18n.tr("Value", "value of a key-value entry")
                    text: kvRow.modelData.value
                    echoMode: kv.kind === "secrets" ? TextInput.Password : TextInput.Normal
                    showPasswordToggle: kv.kind === "secrets"
                    onTextEdited: root.editRow(kv.kind, kvRow.index, "value", text)
                }

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: Theme.iconButtonSize
                    iconName: "close"
                    tooltipText: I18n.tr("Remove", "verb, button that removes an item from a list")
                    onClicked: root.removeRow(kv.kind, kvRow.index)
                }
            }
        }
    }

    SettingsRow {
        title: I18n.tr("Plugin")
        subtitle: root.serviceType
    }

    SettingsTextFieldRow {
        visible: root.form === ""
        text: I18n.tr("Username")
        value: root.vpn["user-name"] ?? ""
        onValueEdited: text => root.editor.setValue(root.sectionKey, "user-name", text === "" ? undefined : text)
    }

    SettingsToggleRow {
        text: I18n.tr("Stay connected across network changes", "VPN option")
        checked: root.vpn.persistent === true
        onToggled: checked => {
            const stored = root.editor.original?.[root.sectionKey]?.persistent !== undefined;
            root.editor.setValue(root.sectionKey, "persistent", checked ? true : (stored ? false : undefined));
        }
    }

    SettingsTextFieldRow {
        text: I18n.tr("Timeout", "seconds to wait for the VPN to connect, 0 = default")
        value: root.timeoutText
        placeholderText: I18n.tr("Default")
        isError: root.timeoutInvalid
        maximumLength: 10
        onValueEdited: text => {
            root.timeoutText = text;
            if (root.timeoutInvalid)
                return;
            const n = parseInt(text.trim());
            root.editor.setValue(root.sectionKey, "timeout", n > 0 ? n : undefined);
        }
    }

    SettingsRow {
        title: I18n.tr("Options")

        DButton {
            text: I18n.tr("Add entry")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            variant: "text"
            onClicked: root.addRow("data")
        }
    }

    KvRepeater {
        kind: "data"
        model: root.dataRows
    }

    SettingsRow {
        title: I18n.tr("Secrets", "VPN plugin secret values")

        DButton {
            text: I18n.tr("Add entry")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            variant: "text"
            onClicked: root.addRow("secrets")
        }
    }

    KvRepeater {
        kind: "secrets"
        model: root.secretRows
    }
}
