pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property string artUrl: ""
    property real placeholderIconSize: Math.min(width, height) * 0.46
    property real cornerRadius: Math.min(width, height) * 0.22
    readonly property real renderScale: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio
    readonly property int artPixelSize: Math.max(1, Math.round(Math.max(width, height) * renderScale))

    ClippingRectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Theme.primaryContainer
        antialiasing: true

        DIcon {
            anchors.centerIn: parent
            name: "music_note"
            size: root.placeholderIconSize
            color: Theme.accentOnPrimaryContainer
            visible: artwork.status !== Image.Ready
        }

        Image {
            id: artwork

            anchors.fill: parent
            source: root.visible && root.width > 0 ? root.artUrl : ""
            asynchronous: true
            retainWhileLoading: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.artPixelSize, root.artPixelSize)
        }
    }
}
