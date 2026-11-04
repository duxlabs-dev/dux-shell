import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Rectangle {
    id: root

    property string iconName: ""
    property string text: ""
    property string trailingIcon: ""
    property bool active: false
    property int count: 0
    property color iconColor: active ? Theme.onPrimaryContainer : Theme.surfaceText
    property color restColor: "transparent"

    signal clicked

    implicitHeight: Theme.fieldHeight
    radius: Theme.fullRadius(width, height)
    color: active ? Theme.primaryContainer : restColor
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: clicked()

    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
            return;
        root.clicked();
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.surfaceText
        opacity: mouseArea.pressed ? Theme.stateLayerPressed : mouseArea.containsMouse ? Theme.stateLayerHover : 0
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacingL
        anchors.rightMargin: Theme.spacingL
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingM

        DIcon {
            id: leadIcon
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: Theme.iconSize
            color: root.iconColor
            filled: root.active
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - leadIcon.width - parent.spacing - (countText.visible ? countText.width + parent.spacing : 0) - (tailIcon.visible ? tailIcon.width + parent.spacing : 0)
            text: root.text
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeMedium
            font.weight: root.active ? Theme.fontWeightBold : Theme.fontWeight
            color: root.active ? Theme.onPrimaryContainer : Theme.surfaceText
        }

        StyledText {
            id: countText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.count > 0
            text: root.count
            font.pixelSize: Theme.fontSizeSmall
            color: root.active ? Theme.onPrimaryContainer : Theme.surfaceVariantText
        }

        DIcon {
            id: tailIcon
            anchors.verticalCenter: parent.verticalCenter
            visible: root.trailingIcon !== ""
            name: root.trailingIcon
            size: Theme.iconSize
            color: root.active ? Theme.onPrimaryContainer : Theme.surfaceText
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    FocusRing {
        anchors.margins: Theme.focusRingWidth / 2
        radius: root.radius
    }
}
