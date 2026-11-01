import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Icon and title heading: the section title and the title of each side pane.
Row {
    id: root

    property string icon: ""
    property string title: ""
    property real textSize: Theme.fontSizeMedium

    width: parent?.width ?? 0
    height: Math.max(Theme.iconSize, label.implicitHeight)
    spacing: Theme.spacingS
    Accessible.role: Accessible.Heading
    Accessible.name: title

    DIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: Theme.iconSize
        color: Theme.primary
    }

    StyledText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Theme.iconSize - parent.spacing
        text: root.title
        elide: Text.ElideRight
        font.pixelSize: root.textSize
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }
}
