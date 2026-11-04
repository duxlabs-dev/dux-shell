import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Components

// The widths Mod+R cycles through, picked from a fixed set; Expert only.
NiriRow {
    id: root

    // [{value, text}]
    property var choices: []

    readonly property var picked: (value ?? []).map(v => choices.findIndex(c => c.value === v)).filter(i => i >= 0).map(i => choices[i].text)

    settingKey: "columns.presetWidths"
    icon: "view_week"
    title: I18n.tr("Preset widths")
    tip: I18n.tr("Replaces the whole list from config.kdl")
    kdlKey: "layout.preset-column-widths"
    toggle: false
    visible: expert

    DButtonGroup {
        id: group

        anchors.verticalCenter: parent.verticalCenter
        model: root.choices.map(c => c.text)
        selectionMode: "multi"
        currentSelection: root.picked
        Accessible.name: root.title
        onSelectionChanged: (index, selected) => {
            const next = root.choices.filter(c => currentSelection.includes(c.text)).map(c => c.value);
            // niri needs at least one width to cycle through.
            if (next.length > 0)
                root.write(next);
            currentSelection = Qt.binding(() => root.picked);
        }
    }
}
