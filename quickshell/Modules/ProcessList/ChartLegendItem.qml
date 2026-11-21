pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Row {
    id: root

    property string text: ""
    property string value: ""
    property color swatchColor: Theme.primary
    property bool dashed: false

    spacing: Theme.spacingXS

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXXS

        Repeater {
            model: root.dashed ? 2 : 1

            Rectangle {
                width: root.dashed ? Theme.spacingS : Theme.spacingL
                height: Theme.outlineWidthFocused
                radius: height / 2
                color: root.swatchColor
            }
        }
    }

    StyledText {
        text: root.text
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    NumericText {
        visible: text !== ""
        text: root.value
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }
}
