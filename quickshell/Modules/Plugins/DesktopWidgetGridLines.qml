import QtQuick
import qs.Common

Item {
    id: root

    required property int gridSize
    required property real extentWidth
    required property real extentHeight

    opacity: 0.3

    Repeater {
        model: Math.ceil(root.extentWidth / root.gridSize)

        Rectangle {
            required property int index
            x: index * root.gridSize
            y: 0
            width: 1
            height: root.extentHeight
            color: Theme.primary
        }
    }

    Repeater {
        model: Math.ceil(root.extentHeight / root.gridSize)

        Rectangle {
            required property int index
            x: 0
            y: index * root.gridSize
            width: root.extentWidth
            height: 1
            color: Theme.primary
        }
    }
}
