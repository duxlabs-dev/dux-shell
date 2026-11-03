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
    property var dockButton: {
        switch (itemData.type) {
        case "launcher":
            return launcherButton;
        case "trash":
            return trashButton;
        case "overflow-toggle":
            return overflowButton;
        default:
            return button;
        }
    }
    property var itemData: modelData
    readonly property bool isOverflowToggle: itemData.type === "overflow-toggle"
    readonly property bool isTrash: itemData.type === "trash"
    readonly property bool isInOverflow: itemData.isInOverflow === true
    readonly property bool isDragging: button.dragging

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
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
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

    readonly property var shiftSpringParams: Theme.springPreset("fast", 150)

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

    DockOverflowButton {
        id: overflowButton
        options: strip.options
        visible: isOverflowToggle
        anchors.centerIn: parent
        width: delegateItem.width
        height: delegateItem.height
        actualIconSize: strip.iconSize * (strip.options.iconSizePercentage ?? 100) / 100
        overflowCount: itemData.overflowCount || 0
        overflowExpanded: strip.overflowExpanded
        isVertical: strip.isVertical
        onClicked: strip.overflowExpanded = !strip.overflowExpanded
    }

    DockLauncherButton {
        id: launcherButton
        options: strip.options
        visible: itemData.type === "launcher"
        anchors.centerIn: parent
        width: delegateItem.width
        height: delegateItem.height
        actualIconSize: strip.iconSize * (strip.options.iconSizePercentage ?? 100) / 100
        dockApps: strip
    }

    DockTrashButton {
        id: trashButton
        options: strip.options
        visible: itemData.type === "trash"
        anchors.centerIn: parent
        width: delegateItem.width
        height: delegateItem.height
        actualIconSize: strip.iconSize * (strip.options.iconSizePercentage ?? 100) / 100
        dockApps: strip
        contextMenu: strip.trashContextMenu
        parentDockScreen: strip.dockScreen
    }

    DockAppButton {
        id: button
        options: strip.options
        visible: !isOverflowToggle && itemData.type !== "separator" && itemData.type !== "launcher" && itemData.type !== "trash"
        anchors.centerIn: parent
        width: delegateItem.width
        height: delegateItem.height
        actualIconSize: strip.iconSize * (strip.options.iconSizePercentage ?? 100) / 100
        appData: itemData
        contextMenu: strip.contextMenu
        dockApps: strip
        index: delegateItem.index
        parentDockScreen: strip.dockScreen
        showWindowTitle: itemData?.type === "window" || itemData?.type === "grouped"
        windowTitle: {
            const title = itemData?.toplevel?.title || "(Unnamed)";
            return title.length > 50 ? title.substring(0, 47) + "..." : title;
        }
    }
}
