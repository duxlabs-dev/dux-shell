pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Common as DCommon
import qs.DCommon.Widgets

Item {
    id: root

    required property var member
    required property real iconSize
    property color iconColor: Theme.surfaceText
    property color fallbackBackgroundColor: Theme.surfaceLight
    property color fallbackTextColor: Theme.primary

    readonly property string iconValue: {
        switch (member?.iconType) {
        case "material":
        case "nerd":
            return "material:" + (member.icon || "apps");
        case "unicode":
            return "unicode:" + (member.icon || "");
        default:
            return member?.icon ?? "";
        }
    }

    implicitWidth: iconSize
    implicitHeight: iconSize

    Loader {
        id: resolvedIcon
        anchors.fill: parent
        active: !!root.member?.iconSource

        // Dock icons already hold resolved URLs; do not resolve them again.
        sourceComponent: Image {
            readonly property int rasterSize: DCommon.Style.iconRasterSize(root.iconSize * Screen.devicePixelRatio)
            source: root.member?.iconSource ?? ""
            sourceSize: Qt.size(rasterSize, rasterSize)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            mipmap: true
            retainWhileLoading: true
        }
    }

    Loader {
        anchors.fill: parent
        active: !resolvedIcon.active || (resolvedIcon.item as Image)?.status === Image.Error
        sourceComponent: AppIconRenderer {
            visible: true
            iconValue: root.iconValue
            iconSize: root.iconSize
            iconColor: root.iconColor
            materialIconSizeAdjustment: 0
            fallbackRadius: Theme.fullRadius(width, height)
            fallbackBackgroundColor: root.fallbackBackgroundColor
            fallbackTextColor: root.fallbackTextColor
            fallbackText: root.member?.name?.charAt(0).toUpperCase() || "?"
        }
    }
}
