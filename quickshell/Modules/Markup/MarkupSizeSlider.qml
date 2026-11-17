pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: root

    required property var target

    spacing: Theme.spacingXS
    anchors.verticalCenter: parent?.verticalCenter

    StyledTextMetrics {
        id: widestLabel

        text: "32px"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.target.strokeSize) + "px"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceText
        width: widestLabel.advanceWidth
        horizontalAlignment: Text.AlignRight
    }

    DSlider {
        id: sizeSlider

        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconSize * 4
        minimum: 1
        maximum: 32
        step: 1
        wheelEnabled: false
        value: root.target.strokeSize
        showValue: false

        onSliderValueChanged: val => root.target.strokeSize = Math.max(1, Math.min(32, Math.round(val)))

        Binding {
            target: sizeSlider
            property: "value"
            value: root.target.strokeSize
        }
    }
}
