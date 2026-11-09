pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import "../../../Common/ConnectionEditor.js" as CE

SettingsCard {
    id: root

    required property var editor

    readonly property int rev: editor.revision
    readonly property var sec: {
        rev;
        return editor.draft?.gsm ?? {};
    }
    // Invalid input is never written, so validity comes from the typed text.
    readonly property bool valid: netIdRow.ok && mtuRow.ok
    readonly property bool passwordSaved: CE.secretSaved(sec, "password")

    function put(key, v) {
        editor.setValue("gsm", key, v);
    }

    function setSaved(saved) {
        put("password-flags", saved ? undefined : 2);
        if (!saved)
            put("password", undefined);
    }

    function setPin(text) {
        // An empty field on a stored profile keeps the stored PIN.
        if (text === "" && !editor.isNew)
            put("pin", editor.original?.gsm?.pin);
        else
            put("pin", text === "" ? undefined : text);
    }

    // kind: "text", "number" (empty or 0 removes) or "netid" (5-6 digits; invalid input is not written).
    // writer(trimmed) replaces the default single-key write.
    component TextRow: ConnectionSyncedRow {
        id: row
        property string key: ""
        property string kind: "text"
        property var writer: null

        enabled: !root.editor.readOnly
        stored: String(root.sec[key] ?? "")
        check: t => row.kind === "number" ? (/^\d*$/.test(t) && Number(t) <= 4294967295) : (row.kind !== "netid" || /^(\d{5,6})?$/.test(t))
        commit: t => {
            if (row.writer)
                row.writer(t);
            else if (row.kind === "number")
                root.put(row.key, parseInt(t) > 0 ? parseInt(t) : undefined);
            else
                root.put(row.key, t === "" ? undefined : t);
        }
    }

    title: I18n.tr("Cellular")

    TextRow {
        text: "APN"
        placeholderText: I18n.tr("Auto")
        key: "apn"
        writer: t => root.editor.setSection("gsm", CE.applyApn(root.sec, t, root.editor.original?.gsm))
    }

    TextRow {
        text: I18n.tr("Username")
        key: "username"
    }

    ConnectionSyncedRow {
        secret: true
        text: I18n.tr("Password")
        enabled: !root.editor.readOnly && root.passwordSaved
        stored: String(root.sec.password ?? "")
        commit: t => root.put("password", t === "" ? undefined : t)
    }

    SettingsToggleRow {
        text: I18n.tr("Save password")
        enabled: !root.editor.readOnly
        checked: root.passwordSaved
        onToggled: checked => root.setSaved(checked)
    }

    ConnectionSyncedRow {
        secret: true
        text: I18n.tr("PIN")
        enabled: !root.editor.readOnly
        stored: String(root.sec.pin ?? "")
        same: (t, s) => t === s || (t === "" && s === String(root.editor.original?.gsm?.pin ?? ""))
        commit: t => root.setPin(t)
    }

    SettingsToggleRow {
        text: I18n.tr("Allow roaming", "mobile broadband")
        enabled: !root.editor.readOnly
        checked: root.sec["home-only"] !== true
        onToggled: checked => root.put("home-only", checked ? undefined : true)
    }

    TextRow {
        id: netIdRow
        text: I18n.tr("Network ID", "mobile operator MCC-MNC code")
        key: "network-id"
        kind: "netid"
        maximumLength: 6
    }

    TextRow {
        text: I18n.tr("Number", "phone number dialed to connect, e.g. *99#")
        key: "number"
    }

    TextRow {
        id: mtuRow
        text: "MTU"
        placeholderText: I18n.tr("Auto")
        key: "mtu"
        kind: "number"
        maximumLength: 10
    }
}
