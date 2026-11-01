pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    required property var controller
    property string iconName: "blur_on"
    property string iconMode: "icon"
    property string iconPath: ""
    property string iconColor: "primary"

    readonly property real diameter: Math.min(width, height)
    readonly property real faceSize: Math.max(Theme.fontSizeSmall, Math.round(root.diameter * 0.46))
    readonly property color symbolColor: {
        switch (root.iconColor) {
        case "":
        case "primary":
            return Theme.primary;
        case "surface":
            return Theme.surfaceText;
        default:
            return root.iconColor;
        }
    }

    Loader {
        id: logoLoader

        anchors.centerIn: parent
        active: root.iconMode !== "icon"

        sourceComponent: LauncherLogo {
            mode: root.iconMode
            size: root.faceSize
            colorOverride: root.iconColor
            customPath: root.iconPath
        }
    }

    // A logo mode with nothing to show (unknown compositor, empty custom path) falls back to the symbol.
    DIcon {
        anchors.centerIn: parent
        visible: !(logoLoader.item as LauncherLogo)?.resolvedMode
        name: root.iconName
        size: root.faceSize
        color: root.symbolColor
    }

    Rectangle {
        readonly property real badgeSize: Math.max(Theme.spacingXS, Math.round(root.diameter * 0.2))

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Math.round(root.diameter * 0.08)
        width: badgeSize
        height: badgeSize
        radius: badgeSize / 2
        color: Theme.error
        visible: root.controller.homeNotificationBadge
    }
}
