import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root
    required property var options

    property color iconColor: Theme.surfaceText
    property real actualIconSize: 40
    property int overflowCount: 0
    property bool overflowExpanded: false
    property bool isVertical: false

    function activate() {
        clicked();
    }
    signal clicked

    Rectangle {
        id: buttonBackground
        anchors.centerIn: parent
        width: actualIconSize
        height: actualIconSize
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.primary, mouseArea.containsMouse ? 0.2 : 0.1)

        Behavior on color {
            ColorAnimation {
                duration: Theme.shortDuration
            }
        }

        DIcon {
            id: arrowIcon
            anchors.centerIn: parent
            size: actualIconSize * 0.6
            name: "expand_more"
            color: root.iconColor
            rotation: isVertical ? (overflowExpanded ? 180 : 0) : (overflowExpanded ? 90 : -90)

            Behavior on rotation {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Rectangle {
        visible: overflowCount > 0 && !overflowExpanded && root.options.showOverflowBadge
        anchors.right: buttonBackground.right
        anchors.top: buttonBackground.top
        anchors.rightMargin: -4
        anchors.topMargin: -4
        width: Math.max(18, badgeText.width + 8)
        height: 18
        radius: 9
        color: Theme.primary
        z: 10

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: `+${overflowCount}`
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: Theme.onPrimary
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
