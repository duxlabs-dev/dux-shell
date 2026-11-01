import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string iconName
    property color tone
    property string text
    property string detail

    implicitHeight: body.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(tone, 0.12)
    border.color: Theme.withAlpha(tone, 0.4)
    border.width: Theme.outlineWidth

    Row {
        id: body
        x: Theme.spacingM
        y: Theme.spacingS
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        DIcon {
            name: root.iconName
            size: Theme.iconSizeSmall
            color: root.tone
        }

        Column {
            width: parent.width - Theme.iconSizeSmall - parent.spacing
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                text: root.text
                color: Theme.surfaceText
                wrapMode: Text.Wrap
            }

            StyledText {
                width: parent.width
                visible: root.detail !== ""
                text: root.detail
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                wrapMode: Text.Wrap
            }
        }
    }
}
