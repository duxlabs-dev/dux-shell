pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modals.DLauncherV2

Rectangle {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property bool imageTile: false
    property real iconMargins: 0
    property real iconFallbackLeftMargin: 0
    property real iconFallbackRightMargin: 0
    property real iconFallbackBottomMargin: 0
    property real iconMaterialSizeAdjustment: Theme.spacingM
    property real iconUnicodeScale: Theme.fontSizeXLarge / Theme.iconSizeLarge
    property real minIconSize: Theme.iconSizeLarge
    property real maxIconSize: LauncherMetrics.gridIconSize
    property real iconSizeRatio: Theme.launcherImageRatio
    property bool externalHighlight: false
    property bool bare: false
    property bool dragSource: false
    property bool receiving: false
    readonly property bool tintedTarget: receiving && !isFolder && !imageTile && !bare
    readonly property color contentColor: isSelected ? Theme.onSelectedContainer : tintedTarget ? Theme.onPrimaryContainer : Theme.onSurface
    property var item: null
    property bool isSelected: false
    property bool isHovered: itemArea.containsMouse
    property var controller: null
    property int flatIndex: -1

    signal clicked
    signal rightClicked(real mouseX, real mouseY)
    signal pointerMoved
    signal dragPressed(real sceneX, real sceneY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragReleased(real sceneX, real sceneY)
    signal dragCanceled

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

    readonly property real contentInset: bare ? Theme.spacingS : Theme.spacingL
    readonly property int computedIconSize: bare ? Math.min(LauncherMetrics.iconsIconSize, width - contentInset * 2) : Math.min(root.maxIconSize, Math.max(root.minIconSize, width * root.iconSizeRatio))
    readonly property bool isFolder: item?.type === "folder"
    readonly property real dragThreshold: itemArea.drag.threshold

    radius: Theme.cornerRadiusL
    color: externalHighlight ? "transparent" : isSelected ? Theme.selectedContainer : bare ? "transparent" : Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    border.width: externalHighlight || bare ? 0 : Theme.layerOutlineWidth
    border.color: Theme.outlineMedium
    opacity: dragSource ? LauncherMetrics.dragSourceOpacity : (root.item?.type === "dmenu" && root.item?.data?.nonSelectable) ? 0.5 : 1.0
    scale: receiving ? LauncherMetrics.dropTargetScale : 1

    // Suppress the click even if the lifted drag is canceled.
    onDragSourceChanged: {
        if (dragSource)
            itemArea.swallowClick = true;
    }

    Behavior on scale {
        enabled: !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    Rectangle {
        anchors.fill: parent
        z: root.imageTile ? 2 : 0
        radius: root.radius
        visible: root.receiving && !root.bare && (root.imageTile || !root.isFolder)
        color: root.imageTile ? Theme.withAlpha(Theme.primary, Theme.stateLayerDrag) : Theme.primaryContainer
        border.width: LauncherMetrics.dropTargetOutlineWidth
        border.color: Theme.primary
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.withAlpha(root.contentColor, itemArea.pressed ? Theme.stateLayerPressed : Theme.stateLayerHover)
        visible: root.isHovered || itemArea.pressed
    }

    DRipple {
        id: rippleLayer
        rippleColor: root.contentColor
        cornerRadius: root.radius
    }

    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacingXS
        spacing: Theme.spacingXS
        z: 1

        SourceBadge {
            badgeVisible: !root.imageTile && !root.bare
            source: root.item?.type === "app" ? (root.item.source || "") : ""
            glyphSize: Theme.iconSizeSmall
        }

        DIcon {
            name: "push_pin"
            size: Theme.iconSizeSmall
            color: root.contentColor
            visible: root.item?.pinned === true
        }

        DIcon {
            name: root.item?.data?.checked ? "check_box" : "check_box_outline_blank"
            size: Theme.iconSizeSmall
            color: root.item?.data?.checked ? Theme.primary : root.contentColor
            visible: root.item?.type === "dmenu" && root.controller?.dmenuMultiSelect === true
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.imageTile
        sourceComponent: Item {
            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingS
                width: parent.width - root.contentInset * 2

                Loader {
                    width: root.computedIconSize
                    height: root.computedIconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !(root.item?.type === "dmenu" && root.item?.data?.nonSelectable && !root.item?.icon)
                    sourceComponent: root.isFolder ? folderIconComponent : appIconComponent

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Theme.spacingXS
                        z: -1
                        radius: Theme.cornerRadiusL
                        visible: root.bare && root.receiving && !root.isFolder
                        color: Theme.primaryContainer
                        border.width: LauncherMetrics.dropTargetOutlineWidth
                        border.color: Theme.primary
                    }

                    Component {
                        id: appIconComponent

                        AppIconRenderer {
                            fallbackRadius: Theme.fullRadius(width, height)
                            fallbackBackgroundColor: Theme.primaryContainer
                            fallbackTextColor: Theme.onPrimaryContainer
                            iconValue: root.iconValue
                            iconMargins: root.iconMargins
                            fallbackLeftMargin: root.iconFallbackLeftMargin
                            fallbackRightMargin: root.iconFallbackRightMargin
                            fallbackBottomMargin: root.iconFallbackBottomMargin
                            unicodeIconScale: root.iconUnicodeScale
                            iconSize: root.computedIconSize
                            animate: root.visible && root.item?.data?.animated === true
                            fallbackText: root.item?.name?.charAt(0).toUpperCase() || "?"
                            iconColor: root.contentColor
                            materialIconSizeAdjustment: root.iconMaterialSizeAdjustment
                        }
                    }

                    Component {
                        id: folderIconComponent

                        LauncherFolderIcon {
                            item: root.item
                            receiving: root.receiving
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    height: LauncherMetrics.tileLabelBlockHeight
                    verticalAlignment: Text.AlignTop
                    text: root.item?._hName ?? root.item?.name ?? ""
                    // RichText ignores elide and maximumLineCount, so only dmenu markup rows get it.
                    textFormat: !root.item?._hRich ? Text.PlainText : root.item.data?.markup ? Text.RichText : Text.StyledText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    font.family: Theme.fontFamily
                    color: root.contentColor
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    MouseArea {
        id: itemArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.dragSource ? Qt.DragMoveCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: root.dragSource

        property bool swallowClick: false

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton) {
                if (!(pressedButtons & Qt.LeftButton))
                    return;
                swallowClick = true;
                root.dragCanceled();
                return;
            }
            swallowClick = false;
            rippleLayer.trigger(mouse.x, mouse.y);
            const scenePos = mapToItem(null, mouse.x, mouse.y);
            root.dragPressed(scenePos.x, scenePos.y);
        }
        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            const scenePos = mapToItem(null, mouse.x, mouse.y);
            root.dragReleased(scenePos.x, scenePos.y);
        }
        onCanceled: root.dragCanceled()
        onClicked: mouse => {
            if (swallowClick)
                return;
            if (mouse.button === Qt.RightButton) {
                var scenePos = mapToItem(null, mouse.x, mouse.y);
                root.rightClicked(scenePos.x, scenePos.y);
                return;
            }
            root.clicked();
        }

        onPositionChanged: mouse => {
            root.pointerMoved();
            if (root.controller)
                root.controller.keyboardNavigationActive = false;
            if (!(pressedButtons & Qt.LeftButton))
                return;
            const scenePos = mapToItem(null, mouse.x, mouse.y);
            root.dragMoved(scenePos.x, scenePos.y);
        }
    }
}
