pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: root

    property int minutes: 0
    readonly property int hours: Math.floor(minutes / 60)
    readonly property int remainder: minutes % 60
    readonly property int maxHours: 23
    readonly property int maxRemainder: 59
    readonly property int minuteStep: 5
    readonly property real cellWidth: (width - spacing) / 2
    readonly property real digitHeight: Theme.iconButtonSize * 2

    signal committed(int minutes)

    function commit(nextHours, nextRemainder) {
        committed(Math.max(0, Math.min(maxHours, nextHours)) * 60 + Math.max(0, Math.min(maxRemainder, nextRemainder)));
    }

    spacing: Theme.spacingM

    component Cell: Column {
        id: cell

        property string label: ""
        property int value: 0
        property int maximum: 0

        signal stepped(int direction)

        width: root.cellWidth
        spacing: Theme.spacingS

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: cell.label
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceVariantText
        }

        Row {
            width: parent.width
            height: root.digitHeight
            spacing: Theme.groupedListGap
            LayoutMirroring.enabled: false

            StyledRect {
                width: parent.width - parent.spacing - steppers.width
                height: parent.height
                radius: SettingsMetrics.groupInnerRadius
                topLeftRadius: Theme.groupedListOuterRadius
                bottomLeftRadius: Theme.groupedListOuterRadius
                color: SettingsMetrics.controlColor

                NumericText {
                    anchors.centerIn: parent
                    text: String(cell.value).padStart(2, "0")
                    font.pixelSize: Theme.fontSizeDisplayLarge
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }
            }

            Column {
                id: steppers
                width: Theme.buttonHeightM
                height: parent.height
                spacing: Theme.groupedListGap

                DActionButton {
                    width: parent.width
                    height: (parent.height - parent.spacing) / 2
                    radius: SettingsMetrics.groupInnerRadius
                    topRightRadius: Theme.groupedListOuterRadius
                    iconName: "keyboard_arrow_up"
                    iconSize: Theme.iconSize
                    iconColor: Theme.onSecondaryContainer
                    backgroundColor: Theme.secondaryContainer
                    enabled: cell.value < cell.maximum
                    Accessible.name: I18n.tr("Increase", "Accessible name for a button that increases a numeric value")
                    onClicked: cell.stepped(1)
                }

                DActionButton {
                    width: parent.width
                    height: (parent.height - parent.spacing) / 2
                    radius: SettingsMetrics.groupInnerRadius
                    bottomRightRadius: Theme.groupedListOuterRadius
                    iconName: "keyboard_arrow_down"
                    iconSize: Theme.iconSize
                    iconColor: Theme.onSecondaryContainer
                    backgroundColor: Theme.secondaryContainer
                    enabled: cell.value > 0
                    Accessible.name: I18n.tr("Decrease", "Accessible name for a button that decreases a numeric value")
                    onClicked: cell.stepped(-1)
                }
            }
        }
    }

    Cell {
        label: I18n.tr("Hours", "duration picker column label")
        value: root.hours
        maximum: root.maxHours
        onStepped: direction => root.commit(root.hours + direction, root.remainder)
    }

    Cell {
        label: I18n.tr("Minutes", "duration picker column label")
        value: root.remainder
        maximum: root.maxRemainder
        onStepped: direction => root.commit(root.hours, root.remainder + direction * root.minuteStep)
    }
}
