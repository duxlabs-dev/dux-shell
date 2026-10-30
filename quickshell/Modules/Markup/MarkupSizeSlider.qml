pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

Row {
    id: root

    required property var target

    spacing: Theme.spacingXS
    anchors.verticalCenter: parent?.verticalCenter

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.target.strokeSize) + "px"
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Bold
        color: Theme.surfaceText
        width: 34
        horizontalAlignment: Text.AlignRight
    }

    DankSlider {
        id: sizeSlider

        anchors.verticalCenter: parent.verticalCenter
        width: 90
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
