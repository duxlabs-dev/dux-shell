pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "../../../../../Common/niri/sections/corners.js" as Corners

// The active corners in words, next to the drawing.
Column {
    id: root

    required property var card

    spacing: Theme.spacingXS
    Accessible.role: Accessible.List
    Accessible.name: I18n.tr("Active corners")

    StyledText {
        visible: legend.count === 0
        height: Theme.buttonHeightXS
        verticalAlignment: Text.AlignVCenter
        text: I18n.tr("No hot corner")
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
    }

    Repeater {
        id: legend

        model: Corners.corners.filter(c => (root.card.current[c] ?? "none") !== "none")

        delegate: Row {
            id: entry

            required property string modelData
            readonly property var action: root.card.actionOf(root.card.current[modelData])

            height: Theme.buttonHeightXS
            spacing: Theme.spacingS
            Accessible.role: Accessible.ListItem
            Accessible.name: root.card.cornerInfo[modelData].text + ": " + action.text

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.card.cornerInfo[entry.modelData].icon
                size: Theme.iconSizeMedium
                color: Theme.surfaceVariantText
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: entry.action.icon
                size: Theme.iconSizeMedium
                color: Theme.primary
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: entry.action.text
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            DBadge {
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.action.dms
                text: I18n.tr("DMS")
                tooltipText: I18n.tr("Run by DMS")
            }
        }
    }
}
