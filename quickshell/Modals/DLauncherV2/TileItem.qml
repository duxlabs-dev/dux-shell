pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2.Components

LauncherTile {
    id: root
    imageTile: true

    readonly property string toplevelId: item?.data?.toplevelId ?? ""
    readonly property var waylandToplevel: {
        if (!toplevelId || !item?.pluginId)
            return null;
        const pluginInstance = PluginService.pluginInstances[item.pluginId];
        if (!pluginInstance?.getToplevelById)
            return null;
        return pluginInstance.getToplevelById(toplevelId);
    }
    readonly property bool hasScreencopy: waylandToplevel !== null

    readonly property string imageIconValue: {
        if (!item)
            return "";
        if (hasScreencopy)
            return "";
        var data = item.data;
        if (data?.imageUrl)
            return "image:" + data.imageUrl;
        if (data?.imagePath)
            return "image:" + data.imagePath;
        if (data?.path && isImageFile(data.path))
            return "image:" + data.path;
        switch (item.iconType) {
        case "material":
        case "nerd":
            return "material:" + (item.icon || "image");
        case "unicode":
            return "unicode:" + (item.icon || "");
        case "composite":
            return item.iconFull || "";
        case "image":
        default:
            return item.icon || "";
        }
    }

    function isImageFile(path) {
        if (!path)
            return false;
        var ext = path.split('.').pop().toLowerCase();
        return ["jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "jxl", "avif", "heif", "exr"].indexOf(ext) >= 0;
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.spacingXS

        ClippingRectangle {
            id: imageContainer
            anchors.fill: parent
            radius: Theme.cornerRadiusM
            color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium

            ScreencopyView {
                id: screencopyView
                anchors.fill: parent
                captureSource: root.visible ? root.waylandToplevel : null
                live: root.visible && root.hasScreencopy
                visible: root.hasScreencopy

                Rectangle {
                    anchors.fill: parent
                    color: root.isHovered ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover) : Theme.withAlpha(Theme.surfaceVariant, 0)
                }
            }

            AppIconRenderer {
                anchors.fill: parent
                iconValue: root.imageIconValue
                iconSize: Math.min(parent.width, parent.height)
                animate: root.visible && root.item?.data?.animated === true
                fallbackText: (root.item?.name?.length > 0) ? root.item.name.charAt(0).toUpperCase() : "?"
                materialIconSizeAdjustment: iconSize * 0.3
                visible: !root.hasScreencopy
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: labelText.implicitHeight + Theme.spacingS * 2
                color: root.isSelected ? Theme.selectedContainer : Theme.foregroundColor(Theme.chipSurface, Theme.isFloatingWindow(root))
                visible: root.item?.name?.length > 0

                StyledText {
                    id: labelText
                    anchors.fill: parent
                    anchors.margins: Theme.spacingXS
                    text: root.item?._hName ?? root.item?.name ?? ""
                    textFormat: root.item?._hRich ? Text.RichText : Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.fontFamily
                    color: root.contentColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.spacingXS
                width: Theme.iconSizeMedium
                height: Theme.iconSizeMedium
                radius: Theme.fullRadius(width, height)
                color: Theme.primary
                visible: root.isSelected

                DIcon {
                    anchors.centerIn: parent
                    name: "check"
                    size: Theme.iconSizeSmall
                    color: Theme.primaryText
                }
            }

            Rectangle {
                id: attributionBadge
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Theme.spacingXS
                width: root.hasScreencopy ? Theme.buttonHeightXS : Theme.buttonHeightS
                height: root.hasScreencopy ? Theme.buttonHeightXS : Theme.iconSizeSmall
                radius: root.hasScreencopy ? Theme.fullRadius(width, height) : Theme.cornerRadiusXS
                color: root.hasScreencopy ? Theme.chipSurface : Theme.withAlpha(Theme.chipSurface, 0)
                visible: attributionImage.status === Image.Ready

                Image {
                    id: attributionImage
                    anchors.fill: parent
                    anchors.margins: root.hasScreencopy ? Theme.spacingXS : 0
                    fillMode: Image.PreserveAspectFit
                    source: root.item?.data?.attribution || ""
                    asynchronous: true
                    sourceSize.width: LauncherMetrics.gridIconSize * 2
                    sourceSize.height: LauncherMetrics.gridIconSize * 2
                    mipmap: true
                }
            }

            SourceBadge {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.spacingXS
                source: root.item?.type === "app" ? (root.item.source || "") : ""
                glyphSize: Theme.iconSizeSmall
                badgeVisible: !root.isSelected
            }
        }
    }
}
