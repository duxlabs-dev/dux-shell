pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.DBar

Grid {
    id: root

    property var bar: null
    property var overflowPopout: null
    property bool popupUsesVerticalLine: false

    property var items: []
    property int customColumns: 5
    property real customItemSize: Theme.iconSizeSmall + Theme.spacingS
    property real customIconSize: Theme.iconSizeSmall
    property real customSpacing: Theme.spacingXXS

    readonly property var effectiveItems: bar ? bar.hiddenBarItems : items
    readonly property real effectiveItemSize: bar ? (bar.trayItemSize + 4) : customItemSize
    readonly property real effectiveIconSize: bar ? bar.trayIconSize : customIconSize

    signal itemClicked(var trayItem, var mouse, var itemArea)

    columns: {
        if (bar)
            return popupUsesVerticalLine ? 1 : (bar.useSingleLineOverflowPopup ? effectiveItems.length : Math.min(5, effectiveItems.length));
        return customColumns;
    }
    spacing: customSpacing
    rowSpacing: bar ? 2 : customSpacing

    Repeater {
        model: root.effectiveItems

        Item {
            id: overflowItemRoot
            required property var modelData
            required property int index
            readonly property var trayItem: modelData
            readonly property string itemKey: TrayMenuManager.getTrayItemKey(trayItem)
            readonly property string iconSource: TrayMenuManager.iconSourceFor(trayItem)

            width: root.effectiveItemSize
            height: root.effectiveItemSize
            z: popupDragHandler.dragging ? 100 : 0

            property real shiftOffset: root.bar ? root.bar.dragShiftOffset(index, root.bar.popupDraggedIndex, root.bar.popupDropTargetIndex, root.effectiveItemSize + 2) : 0

            transform: Translate {
                x: !root.popupUsesVerticalLine ? overflowItemRoot.shiftOffset + (popupDragHandler.dragging ? popupDragHandler.dragAxisOffset : 0) : 0
                y: root.popupUsesVerticalLine ? overflowItemRoot.shiftOffset + (popupDragHandler.dragging ? popupDragHandler.dragAxisOffset : 0) : 0
                Behavior on x {
                    enabled: root.bar && !root.bar.suppressShiftAnimation && !root.popupUsesVerticalLine
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: root.bar && !root.bar.suppressShiftAnimation && root.popupUsesVerticalLine
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }

            BarPillSurface {
                anchors.fill: parent
                style: root.bar ? BarMetrics.widgetStyle(root.bar.barConfig) : "pills"
                pressed: itemArea.pressed
                radiusOverride: root.bar ? -1 : Theme.fullRadius(width, height)
                color: itemArea.pressed
                    ? Theme.withAlpha(root.bar ? Theme.onSurface : Theme.surfaceText, Theme.stateLayerPressed)
                    : (itemArea.containsMouse ? (root.bar ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover) : Theme.surfaceTextHover) : "transparent")
                border.width: popupDragHandler.dragging ? Theme.outlineWidthFocused : 0
                border.color: Theme.primary
                opacity: popupDragHandler.dragging ? 0.8 : 1.0
            }

            Item {
                id: popupDragHandler
                anchors.fill: parent
                property bool dragging: false
                property point dragStartPos: Qt.point(0, 0)
                property real dragAxisOffset: 0
                property bool longPressing: false

                Timer {
                    id: popupLongPressTimer
                    interval: 400
                    repeat: false
                    onTriggered: popupDragHandler.longPressing = true
                }
            }

            TrayItemIcon {
                anchors.fill: parent
                tray: root.bar
                trayItem: overflowItemRoot.trayItem
                source: overflowItemRoot.iconSource
                iconSize: root.effectiveIconSize
                fallbackTextColor: root.bar ? (root.bar.trayTextColor ?? Theme.widgetTextColor) : Theme.surfaceTextSecondary
            }

            MouseArea {
                id: itemArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: (root.bar && popupDragHandler.longPressing) ? Qt.DragMoveCursor : Qt.PointingHandCursor

                onPressed: mouse => {
                    if (root.bar && mouse.button === Qt.LeftButton) {
                        popupDragHandler.dragStartPos = Qt.point(mouse.x, mouse.y);
                        popupLongPressTimer.start();
                    }
                }
                onReleased: mouse => {
                    if (root.bar) {
                        popupLongPressTimer.stop();
                        const wasDragging = popupDragHandler.dragging;
                        if (wasDragging)
                            root.bar.finishPopupDrag();

                        popupDragHandler.longPressing = false;
                        popupDragHandler.dragging = false;
                        popupDragHandler.dragAxisOffset = 0;
                    }
                }
                onPositionChanged: mouse => {
                    if (!root.bar)
                        return;
                    const axisDelta = root.popupUsesVerticalLine ? (mouse.y - popupDragHandler.dragStartPos.y) : (mouse.x - popupDragHandler.dragStartPos.x);
                    if (popupDragHandler.longPressing && !popupDragHandler.dragging && Math.abs(axisDelta) > 5) {
                        popupDragHandler.dragging = true;
                        root.bar.beginPopupDrag(overflowItemRoot.index);
                    }
                    if (!popupDragHandler.dragging)
                        return;

                    popupDragHandler.dragAxisOffset = axisDelta;
                    root.bar.updatePopupDrag(axisDelta, overflowItemRoot.index);
                }
                onClicked: mouse => {
                    if (popupDragHandler.dragging)
                        return;
                    if (!overflowItemRoot.trayItem)
                        return;

                    if (!root.bar) {
                        root.itemClicked(overflowItemRoot.trayItem, mouse, itemArea);
                        return;
                    }

                    if (mouse.button === Qt.LeftButton && !overflowItemRoot.trayItem.onlyMenu) {
                        overflowItemRoot.trayItem.activate();
                        root.bar.menuOpen = false;
                        return;
                    }
                    const localPos = itemArea.mapToGlobal(mouse.x, mouse.y);
                    const isStandalone = !root.overflowPopout?.useConnectedBackend;
                    const popX = isStandalone ? (root.overflowPopout?.alignedX || 0) : 0;
                    const popY = isStandalone ? (root.overflowPopout?.alignedY || 0) : 0;
                    const gx = localPos.x + popX;
                    const gy = localPos.y + popY;
                    if (!overflowItemRoot.trayItem.hasMenu) {
                        root.bar.callContextMenuFallback(overflowItemRoot.trayItem.id, Math.round(gx), Math.round(gy));
                        return;
                    }
                    root.bar.showForTrayItemAtGlobalPoint(overflowItemRoot.trayItem, gx, gy, itemArea.width, root.bar.parentScreen, root.bar.isAtBottom, root.bar.isVerticalOrientation, root.bar.axis);
                }
            }
        }
    }
}
