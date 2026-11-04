import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Components

// DMS stores gaps as -1 (follow the bar spacing), -2 (leave them to the user's niri config) or a size.
NiriRow {
    id: root

    readonly property int mode: value === -2 ? 2 : value >= 0 ? 1 : 0
    // Custom starts from niri's own default
    readonly property int niriGaps: 16

    settingKey: "look.gaps"
    toggle: false
    tryValue: undefined

    DButtonGroup {
        id: group

        anchors.verticalCenter: parent.verticalCenter
        arrowKeysSelect: false
        model: [
            {
                "text": I18n.tr("Auto", "niri page: gaps follow the bar spacing"),
                "tooltip": I18n.tr("Follows the bar spacing")
            },
            {
                "text": I18n.tr("Custom", "niri page: gaps set by hand")
            },
            {
                "text": I18n.tr("My config", "niri page: gaps left to the user's niri config"),
                "tooltip": I18n.tr("DMS leaves gaps to your niri config")
            }
        ]
        currentIndex: root.mode
        Accessible.name: root.title
        onSelectionChanged: (index, selected) => {
            if (!selected || index === root.mode)
                return;
            if (index === 1) {
                root.write(root.niriGaps);
                return;
            }
            root.write(index === 2 ? -2 : -1);
        }
    }
}
