pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Dock

Item {
    id: delegateItem
    required property var strip
    function activate() {
        if (isOverflowToggle)
            strip.overflowExpanded = !strip.overflowExpanded;
        else
            dockButton?.activate();
    }
    readonly property var hoveredButton: dockButton?.showTooltip ? dockButton : null
    readonly property bool interactionActive: isDragging
    required property var modelData
    required property int index

    activeFocusOnTab: (!isInOverflow || strip.overflowExpanded) && itemData.type !== "separator"
    Accessible.name: dockButton?.tooltipText ?? I18n.tr("Applications")
    Accessible.role: Accessible.Button
    onActiveFocusChanged: if (activeFocus)
        strip.surfaceContext.ensureVisible(delegateItem)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space) {
            dockButton?.activate();
            event.accepted = true;
            return;
        }
        if (!strip.renderItems)
            return;
        const previous = strip.isVertical ? Qt.Key_Up : (I18n.isRtl ? Qt.Key_Right : Qt.Key_Left);
        const next = strip.isVertical ? Qt.Key_Down : (I18n.isRtl ? Qt.Key_Left : Qt.Key_Right);
        const direction = event.key === previous ? -1 : event.key === next ? 1 : 0;
        if (!direction)
            return;
        for (let i = index + direction; i >= 0 && i < strip.renderedCount; i += direction) {
            const target = strip.itemAt(i);
            if (!target?.activeFocusOnTab)
                continue;
            target.forceActiveFocus();
            event.accepted = true;
            return;
        }
    }
    Keys.onEnterPressed: activate()
    Keys.onReturnPressed: {
        if (isOverflowToggle)
            strip.overflowExpanded = !strip.overflowExpanded;
        else
            dockButton?.activate();
    }
    readonly property Item dockButton: buttonLoader.item
    readonly property bool isAppButton: !["separator", "launcher", "trash", "overflow-toggle"].includes(itemData.type)
    property var itemData: modelData
    readonly property bool isOverflowToggle: itemData.type === "overflow-toggle"
    readonly property bool isTrash: itemData.type === "trash"
    readonly property bool isInOverflow: itemData.isInOverflow === true
    readonly property bool isDragging: isAppButton && (dockButton?.dragging ?? false)

    clip: false
    z: isDragging ? 100 : 0
    visible: !isInOverflow || strip.overflowExpanded
    opacity: (isInOverflow && !strip.overflowExpanded) ? 0 : 1
    scale: (isInOverflow && !strip.overflowExpanded) ? 0.8 : 1

    readonly property bool collapsed: isInOverflow && !strip.overflowExpanded
    readonly property real primarySize: {
        if (itemData.type === "separator")
            return 8;
        if (strip.options.compact === false && !strip.isVertical)
            return strip.targetSize + Theme.listItemHeight * 2;
        return strip.targetSize;
    }

    width: collapsed ? 0 : (strip.isVertical ? strip.crossSize : primarySize)
    height: collapsed ? 0 : (strip.isVertical ? primarySize : strip.crossSize)

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastEffects
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    property real shiftOffset: {
        if (!strip.renderItems || strip.draggedIndex < 0 || !itemData.isPinned || itemData.type === "separator")
            return 0;
        if (delegateItem.index === strip.draggedIndex)
            return 0;

        const dragIdx = strip.draggedIndex;
        const dropIdx = strip.dropTargetIndex;
        const myIdx = delegateItem.index;
        const shiftAmount = strip.targetSize + strip.itemSpacing;

        if (dropIdx < 0)
            return 0;
        if (dragIdx < dropIdx && myIdx > dragIdx && myIdx <= dropIdx)
            return -shiftAmount;
        if (dragIdx > dropIdx && myIdx >= dropIdx && myIdx < dragIdx)
            return shiftAmount;
        return 0;
    }

    readonly property var shiftSpringParams: Theme.springPreset("fastSpatial")

    SpringMotion {
        id: shiftSpring
        enabled: !strip.suppressShiftAnimation
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: delegateItem.shiftSpringParams.stiffness
        damping: delegateItem.shiftSpringParams.damping

        Component.onCompleted: snapTo(delegateItem.shiftOffset)
    }

    onShiftOffsetChanged: shiftSpring.retarget(shiftOffset)

    transform: Translate {
        x: strip.isVertical ? 0 : shiftSpring.value
        y: strip.isVertical ? shiftSpring.value : 0
    }

    Rectangle {
        visible: itemData.type === "separator"
        width: strip.isVertical ? strip.iconSize * 0.5 : 2
        height: strip.isVertical ? 2 : strip.iconSize * 0.5
        color: Theme.outlineHeavy
        radius: 1
        anchors.centerIn: parent
    }

    Loader {
        id: buttonLoader
        anchors.centerIn: parent
        width: delegateItem.width
        height: delegateItem.height
        sourceComponent: {
            switch (delegateItem.itemData.type) {
            case "separator":
                return null;
            case "launcher":
                return launcherButton;
            case "trash":
                return trashButton;
            case "overflow-toggle":
                return overflowButton;
            default:
                return appButton;
            }
        }
    }

    Component {
        id: overflowButton

        DockOverflowButton {
            options: delegateItem.strip.options
            actualIconSize: delegateItem.strip.iconSize * (delegateItem.strip.options.iconSizePercentage ?? 100) / 100
            overflowCount: delegateItem.itemData.overflowCount || 0
            overflowExpanded: delegateItem.strip.overflowExpanded
            isVertical: delegateItem.strip.isVertical
            onClicked: delegateItem.strip.overflowExpanded = !delegateItem.strip.overflowExpanded
        }
    }

    Component {
        id: launcherButton

        DockLauncherButton {
            options: delegateItem.strip.options
            actualIconSize: delegateItem.strip.iconSize * (delegateItem.strip.options.iconSizePercentage ?? 100) / 100
            dockApps: delegateItem.strip
        }
    }

    Component {
        id: trashButton

        DockTrashButton {
            options: delegateItem.strip.options
            actualIconSize: delegateItem.strip.iconSize * (delegateItem.strip.options.iconSizePercentage ?? 100) / 100
            dockApps: delegateItem.strip
            contextMenu: delegateItem.strip.trashContextMenu
            parentDockScreen: delegateItem.strip.dockScreen
        }
    }

    Component {
        id: appButton

        DockAppButton {
            options: delegateItem.strip.options
            actualIconSize: delegateItem.strip.iconSize * (delegateItem.strip.options.iconSizePercentage ?? 100) / 100
            appData: delegateItem.itemData
            contextMenu: delegateItem.strip.contextMenu
            dockApps: delegateItem.strip
            index: delegateItem.index
            parentDockScreen: delegateItem.strip.dockScreen
            showWindowTitle: delegateItem.itemData?.type === "window" || delegateItem.itemData?.type === "grouped"
            windowTitle: {
                const title = delegateItem.itemData?.toplevel?.title || "(Unnamed)";
                return title.length > 50 ? title.substring(0, 47) + "..." : title;
            }
        }
    }
}
