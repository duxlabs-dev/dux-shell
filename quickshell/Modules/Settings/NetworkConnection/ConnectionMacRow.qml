import QtQuick
import "../../../Common/ConnectionEditor.js" as CE

// Hardware address in section[key]; only a valid MAC or empty is written.
ConnectionSyncedRow {
    id: root

    required property var editor
    required property string section
    required property string key

    placeholderText: "AA:BB:CC:DD:EE:FF"
    stored: {
        root.editor.revision;
        return String(root.editor.draft?.[root.section]?.[root.key] ?? "");
    }
    check: t => t === "" || CE.isValidMac(t)
    commit: t => root.editor.setValue(root.section, root.key, t === "" ? undefined : t)
}
