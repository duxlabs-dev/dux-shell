import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import "../../../Common/ConnectionEditor.js" as CE

// Cloned MAC dropdown plus the manual address row for the section it is placed in.
Column {
    id: root

    required property var editor
    required property string section
    // Manual is chosen but no valid address has been typed yet, so nothing is written.
    property bool pendingManual: false
    readonly property var sec: {
        editor.revision;
        return editor.draft?.[section] ?? {};
    }
    readonly property string mode: pendingManual ? "manual" : CE.clonedMacMode(sec)
    readonly property bool ok: mode !== "manual" || manualRow.ok

    function writeManual(text) {
        pendingManual = false;
        editor.setSection(section, CE.applyClonedMac(sec, "manual", text));
    }

    width: parent?.width ?? 0
    spacing: SettingsMetrics.groupGap

    ConnectionChoiceRow {
        text: I18n.tr("Cloned MAC address", "network hardware setting")
        choices: [
            {
                "value": "default",
                "label": I18n.tr("Default")
            },
            {
                "value": "preserve",
                "label": I18n.tr("Preserve", "cloned MAC: keep the current address")
            },
            {
                "value": "permanent",
                "label": I18n.tr("Permanent", "cloned MAC: the hardware address")
            },
            {
                "value": "random",
                "label": I18n.tr("Random")
            },
            {
                "value": "stable",
                "label": I18n.tr("Stable", "cloned MAC: stable per network")
            },
            {
                "value": "manual",
                "label": I18n.tr("Manual")
            }
        ]
        stored: root.mode
        onPicked: value => {
            if (value !== "manual") {
                root.pendingManual = false;
                root.editor.setSection(root.section, CE.applyClonedMac(root.sec, value, ""));
                return;
            }
            root.pendingManual = true;
            const typed = manualRow.value.trim();
            if (CE.isValidMac(typed))
                root.writeManual(typed);
        }
    }

    ConnectionSyncedRow {
        id: manualRow
        visible: root.mode === "manual"
        text: I18n.tr("Cloned MAC address", "network hardware setting")
        placeholderText: "AA:BB:CC:DD:EE:FF"
        stored: CE.clonedMacAddress(root.sec)
        check: t => CE.isValidMac(t)
        commit: t => root.writeManual(t)
    }
}
