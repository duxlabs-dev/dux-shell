import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// Segmented choice, the same DButtonGroup look as the rest of the DMS settings (SettingsButtonGroupRow).
NiriRow {
    id: root

    // [{value, text, icon, tooltip}]; an option with an icon and no text shows only the icon
    property var options: []

    readonly property int currentIndex: options.findIndex(o => JSON.stringify(o.value) === JSON.stringify(value))

    toggle: false
    tryValue: options.length > 1 ? options[(currentIndex + 1) % options.length].value : undefined

    DButtonGroup {
        anchors.verticalCenter: parent.verticalCenter
        arrowKeysSelect: false
        model: root.options.map(o => ({
                    "text": o.text ?? "",
                    "icon": o.icon ?? "",
                    "tooltip": o.tooltip ?? ""
                }))
        currentIndex: root.currentIndex
        Accessible.name: root.title
        onSelectionChanged: (index, selected) => {
            if (!selected || index === root.currentIndex)
                return;
            root.write(root.options[index].value);
        }
    }
}
