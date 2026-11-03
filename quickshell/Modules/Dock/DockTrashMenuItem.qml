import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string text: ""
    property bool isDestructive: false

    signal triggered

    implicitWidth: contentRow.implicitWidth + Theme.spacingS * 2
    height: 28
    radius: Theme.cornerRadius
    opacity: enabled ? 1 : 0.4
    color: {
        if (!area.containsMouse || !enabled)
            return "transparent";
        if (isDestructive)
            return Theme.errorHover;
        return BlurService.hoverColor(Theme.widgetBaseHoverColor);
    }

    Row {
        id: contentRow
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        DIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: 14
            color: root.isDestructive && area.containsMouse && root.enabled ? Theme.error : Theme.surfaceText
            opacity: 0.7
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            font.pixelSize: Theme.fontSizeSmall
            color: root.isDestructive && area.containsMouse && root.enabled ? Theme.error : Theme.surfaceText
            font.weight: Theme.fontWeight
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
    }

    DRipple {
        id: ripple
        rippleColor: root.isDestructive ? Theme.error : Theme.surfaceText
        cornerRadius: Theme.cornerRadius
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => ripple.trigger(mouse.x, mouse.y)
        onClicked: root.triggered()
    }
}
