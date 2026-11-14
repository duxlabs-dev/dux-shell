import QtQuick

// Integer setting in min..max; empty removes the key so NM applies its default. With zeroUnset, 0 does too.
ConnectionSyncedRow {
    id: root

    required property var editor
    required property string section
    required property string key
    property int min: 0
    property real max: 0
    property bool zeroUnset: false

    stored: {
        root.editor.revision;
        const v = root.editor.draft?.[root.section]?.[root.key];
        return v === undefined || v === null || (root.zeroUnset && v === 0) ? "" : String(v);
    }
    check: t => t === "" || (/^\d+$/.test(t) && Number(t) >= root.min && Number(t) <= root.max)
    commit: t => root.editor.setValue(root.section, root.key, t === "" || (root.zeroUnset && Number(t) === 0) ? undefined : Number(t))
    maximumLength: String(max).length
}
