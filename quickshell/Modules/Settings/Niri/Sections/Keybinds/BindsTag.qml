pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Rectangle {
    id: root

    property string icon: ""
    property alias text: label.text
    property string tip: ""
    property bool warn: false
    // Flow breaks between tags, not inside: a tag wider than its slot wraps its label instead of clipping
    property real maximumWidth: 0

    implicitWidth: row.implicitWidth + Theme.spacingS * 2
    implicitHeight: Math.max(row.implicitHeight, Theme.iconSizeSmall) + Theme.spacingXXS * 2
    width: maximumWidth > 0 ? Math.min(implicitWidth, maximumWidth) : implicitWidth
    radius: height / 2
    color: warn ? Theme.withAlpha(Theme.warning, 0.2) : Theme.surfaceContainerHigh

    HoverHandler {
        id: hover
        enabled: root.tip !== ""
    }

    Loader {
        active: hover.hovered
        sourceComponent: DTooltipHost {
            target: root
            side: "top"
            text: root.tip
            Component.onCompleted: Qt.callLater(schedule)
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        width: parent.width - Theme.spacingS * 2
        spacing: Theme.spacingXXS

        DIcon {
            id: tagIcon
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            size: Theme.iconSizeSmall
            color: root.warn ? Theme.warning : Theme.surfaceVariantText
        }

        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (tagIcon.visible ? tagIcon.width + parent.spacing : 0)
            wrapMode: root.maximumWidth > 0 ? Text.WrapAnywhere : Text.NoWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }
    }
}
