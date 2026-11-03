pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    required property var systemModel

    Column {
        anchors {
            fill: parent
            margins: Theme.spacingXL
        }
        spacing: Theme.spacingL

        Row {
            width: parent.width
            spacing: Theme.spacingM

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - valueText.width - parent.spacing
                spacing: Theme.spacingXXS

                StyledText {
                    text: root.systemModel.title
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Theme.fontWeightMedium
                }

                StyledText {
                    text: root.systemModel.mutable ? I18n.tr("Click the icon to mute", "island volume face: hint under the title") : I18n.tr("Display brightness control", "island brightness face: hint under the title")
                    color: Theme.surfaceTextSecondary
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            StyledText {
                id: valueText

                anchors.verticalCenter: parent.verticalCenter
                text: root.systemModel.displayValue
                color: Theme.primary
                font.pixelSize: 28
                font.weight: Theme.fontWeightMedium
            }
        }

        DSlider {
            id: levelSlider

            width: parent.width
            size: "m"
            insetIcon: root.systemModel.iconName
            insetIconClickable: root.systemModel.mutable
            insetIconLabel: root.systemModel.muted ? I18n.tr("Unmute") : I18n.tr("Mute")
            Accessible.name: root.systemModel.title
            onInsetIconClicked: root.systemModel.toggleMute()
            minimum: root.systemModel.minimum
            maximum: Math.max(root.systemModel.minimum + 1, Math.round(root.systemModel.maximum))
            visible: root.systemModel.levelActivity
            enabled: root.systemModel.available
            showValue: false
            unit: root.systemModel.unit
            valueOverride: Math.round(root.systemModel.value)
            onSliderValueChanged: newValue => root.systemModel.setRatio(newValue / maximum)

            Binding on value {
                value: Math.round(root.systemModel.value)
                restoreMode: Binding.RestoreNone
                when: !levelSlider.isDragging
            }
        }
    }
}
