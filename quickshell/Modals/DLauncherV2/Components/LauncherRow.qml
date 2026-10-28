pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2
import "../../../Common/htmlElide.js" as HtmlElide

DListItem {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property real iconMargins: 0
    property real iconFallbackLeftMargin: 0
    property real iconFallbackRightMargin: 0
    property real iconFallbackBottomMargin: 0
    property real iconMaterialSizeAdjustment: Theme.spacingM
    property real iconUnicodeScale: Theme.fontSizeXLarge / Theme.iconSizeLarge
    property real iconSize: LauncherMetrics.iconSize
    // Dense keeps file paths and setting categories: those names repeat across folders and pages
    property bool showDescription: Theme.densityLevel > -2 || item?.type === "file" || item?.type === "setting"
    property var item: null
    property var controller: null
    property int flatIndex: -1

    signal rightClicked(real mouseX, real mouseY)

    Accessible.name: item?.name ?? ""
    Accessible.description: item?.subtitle ?? ""
    onContextMenuRequested: (mouseX, mouseY) => {
        const pos = mapToItem(null, mouseX, mouseY);
        rightClicked(pos.x, pos.y);
    }
    onPointerMoved: {
        if (controller)
            controller.keyboardNavigationActive = false;
    }

    readonly property string iconValue: {
        if (!item)
            return "";
        switch (item.iconType) {
        case "material":
        case "nerd":
            return "material:" + (item.icon || "apps");
        case "unicode":
            return "unicode:" + (item.icon || "");
        case "composite":
            return item.iconFull || "";
        case "image":
        default:
            return item.icon || "";
        }
    }
    readonly property string previewSource: {
        const data = item?.data;
        const raw = data?.imageUrl || data?.imagePath || "";
        if (!raw || !raw.startsWith("/"))
            return raw;
        return "file://" + raw;
    }
    readonly property bool hasClipboardPreview: item?.type === "clipboard" && !!item?.data?.isImage && String(item?.data?.mimeType ?? "").startsWith("image/")

    width: parent?.width ?? Theme.fieldDefaultWidth
    height: LauncherMetrics.rowHeight
    opacity: (root.item?.type === "dmenu" && root.item?.data?.nonSelectable) ? 0.5 : 1.0

    AppIconRenderer {
        id: iconRenderer
        width: root.iconSize
        height: root.iconSize
        anchors.left: parent.left
        anchors.leftMargin: LauncherMetrics.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        visible: !(root.item?.type === "dmenu" && root.item?.data?.nonSelectable && !root.item?.icon)
        iconValue: root.iconValue
        iconMargins: root.iconMargins
        fallbackLeftMargin: root.iconFallbackLeftMargin
        fallbackRightMargin: root.iconFallbackRightMargin
        fallbackBottomMargin: root.iconFallbackBottomMargin
        unicodeIconScale: root.iconUnicodeScale
        fallbackRadius: Theme.fullRadius(width, height)
        fallbackBackgroundColor: Theme.primaryContainer
        fallbackTextColor: Theme.onPrimaryContainer
        iconSize: root.iconSize
        fallbackText: (root.item?.name?.length > 0) ? root.item.name.charAt(0).toUpperCase() : "?"
        materialIconSizeAdjustment: root.iconMaterialSizeAdjustment
        iconColor: root.contentColor
    }

    Item {
        id: textColumn
        anchors.left: iconRenderer.right
        anchors.leftMargin: LauncherMetrics.rowPadding
        anchors.right: rightContent.left
        anchors.rightMargin: rightContent.width > 0 ? Theme.spacingM : 0
        anchors.verticalCenter: parent.verticalCenter
        height: nameText.implicitHeight + (subText.visible ? subText.height + Theme.spacingXXS : 0)

        StyledText {
            id: nameText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            text: root.item?._hName ?? root.item?.name ?? ""
            textFormat: root.item?._hRich ? Text.RichText : Text.PlainText
            font.pixelSize: Theme.fontSizeLarge
            font.weight: (root.item?.type === "dmenu" && root.item?.data?.urgent) ? Theme.fontWeightBold : Theme.fontWeightMedium
            font.family: Theme.fontFamily
            color: (root.item?.type === "dmenu" && root.item?.data?.urgent) ? Theme.error : root.item?.data?.active ? Theme.primary : root.contentColor
            wrapMode: Text.WordWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
        }

        StyledTextMetrics {
            id: subProbe
            font.pixelSize: Theme.fontSizeSmall
            elide: Qt.ElideRight
            elideWidth: textColumn.width
            text: root.item?._hRich ? HtmlElide.stripHtmlTags(root.item?._hSub ?? "") : ""
        }

        readonly property int _richBudget: {
            if (!subProbe.text)
                return 0;
            var e = subProbe.elidedText;
            return e.endsWith("…") ? e.length - 1 : e.length;
        }

        StyledText {
            id: subText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: nameText.bottom
            anchors.topMargin: Theme.spacingXXS
            text: root.item?._hRich ? HtmlElide.elideRichText(root.item._hSub ?? "", textColumn._richBudget) : (root.item?.subtitle ?? "")
            textFormat: root.item?._hRich ? Text.RichText : Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.fontFamily
            color: root.supportingContentColor
            wrapMode: Text.WordWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            visible: root.showDescription && (root.item?.subtitle ?? "").length > 0
            horizontalAlignment: Text.AlignLeft
        }
    }

    Row {
        id: rightContent
        anchors.right: parent.right
        anchors.rightMargin: LauncherMetrics.rowPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        DIcon {
            name: "push_pin"
            size: Theme.iconSizeSmall
            color: root.contentColor
            visible: root.item?.pinned === true
            anchors.verticalCenter: parent.verticalCenter
        }

        DIcon {  // dmenu --multi-select checkbox
            name: root.item?.data?.checked ? "check_box" : "check_box_outline_blank"
            size: Theme.iconSizeSmall
            color: root.item?.data?.checked ? Theme.primary : root.contentColor
            visible: root.item?.type === "dmenu" && root.controller?.dmenuMultiSelect === true
            anchors.verticalCenter: parent.verticalCenter
        }

        Image {
            width: LauncherMetrics.previewWidth
            height: LauncherMetrics.previewHeight
            visible: root.previewSource.length > 0 && !root.hasClipboardPreview
            source: visible ? root.previewSource : ""
            asynchronous: true
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            anchors.verticalCenter: parent.verticalCenter
        }

        Loader {
            active: root.hasClipboardPreview
            visible: active
            width: active ? LauncherMetrics.previewWidth : 0
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: ClipboardLauncherPreview {
                entry: root.item?.data ?? null
            }
        }

        Loader {
            id: allModeToggle
            active: root.item?.type === "plugin_browse"
            visible: active
            width: active ? Theme.buttonHeightXS : 0
            height: Theme.buttonHeightXS
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Rectangle {
                id: toggleButton
                Accessible.role: Accessible.Button
                Accessible.name: toggleButton.isAllowed ? I18n.tr("Hide") : I18n.tr("Show")
                readonly property alias hovered: allModeToggleArea.containsMouse
                readonly property string pluginId: root.item?.data?.pluginId ?? ""
                readonly property bool isAllowed: {
                    SettingsData.launcherPluginVisibility;
                    return pluginId.length > 0 && SettingsData.getPluginAllowWithoutTrigger(pluginId);
                }
                radius: Theme.fullRadius(width, height)
                color: allModeToggleArea.containsMouse ? Theme.surfaceHover : Theme.withAlpha(Theme.surfaceHover, 0)

                DIcon {
                    anchors.centerIn: parent
                    name: toggleButton.isAllowed ? "visibility" : "visibility_off"
                    size: Theme.chipIconSize
                    color: toggleButton.isAllowed ? Theme.primary : Theme.onSurfaceVariant
                }

                MouseArea {
                    id: allModeToggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!toggleButton.pluginId)
                            return;
                        SettingsData.setPluginAllowWithoutTrigger(toggleButton.pluginId, !toggleButton.isAllowed);
                    }
                }
            }
        }

        Rectangle {
            visible: !!root.item?.type && root.item.type !== "app" && root.item.type !== "plugin_browse" && root.item.type !== "dmenu" && (!root.controller?.activePluginName || (root.item.badgeLabel ?? "").length > 0)
            width: typeBadge.implicitWidth + Theme.spacingS * 2
            height: Theme.iconSizeMedium
            radius: Theme.fullRadius(width, height)
            color: Theme.chipSurface
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                id: typeBadge
                font.weight: Theme.fontWeightMedium
                anchors.centerIn: parent
                text: {
                    if (!root.item)
                        return "";
                    if ((root.item.badgeLabel ?? "").length > 0)
                        return root.item.badgeLabel;
                    switch (root.item.type) {
                    case "plugin":
                        return I18n.tr("Plugin", "noun, item type label and fallback plugin name");
                    case "setting":
                        return I18n.tr("Setting", "noun, singular, launcher result type badge");
                    case "clipboard":
                        return I18n.tr("Clipboard");
                    case "file":
                        return root.item.data?.is_dir ? I18n.tr("Folder", "noun, launcher result type label for a directory") : I18n.tr("File", "noun, launcher result type badge, also printer device class");
                    default:
                        return "";
                    }
                }
                font.pixelSize: Theme.fontSizeSmall
                color: root.supportingContentColor
            }
        }

        SourceBadge {
            anchors.verticalCenter: parent.verticalCenter
            source: root.item?.type === "app" ? (root.item.source || "") : ""
            glyphSize: Theme.iconSizeSmall
        }
    }
}
