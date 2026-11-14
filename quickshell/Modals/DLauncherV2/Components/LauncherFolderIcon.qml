pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components as Components

Item {
    id: root

    property var item: null
    property bool receiving: false

    readonly property var members: item?.data?.members ?? []
    readonly property string materialIcon: item?.icon ?? ""
    readonly property real space: Math.min(width, height)

    // AOSP Launcher3 ClippedFolderIconLayoutRule.
    readonly property int maxPreviewItems: 4
    readonly property real maxItemScale: 0.51
    readonly property real minItemScale: 0.44
    readonly property real itemRadiusScale: 1.15
    readonly property real maxRadiusDilation: 0.25

    readonly property int previewCount: Math.min(members.length, maxPreviewItems)
    readonly property real miniSize: space * (previewCount < maxPreviewItems ? maxItemScale : minItemScale)

    function slotCenter(index, count) {
        const half = space / 2;
        if (count < 2)
            return Qt.point(half, half);
        const rtl = I18n.isRtl;
        const direction = rtl ? 1 : -1;
        const shift = count === 3 ? Math.PI / 2 : count === 4 ? Math.PI / 4 : 0;
        const theta0 = (rtl ? 0 : Math.PI) + direction * shift;
        // The ring visits the bottom row in reverse reading order.
        const slot = count === 4 && index >= 2 ? 5 - index : index;
        const radius = itemRadiusScale * half * (1 + maxRadiusDilation * (count - 2) / (maxPreviewItems - 2));
        const theta = theta0 + slot * (2 * Math.PI / count) * direction;
        return Qt.point(half + radius * Math.cos(theta) / 2, half - radius * Math.sin(theta) / 2);
    }

    function memberIconValue(member) {
        switch (member?.iconType) {
        case "material":
        case "nerd":
            return "material:" + (member.icon || "apps");
        case "unicode":
            return "unicode:" + (member.icon || "");
        case "composite":
            return member.iconFull || "";
        default:
            return member?.icon ?? "";
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.space
        height: root.space
        radius: Theme.fullRadius(width, height)
        color: Theme.foregroundColor(Theme.primaryContainer, Theme.isFloatingWindow(root))
        border.width: root.receiving ? Components.LauncherMetrics.dropTargetOutlineWidth : 0
        border.color: Theme.primary
    }

    Loader {
        anchors.centerIn: parent
        active: root.materialIcon.length > 0
        visible: active
        sourceComponent: DIcon {
            name: root.materialIcon
            size: Math.round(root.space - Components.LauncherMetrics.folderIconGap * 4)
            color: Theme.accentOnPrimaryContainer
        }
    }

    ClippingRectangle {
        anchors.centerIn: parent
        width: root.space
        height: root.space
        radius: Theme.fullRadius(width, height)
        color: "transparent"
        visible: root.materialIcon.length === 0

        Repeater {
            model: root.materialIcon.length === 0 ? root.members.slice(0, root.maxPreviewItems) : []

            AppIconRenderer {
                required property var modelData
                required property int index
                readonly property point center: root.slotCenter(index, root.previewCount)
                x: center.x - width / 2
                y: center.y - height / 2
                width: root.miniSize
                height: root.miniSize
                iconValue: root.memberIconValue(modelData)
                iconSize: root.miniSize
                iconColor: Theme.onPrimaryContainer
                materialIconSizeAdjustment: 0
                fallbackRadius: Theme.fullRadius(width, height)
                fallbackBackgroundColor: Theme.primary
                fallbackTextColor: Theme.onPrimary
                fallbackText: modelData?.name?.charAt(0).toUpperCase() || "?"
            }
        }
    }
}
