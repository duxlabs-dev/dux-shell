pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Modals.DLauncherV2.Components as Components
import "../../../Common/IconFolders.js" as IconFolders

Item {
    id: root

    property var item: null
    property bool receiving: false

    readonly property var members: item?.data?.members ?? []
    readonly property string materialIcon: item?.icon ?? ""
    readonly property real space: Math.min(width, height)
    readonly property bool neutral: IconThemeService.neutralTiles
    readonly property color fill: Theme.foregroundColor(neutral ? Theme.chipSurface : Theme.primaryContainer, Theme.isFloatingWindow(root))
    // Folders take the outline Dux Icons draws app tiles in; the circle keeps the ring.
    readonly property string tileShape: IconThemeService.tileShape
    readonly property string outline: IconFolders.outlinePath(tileShape)
    readonly property bool shaped: outline !== ""

    // AOSP Launcher3 ClippedFolderIconLayoutRule.
    readonly property int maxPreviewItems: 4
    readonly property real maxItemScale: 0.51
    readonly property real minItemScale: 0.44
    readonly property real itemRadiusScale: 1.15
    readonly property real maxRadiusDilation: 0.25

    readonly property int previewCount: Math.min(members.length, maxPreviewItems)
    readonly property real miniSize: space * (shaped ? IconFolders.gridSlot(tileShape, previewCount, 0, false).size : previewCount < maxPreviewItems ? maxItemScale : minItemScale)

    function slotCenter(index, count) {
        if (shaped) {
            const slot = IconFolders.gridSlot(tileShape, count, index, I18n.isRtl);
            return Qt.point(space * slot.x, space * slot.y);
        }
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
        default:
            return member?.icon ?? "";
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.space
        height: root.space
        radius: Theme.fullRadius(width, height)
        visible: !root.shaped
        color: root.fill
        border.width: root.receiving ? Components.LauncherMetrics.dropTargetOutlineWidth : 0
        border.color: Theme.primary
    }

    Loader {
        anchors.centerIn: parent
        active: root.shaped
        visible: active
        sourceComponent: Shape {
            id: backdrop

            // The outline is stroked on its center line, so it is pulled in by half its width to stay inside the tile.
            readonly property real stroke: root.receiving ? Components.LauncherMetrics.dropTargetOutlineWidth : 0
            readonly property real unit: width / 64
            width: Math.max(0, root.space - stroke)
            height: width
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                scale: Qt.size(backdrop.unit, backdrop.unit)
                fillColor: root.fill
                strokeColor: Theme.primary
                strokeWidth: backdrop.stroke > 0 ? backdrop.stroke : -1
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: root.outline
                }
            }
        }
    }

    Loader {
        anchors.centerIn: parent
        active: root.materialIcon.length > 0
        visible: active
        sourceComponent: DIcon {
            name: root.materialIcon
            size: Math.round(root.space - Components.LauncherMetrics.folderIconGap * 4)
            color: root.neutral ? Theme.surfaceText : Theme.accentOnPrimaryContainer
        }
    }

    ClippingRectangle {
        anchors.centerIn: parent
        width: root.space
        height: root.space
        // The grid sits inside the outline, so only the ring needs the round clip.
        radius: root.shaped ? 0 : Theme.fullRadius(width, height)
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
                iconColor: root.neutral ? Theme.surfaceText : Theme.onPrimaryContainer
                materialIconSizeAdjustment: 0
                fallbackRadius: Theme.fullRadius(width, height)
                fallbackBackgroundColor: Theme.primary
                fallbackTextColor: Theme.onPrimary
                fallbackText: modelData?.name?.charAt(0).toUpperCase() || "?"
            }
        }
    }
}
