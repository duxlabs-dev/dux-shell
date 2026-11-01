import QtQuick
import qs.Common
import qs.Widgets

// The tone only tints the fill: the label stays in the text colour, which reads on any tint.
Rectangle {
    property alias text: chipLabel.text
    property color tone: Theme.surfaceVariantText

    width: chipLabel.implicitWidth + Theme.spacingM * 2
    height: chipLabel.implicitHeight + Theme.spacingXS * 2
    radius: Theme.fullRadius(width, height)
    color: Theme.withAlpha(tone, 0.16)

    StyledText {
        id: chipLabel
        anchors.centerIn: parent
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
    }
}
