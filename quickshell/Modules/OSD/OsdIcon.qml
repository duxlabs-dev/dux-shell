import QtQuick
import qs.Common
import qs.DCommon.Widgets

Loader {
    id: root

    property string iconName: ""
    property string label: ""
    property color iconColor: Theme.onSecondaryContainer
    property color backgroundColor: Theme.secondaryContainer
    property bool filled: false
    property bool tonal: true
    property bool interactive: false
    property bool available: true
    readonly property bool hovered: item?.hovered ?? false
    readonly property real glyphSize: Math.min(Theme.iconSize, width)

    signal clicked

    width: Theme.buttonHeightS
    height: width
    sourceComponent: interactive ? action : indicator

    Component {
        id: action

        DActionButton {
            buttonSize: root.width
            iconName: root.iconName
            iconSize: root.glyphSize
            iconColor: root.iconColor
            backgroundColor: !root.tonal ? "transparent" : enabled ? root.backgroundColor : Theme.onSurface_12
            Accessible.name: root.label
            enabled: root.available
            onClicked: root.clicked()
        }
    }

    Component {
        id: indicator

        Rectangle {
            radius: Theme.fullRadius(width, height)
            color: !root.tonal ? "transparent" : root.available ? root.backgroundColor : Theme.onSurface_12

            DIcon {
                anchors.centerIn: parent
                name: root.iconName
                size: root.glyphSize
                color: root.available ? root.iconColor : Theme.onSurface_38
                filled: root.filled
            }
        }
    }
}
