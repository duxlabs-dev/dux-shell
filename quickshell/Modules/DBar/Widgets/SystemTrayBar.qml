import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.Common
import qs.Modules.DBar
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../OverflowLayout.js" as OverflowLayout

BasePill {
    id: root

    enableBackgroundHover: false
    enableCursor: false

    property var parentWindow: null
    property var widgetData: null
    property string section: "right"
    // A same-named binding inside the overflow grid would resolve to its own property.
    readonly property DPopout overflowPopoutRef: overflowPopout
    property bool isAtBottom: false
    property bool useOverflowPopup: !widgetData?.trayUseInlineExpansion
    property bool useSingleLineOverflowPopup: SettingsData.widgetOption("systemTray", widgetData, "trayPopupSingleLine")
    property bool useAutomaticOverflow: SettingsData.widgetOption("systemTray", widgetData, "trayAutoOverflow")
    property int configuredMaxVisibleItems: SettingsData.widgetOption("systemTray", widgetData, "trayMaxVisibleItems")
    property real configuredIconSpacing: Math.max(0, SettingsData.widgetOption("systemTray", widgetData, "trayIconSpacing"))
    property real sectionAvailablePrimarySize: 0
    readonly property var hiddenTrayIds: TrayMenuManager.envHiddenTrayIds
    readonly property var allTrayItems: TrayMenuManager.filterEnvHidden(SystemTray.items.values)
    function getTrayItemKey(item) {
        return TrayMenuManager.getTrayItemKey(item, root.allTrayItems);
    }

    function resolveOrderIndex(key, orderMap) {
        return TrayMenuManager.resolveOrderIndex(key, orderMap);
    }

    function isTrayIdHidden(key) {
        return SessionData.isHiddenTrayId(key);
    }

    function trayIconSourceFor(trayItem) {
        return TrayMenuManager.iconSourceFor(trayItem);
    }

    function activateInlineTrayItem(trayItem, anchorItem) {
        if (!trayItem)
            return;
        if (!trayItem.onlyMenu) {
            trayItem.activate();
            return;
        }
        if (!trayItem.hasMenu)
            return;
        root.showForTrayItem(trayItem, anchorItem, parentScreen, root.isAtBottom, root.isVerticalOrientation, root.axis);
    }

    Connections {
        target: TrayMenuManager

        function onOpenTrayMenuRequested() {
            const request = TrayMenuManager.claimMenuRequest(root.parentScreen?.name);
            if (!request)
                return;

            const item = TrayMenuManager.findTrayItem(request.itemId);
            if (!item || !item.hasMenu)
                return;

            root.showForTrayItem(item, root, parentScreen, root.isAtBottom, root.isVerticalOrientation, root.axis);
        }
    }

    function openInlineTrayContextMenu(trayItem, areaItem, mouse, anchorItem) {
        if (!trayItem) {
            return;
        }
        if (!trayItem.hasMenu) {
            const gp = areaItem.mapToGlobal(mouse.x, mouse.y);
            root.callContextMenuFallback(trayItem.id, Math.round(gp.x), Math.round(gp.y));
            return;
        }
        root.showForTrayItem(trayItem, anchorItem, parentScreen, root.isAtBottom, root.isVerticalOrientation, root.axis);
    }

    function toggleIconName() {
        const edge = root.axis?.edge;
        if (root.useOverflowPopup)
            return OverflowLayout.expanderIcon(edge, root.menuOpen);

        if (edge === "left" || edge === "right") {
            return root.menuOpen == (root.section !== "right") ? "keyboard_arrow_up" : "keyboard_arrow_down";
        }

        return root.menuOpen != (root.section === "right") ? "keyboard_arrow_left" : "keyboard_arrow_right";
    }

    function callContextMenuFallback(trayItemId, globalX, globalY) {
        TrayMenuManager.callContextMenuFallback(trayItemId, globalX, globalY);
    }

    property int _trayOrderTrigger: 0

    Connections {
        target: SessionData
        function onTrayItemOrderChanged() {
            root._trayOrderTrigger++;
        }
    }

    function sortByPreferredOrder(items, trigger) {
        void trigger;
        return TrayMenuManager.sortByPreferredOrder(items, SessionData.trayItemOrder);
    }

    readonly property var allSortedTrayItems: sortByPreferredOrder(allTrayItems, _trayOrderTrigger)
    readonly property var allSortedTrayItemKeys: allSortedTrayItems.map(item => getTrayItemKey(item))
    readonly property var visibleSortedTrayItems: allSortedTrayItems.filter(item => !root.isTrayIdHidden(root.getTrayItemKey(item)))
    readonly property int automaticVisibleItemLimit: {
        if (!root.useAutomaticOverflow)
            return root.visibleSortedTrayItems.length;

        const explicitLimit = Number(root.configuredMaxVisibleItems || 0);
        if (explicitLimit > 0)
            return Math.max(1, Math.min(root.visibleSortedTrayItems.length, explicitLimit));

        const scale = (typeof CompositorService !== "undefined" && CompositorService.getScreenScale) ? Math.max(1, CompositorService.getScreenScale(root.parentScreen)) : 1;
        const sectionPrimary = root.sectionAvailablePrimarySize > 0 ? root.sectionAvailablePrimarySize : (root.isVerticalOrientation ? (root.parentScreen?.height || 0) : (root.parentScreen?.width || 0));
        const logicalPrimary = sectionPrimary > 0 ? (sectionPrimary / scale) : 640;
        const maxTrayShare = root.isVerticalOrientation ? 0.55 : 0.50;
        const itemSize = Math.max(1, root.trayItemSize + root.configuredIconSpacing);
        const slots = Math.floor((logicalPrimary * maxTrayShare) / itemSize);
        return Math.max(2, Math.min(10, Math.min(root.visibleSortedTrayItems.length, slots)));
    }
    readonly property var mainBarItemsRaw: visibleSortedTrayItems.slice(0, automaticVisibleItemLimit)
    readonly property var mainBarItems: mainBarItemsRaw.map((item, idx) => ({
                key: getTrayItemKey(item),
                item: item
            }))
    readonly property var autoOverflowBarItems: visibleSortedTrayItems.slice(automaticVisibleItemLimit)
    readonly property var manualHiddenBarItems: allSortedTrayItems.filter(item => root.isTrayIdHidden(root.getTrayItemKey(item)))
    readonly property var hiddenBarItemKeys: manualHiddenBarItems.concat(autoOverflowBarItems).map(item => root.getTrayItemKey(item))
    readonly property var hiddenBarItems: allSortedTrayItems.filter(item => hiddenBarItemKeys.indexOf(root.getTrayItemKey(item)) !== -1)
    readonly property string trayIconTintMode: {
        const configuredMode = SettingsData.systemTrayIconTintMode || "none";
        switch (configuredMode) {
        case "monochrome":
        case "primary":
        case "secondary":
            return configuredMode;
        default:
            return "none";
        }
    }
    readonly property bool trayIconTintEnabled: trayIconTintMode !== "none"
    readonly property real trayIconTintSaturationAmount: {
        const raw = SettingsData.systemTrayIconTintSaturation;
        const value = (raw === undefined || raw === null) ? 50 : raw;
        return Math.max(0, Math.min(100, value)) / 100;
    }
    readonly property real trayIconTintStrengthAmount: {
        const raw = SettingsData.systemTrayIconTintStrength;
        const value = (raw === undefined || raw === null) ? 135 : raw;
        return Math.max(0, Math.min(200, value)) / 100;
    }
    readonly property real trayIconSaturation: {
        switch (trayIconTintMode) {
        case "monochrome":
            return -1;
        case "primary":
        case "secondary":
            return -root.trayIconTintSaturationAmount;
        default:
            return 0;
        }
    }
    readonly property real trayIconColorization: {
        switch (trayIconTintMode) {
        case "primary":
        case "secondary":
            return root.trayIconTintStrengthAmount;
        default:
            return 0;
        }
    }
    readonly property color trayIconTintColor: {
        switch (trayIconTintMode) {
        case "primary":
            return Theme.primary;
        case "secondary":
            return Theme.secondary;
        default:
            return Theme.surfaceText;
        }
    }

    readonly property bool reverseInlineHorizontal: !useOverflowPopup && !isVerticalOrientation && section === "right"
    readonly property bool reverseInlineVertical: !useOverflowPopup && isVerticalOrientation && section === "right"
    readonly property var displayedMainBarItems: reverseInlineHorizontal ? [...mainBarItems].reverse() : mainBarItems
    readonly property var displayedInlineExpandedItems: (reverseInlineHorizontal ? [...hiddenBarItems].reverse() : hiddenBarItems).map(item => ({
                key: getTrayItemKey(item),
                item: item
            }))

    function moveTrayItemInFullOrder(visibleFromIndex, visibleToIndex) {
        if (visibleFromIndex === visibleToIndex || visibleFromIndex < 0 || visibleToIndex < 0)
            return;

        const fromKey = mainBarItems[visibleFromIndex]?.key ?? null;
        const toKey = mainBarItems[visibleToIndex]?.key ?? null;
        moveTrayItemKeyInFullOrder(fromKey, toKey);
    }

    function moveTrayItemKeyInFullOrder(fromKey, toKey) {
        const nextOrder = TrayMenuManager.reorderItemKeys(allSortedTrayItemKeys, fromKey, toKey);
        if (nextOrder)
            SessionData.setTrayItemOrder(nextOrder);
    }

    function promoteTrayItemToBar(item) {
        const itemKey = getTrayItemKey(item);
        if (!itemKey)
            return;
        if (SessionData.isHiddenTrayId(itemKey)) {
            SessionData.showTrayId(itemKey);
            return;
        }

        const fullOrder = [...allSortedTrayItemKeys];
        const fromIndex = fullOrder.indexOf(itemKey);
        if (fromIndex < 0)
            return;
        const movedKey = fullOrder.splice(fromIndex, 1)[0];
        const targetIndex = Math.max(0, Math.min(root.automaticVisibleItemLimit - 1, fullOrder.length));
        fullOrder.splice(targetIndex, 0, movedKey);
        SessionData.setTrayItemOrder(fullOrder);
    }

    function isManualHiddenTrayItem(item) {
        return root.isTrayIdHidden(root.getTrayItemKey(item));
    }

    function isAutoOverflowTrayItem(item) {
        const key = getTrayItemKey(item);
        return key && !isManualHiddenTrayItem(item) && root.autoOverflowBarItems.some(overflowItem => getTrayItemKey(overflowItem) === key);
    }

    function dragShiftOffset(index, draggedIndex, dropTargetIndex, shiftAmount) {
        return TrayMenuManager.dragShiftOffset(index, draggedIndex, dropTargetIndex, shiftAmount);
    }

    function beginMainDrag(visualIndex, reversed) {
        root.draggedIndex = reversed ? (root.mainBarItems.length - 1 - visualIndex) : visualIndex;
        root.dropTargetIndex = root.draggedIndex;
    }

    function updateMainDrag(axisOffset, visualIndex, reversed) {
        const itemSize = root.trayItemSize + root.configuredIconSpacing;
        const slotOffset = Math.round(axisOffset / itemSize);
        const visualTargetIndex = Math.max(0, Math.min(root.mainBarItems.length - 1, visualIndex + slotOffset));
        const newTargetIndex = reversed ? (root.mainBarItems.length - 1 - visualTargetIndex) : visualTargetIndex;
        if (newTargetIndex !== root.dropTargetIndex)
            root.dropTargetIndex = newTargetIndex;
    }

    function finishMainDrag() {
        const didReorder = root.dropTargetIndex >= 0 && root.dropTargetIndex !== root.draggedIndex;
        if (didReorder) {
            root.suppressShiftAnimation = true;
            root.moveTrayItemInFullOrder(root.draggedIndex, root.dropTargetIndex);
            Qt.callLater(() => root.suppressShiftAnimation = false);
        }
        root.draggedIndex = -1;
        root.dropTargetIndex = -1;
        return didReorder;
    }

    function beginPopupDrag(index) {
        root.popupDraggedIndex = index;
        root.popupDropTargetIndex = index;
    }

    function updatePopupDrag(axisOffset, index) {
        const itemSize = root.trayItemSize + 6;
        const slotOffset = Math.round(axisOffset / itemSize);
        const newTargetIndex = Math.max(0, Math.min(root.hiddenBarItems.length - 1, index + slotOffset));
        if (newTargetIndex !== root.popupDropTargetIndex)
            root.popupDropTargetIndex = newTargetIndex;
    }

    function finishPopupDrag() {
        const didReorder = root.popupDropTargetIndex >= 0 && root.popupDropTargetIndex !== root.popupDraggedIndex;
        if (didReorder) {
            const fromItem = root.hiddenBarItems[root.popupDraggedIndex];
            const toItem = root.hiddenBarItems[root.popupDropTargetIndex];
            root.suppressShiftAnimation = true;
            root.moveTrayItemKeyInFullOrder(root.getTrayItemKey(fromItem), root.getTrayItemKey(toItem));
            Qt.callLater(() => root.suppressShiftAnimation = false);
        }
        root.popupDraggedIndex = -1;
        root.popupDropTargetIndex = -1;
        return didReorder;
    }

    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property int popupDraggedIndex: -1
    property int popupDropTargetIndex: -1
    property bool suppressShiftAnimation: false
    readonly property bool hasHiddenItems: hiddenBarItems.length > 0
    readonly property bool inlineExpanded: hasHiddenItems && !useOverflowPopup && menuOpen
    visible: allTrayItems.length > 0
    opacity: allTrayItems.length > 0 ? 1 : 0

    states: [
        State {
            name: "hidden_horizontal"
            when: allTrayItems.length === 0 && !isVerticalOrientation
            PropertyChanges {
                target: root
                width: 0
            }
        },
        State {
            name: "hidden_vertical"
            when: allTrayItems.length === 0 && isVerticalOrientation
            PropertyChanges {
                target: root
                height: 0
            }
        }
    ]

    transitions: [
        Transition {
            NumberAnimation {
                properties: "width,height"
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }
    ]

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    readonly property real trayIconSize: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
    readonly property real trayItemSize: trayIconSize + Theme.spacingXS + Theme.spacingXXS

    readonly property string autoBarShadowDirection: {
        const edge = root.axis?.edge;
        switch (edge) {
        case "top":
            return "top";
        case "bottom":
            return "bottom";
        case "left":
            return "left";
        case "right":
            return "right";
        default:
            return "bottom";
        }
    }
    readonly property string effectiveShadowDirection: Theme.elevationLightDirection === "autoBar" ? autoBarShadowDirection : Theme.elevationLightDirection

    property bool menuOpen: false

    function _openOverflowAt(triggerItem) {
        if (!triggerItem || !root.parentScreen)
            return;
        if (!root.positionPopout(overflowPopout, triggerItem, root.isVerticalOrientation ? triggerItem.height : triggerItem.width))
            return;
        root.menuOpen = true;
        PopoutManager.requestPopout(overflowPopout, undefined, "tray-overflow-" + root.section);
    }

    readonly property real overflowRawWidth: {
        const itemCount = root.hiddenBarItems.length;
        if (itemCount === 0)
            return 0;
        const popupUsesVerticalLine = root.useSingleLineOverflowPopup && root.isVerticalOrientation;
        const popupPadding = Theme.spacingS + (popupUsesVerticalLine ? 3 : 0);
        if (popupUsesVerticalLine)
            return root.trayItemSize + 4 + popupPadding * 2;
        const cols = root.useSingleLineOverflowPopup ? itemCount : Math.min(5, itemCount);
        const itemSize = root.trayItemSize + 4;
        const spacing = 2;
        const desiredWidth = cols * itemSize + (cols - 1) * spacing + popupPadding * 2;
        if (!root.useSingleLineOverflowPopup)
            return desiredWidth;
        const maxWidth = Math.max(itemSize + popupPadding * 2, (root.parentScreen?.width || 1920) - 20);
        return Math.min(desiredWidth, maxWidth);
    }

    readonly property real overflowRawHeight: {
        const itemCount = root.hiddenBarItems.length;
        if (itemCount === 0)
            return 0;
        const popupUsesVerticalLine = root.useSingleLineOverflowPopup && root.isVerticalOrientation;
        const popupPadding = Theme.spacingS + (popupUsesVerticalLine ? 3 : 0);
        const itemSize = root.trayItemSize + 4;
        const spacing = 2;
        if (popupUsesVerticalLine) {
            const desiredHeight = itemCount * itemSize + (itemCount - 1) * spacing + popupPadding * 2;
            const maxHeight = Math.max(itemSize + popupPadding * 2, (root.parentScreen?.height || 1080) - 20);
            return Math.min(desiredHeight, maxHeight);
        }
        const cols = root.useSingleLineOverflowPopup ? itemCount : Math.min(5, itemCount);
        const rows = Math.ceil(itemCount / cols);
        return rows * itemSize + (rows - 1) * spacing + popupPadding * 2;
    }

    DPopout {
        id: overflowPopout
        layerNamespace: "dms:tray-overflow"
        screen: root.parentScreen
        popupWidth: root.overflowRawWidth
        popupHeight: root.overflowRawHeight
        content: overflowContentComponent
    }

    DPopout {
        id: trayMenuPopout
        layerNamespace: "dms:tray-menu"
        screen: root.parentScreen
        popupWidth: trayMenuState.computedWidth
        popupHeight: trayMenuState.computedHeight
        content: trayMenuContentComponent
        contentHandlesKeys: true
        property alias openedByHover: trayMenuState.openedByHover
        onOpened: {
            contentLoader.item?.entryStack?.clear();
            contentLoader.item?.forceActiveFocus();
        }
    }

    Connections {
        target: overflowPopout
        function onBackgroundClicked() {
            root.menuOpen = false;
        }
        function onPopoutClosed() {
            root.menuOpen = false;
        }
    }

    function _unregisterMenuIfMatches(targetMenu) {
        if (!root.parentScreen || !targetMenu)
            return;
        const currentRegistered = TrayMenuManager.activeTrayMenus[root.parentScreen.name];
        if (currentRegistered === targetMenu) {
            TrayMenuManager.unregisterMenu(root.parentScreen.name);
        }
    }

    onMenuOpenChanged: {
        if (!root.useOverflowPopup || !root.parentScreen)
            return;
        if (root.menuOpen) {
            trayMenuState.close();
            TrayMenuManager.registerMenu(root.parentScreen.name, overflowPopout);
        } else {
            root._unregisterMenuIfMatches(overflowPopout);
            overflowPopout.close();
        }
    }

    content: Component {
        Item {
            implicitWidth: layoutLoader.item ? layoutLoader.item.implicitWidth : 0
            implicitHeight: layoutLoader.item ? layoutLoader.item.implicitHeight : 0

            Loader {
                id: layoutLoader
                anchors.centerIn: parent
                sourceComponent: root.isVerticalOrientation ? columnComp : rowComp
            }
        }
    }

    Component {
        id: rowComp
        Row {
            spacing: root.configuredIconSpacing
            layoutDirection: root.reverseInlineHorizontal ? Qt.RightToLeft : Qt.LeftToRight

            Repeater {
                model: ScriptModel {
                    values: root.displayedMainBarItems
                    objectProp: "key"
                }

                delegate: mainTrayItemDelegate
            }

            Item {
                width: root.trayItemSize
                height: root.barThickness
                visible: root.hasHiddenItems

                BarPillSurface {
                    id: caretButton
                    width: root.trayItemSize
                    height: root.trayItemSize
                    anchors.centerIn: parent
                    style: BarMetrics.widgetStyle(root.barConfig)
                    pressed: caretArea.pressed
                    color: Theme.withAlpha(Theme.onSurface, caretArea.pressed ? Theme.stateLayerPressed : caretArea.containsMouse ? Theme.stateLayerHover : 0)

                    DIcon {
                        anchors.centerIn: parent
                        name: root.toggleIconName()
                        size: root.trayIconSize
                        color: Theme.widgetTextColor
                    }

                    DRipple {
                        id: caretRipple
                        cornerRadius: caretButton.radius
                    }

                    MouseArea {
                        id: caretArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            caretRipple.trigger(mouse.x, mouse.y);
                        }
                        onClicked: {
                            if (root.useOverflowPopup) {
                                if (!root.menuOpen) {
                                    root._openOverflowAt(caretButton);
                                } else {
                                    root.menuOpen = false;
                                }
                            } else {
                                root.menuOpen = !root.menuOpen;
                            }
                        }
                    }
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.displayedInlineExpandedItems
                    objectProp: "key"
                }

                delegate: inlineExpandedTrayItemDelegate
            }
        }
    }

    Component {
        id: inlineExpandedTrayItemDelegate

        Item {
            property var trayItem: modelData.item
            property string itemKey: modelData.key
            property string iconSource: root.trayIconSourceFor(trayItem)

            width: root.isVerticalOrientation ? root.barThickness : (root.inlineExpanded ? root.trayItemSize : 0)
            height: root.isVerticalOrientation ? (root.inlineExpanded ? root.trayItemSize : 0) : root.barThickness
            visible: width > 0 && height > 0

            Behavior on width {
                enabled: !root.isVerticalOrientation
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }

            Behavior on height {
                enabled: root.isVerticalOrientation
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }

            BarPillSurface {
                id: inlineVisualContent
                width: root.trayItemSize
                height: root.trayItemSize
                x: root.isVerticalOrientation ? Math.round((parent.width - width) / 2) : (root.reverseInlineHorizontal ? parent.width - width : 0)
                y: root.isVerticalOrientation ? (root.reverseInlineVertical ? parent.height - height : 0) : Math.round((parent.height - height) / 2)
                style: BarMetrics.widgetStyle(root.barConfig)
                pressed: inlineTrayItemArea.pressed
                color: Theme.withAlpha(Theme.onSurface, inlineTrayItemArea.pressed ? Theme.stateLayerPressed : inlineTrayItemArea.containsMouse ? Theme.stateLayerHover : 0)
                opacity: root.inlineExpanded ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }

                TrayItemIcon {
                    anchors.fill: parent
                    tray: root
                    trayItem: trayItem
                    source: iconSource
                }

                DRipple {
                    id: inlineItemRipple
                    cornerRadius: inlineVisualContent.radius
                }
            }

            MouseArea {
                id: inlineTrayItemArea
                y: root.isVerticalOrientation ? 0 : -root.topMargin
                x: root.isVerticalOrientation ? -root.leftMargin : 0
                width: parent.width + (root.isVerticalOrientation ? root.leftMargin + root.rightMargin : 0)
                height: parent.height + (root.isVerticalOrientation ? 0 : root.topMargin + root.bottomMargin)
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                enabled: root.inlineExpanded

                onPressed: mouse => {
                    const pos = mapToItem(inlineVisualContent, mouse.x, mouse.y);
                    inlineItemRipple.trigger(pos.x, pos.y);
                }

                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        root.activateInlineTrayItem(trayItem, inlineVisualContent);
                        return;
                    }
                    if (mouse.button !== Qt.RightButton)
                        return;
                    root.openInlineTrayContextMenu(trayItem, inlineTrayItemArea, mouse, inlineVisualContent);
                }
            }
        }
    }

    Component {
        id: mainTrayItemDelegate

        Item {
            id: delegateRoot
            property var trayItem: modelData.item
            property string itemKey: modelData.key
            property string iconSource: root.trayIconSourceFor(trayItem)

            width: root.isVerticalOrientation ? root.barThickness : root.trayItemSize
            height: root.isVerticalOrientation ? root.trayItemSize : root.barThickness
            z: dragHandler.dragging ? 100 : 0

            property real shiftOffset: root.dragShiftOffset(index, root.draggedIndex, root.dropTargetIndex, root.trayItemSize + root.configuredIconSpacing)

            transform: Translate {
                x: root.isVerticalOrientation ? 0 : delegateRoot.shiftOffset
                y: root.isVerticalOrientation ? delegateRoot.shiftOffset : 0
                Behavior on x {
                    enabled: !root.suppressShiftAnimation
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    enabled: !root.suppressShiftAnimation
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Item {
                id: dragHandler
                anchors.fill: parent
                property bool dragging: false
                property point dragStartPos: Qt.point(0, 0)
                property real dragAxisOffset: 0
                property bool longPressing: false

                Timer {
                    id: longPressTimer
                    interval: 400
                    repeat: false
                    onTriggered: dragHandler.longPressing = true
                }
            }

            readonly property int groupCount: root.displayedMainBarItems.length
            readonly property bool reversedRow: !root.isVerticalOrientation && root.reverseInlineHorizontal
            readonly property bool atStart: reversedRow ? index === groupCount - 1 : index === 0
            readonly property bool atEnd: reversedRow ? index === 0 : index === groupCount - 1
            BarPillSurface {
                id: visualContent
                width: root.trayItemSize
                height: root.trayItemSize
                anchors.centerIn: parent
                style: BarMetrics.widgetStyle(root.barConfig)
                vertical: root.isVerticalOrientation
                joinedStart: style === "segments" && !delegateRoot.atStart
                joinedEnd: style === "segments" && !delegateRoot.atEnd
                pressed: trayItemArea.pressed
                color: Theme.withAlpha(Theme.onSurface, trayItemArea.pressed ? Theme.stateLayerPressed : trayItemArea.containsMouse ? Theme.stateLayerHover : 0)
                border.width: dragHandler.dragging ? Theme.outlineWidthFocused : 0
                border.color: Theme.primary
                opacity: dragHandler.dragging ? 0.8 : 1.0

                transform: Translate {
                    x: dragHandler.dragging && !root.isVerticalOrientation ? dragHandler.dragAxisOffset : 0
                    y: dragHandler.dragging && root.isVerticalOrientation ? dragHandler.dragAxisOffset : 0
                }

                TrayItemIcon {
                    anchors.fill: parent
                    tray: root
                    trayItem: delegateRoot.trayItem
                    source: delegateRoot.iconSource
                }

                DRipple {
                    id: itemRipple
                    topLeftRadius: visualContent.topLeftRadius
                    topRightRadius: visualContent.topRightRadius
                    bottomLeftRadius: visualContent.bottomLeftRadius
                    bottomRightRadius: visualContent.bottomRightRadius
                }
            }

            MouseArea {
                id: trayItemArea
                y: root.isVerticalOrientation ? 0 : -root.topMargin
                x: root.isVerticalOrientation ? -root.leftMargin : 0
                width: parent.width + (root.isVerticalOrientation ? root.leftMargin + root.rightMargin : 0)
                height: parent.height + (root.isVerticalOrientation ? 0 : root.topMargin + root.bottomMargin)
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: dragHandler.longPressing ? Qt.DragMoveCursor : Qt.PointingHandCursor

                onPressed: mouse => {
                    const pos = mapToItem(visualContent, mouse.x, mouse.y);
                    itemRipple.trigger(pos.x, pos.y);
                    if (mouse.button === Qt.LeftButton) {
                        dragHandler.dragStartPos = Qt.point(mouse.x, mouse.y);
                        longPressTimer.start();
                    }
                }

                onReleased: mouse => {
                    longPressTimer.stop();
                    const wasDragging = dragHandler.dragging;
                    if (wasDragging)
                        root.finishMainDrag();

                    dragHandler.longPressing = false;
                    dragHandler.dragging = false;
                    dragHandler.dragAxisOffset = 0;

                    if (wasDragging || mouse.button !== Qt.LeftButton)
                        return;

                    if (!delegateRoot.trayItem)
                        return;
                    if (!delegateRoot.trayItem.onlyMenu) {
                        delegateRoot.trayItem.activate();
                        return;
                    }
                    if (!delegateRoot.trayItem.hasMenu)
                        return;
                    if (root.useOverflowPopup)
                        root.menuOpen = false;
                    root.showForTrayItem(delegateRoot.trayItem, visualContent, parentScreen, root.isAtBottom, root.isVerticalOrientation, root.axis);
                }

                onPositionChanged: mouse => {
                    const axisOffset = root.isVerticalOrientation ? (mouse.y - dragHandler.dragStartPos.y) : (mouse.x - dragHandler.dragStartPos.x);
                    if (dragHandler.longPressing && !dragHandler.dragging && Math.abs(axisOffset) > 5) {
                        dragHandler.dragging = true;
                        root.beginMainDrag(index, root.reverseInlineHorizontal);
                    }
                    if (!dragHandler.dragging)
                        return;

                    dragHandler.dragAxisOffset = axisOffset;
                    root.updateMainDrag(axisOffset, index, root.reverseInlineHorizontal);
                }

                onClicked: mouse => {
                    if (dragHandler.dragging)
                        return;
                    if (mouse.button !== Qt.RightButton)
                        return;
                    if (!delegateRoot.trayItem?.hasMenu) {
                        const gp = trayItemArea.mapToGlobal(mouse.x, mouse.y);
                        root.callContextMenuFallback(delegateRoot.trayItem.id, Math.round(gp.x), Math.round(gp.y));
                        return;
                    }
                    if (root.useOverflowPopup)
                        root.menuOpen = false;
                    root.showForTrayItem(delegateRoot.trayItem, visualContent, parentScreen, root.isAtBottom, root.isVerticalOrientation, root.axis);
                }
            }
        }
    }

    Component {
        id: columnComp
        Column {
            spacing: root.configuredIconSpacing

            // Column lacks layoutDirection, so we use four repeaters with mutually exclusive models to control whether main items or expanded items appear above/ below the toggle button.
            // When reverseInlineVertical is true the first and third repeaters are empty and the second and fourth are active, and vice-versa.
            // Because items are swapped between repeaters rather than reversed within a single list, vertical drag-and-drop indices don't need remapping (unlike the horizontal RightToLeft case).
            Repeater {
                model: ScriptModel {
                    values: root.reverseInlineVertical ? [] : root.displayedMainBarItems
                    objectProp: "key"
                }
                delegate: mainTrayItemDelegate
            }

            Repeater {
                model: ScriptModel {
                    values: root.reverseInlineVertical ? root.displayedInlineExpandedItems : []
                    objectProp: "key"
                }
                delegate: inlineExpandedTrayItemDelegate
            }

            Item {
                width: root.barThickness
                height: root.trayItemSize
                visible: root.hasHiddenItems

                BarPillSurface {
                    id: caretButtonVert
                    width: root.trayItemSize
                    height: root.trayItemSize
                    anchors.centerIn: parent
                    style: BarMetrics.widgetStyle(root.barConfig)
                    pressed: caretAreaVert.pressed
                    color: Theme.withAlpha(Theme.onSurface, caretAreaVert.pressed ? Theme.stateLayerPressed : caretAreaVert.containsMouse ? Theme.stateLayerHover : 0)

                    DIcon {
                        anchors.centerIn: parent
                        name: root.toggleIconName()
                        size: root.trayIconSize
                        color: Theme.widgetTextColor
                    }

                    DRipple {
                        id: caretRippleVert
                        cornerRadius: caretButtonVert.radius
                    }

                    MouseArea {
                        id: caretAreaVert
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            caretRippleVert.trigger(mouse.x, mouse.y);
                        }
                        onClicked: {
                            if (root.useOverflowPopup) {
                                if (!root.menuOpen) {
                                    root._openOverflowAt(caretButtonVert);
                                } else {
                                    root.menuOpen = false;
                                }
                            } else {
                                root.menuOpen = !root.menuOpen;
                            }
                        }
                    }
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.reverseInlineVertical ? [] : root.displayedInlineExpandedItems
                    objectProp: "key"
                }
                delegate: inlineExpandedTrayItemDelegate
            }

            Repeater {
                model: ScriptModel {
                    values: root.reverseInlineVertical ? root.displayedMainBarItems : []
                    objectProp: "key"
                }
                delegate: mainTrayItemDelegate
            }
        }
    }

    // Overflow grid content rendered inside DPopout
    Component {
        id: overflowContentComponent

        Item {
            id: overflowContent
            objectName: "overflowMenuContainer"

            readonly property bool popupUsesVerticalLine: root.useSingleLineOverflowPopup && root.isVerticalOrientation
            readonly property real popupPadding: Theme.spacingS + (popupUsesVerticalLine ? 3 : 0)

            implicitWidth: root.overflowRawWidth
            implicitHeight: root.overflowRawHeight

            Flickable {
                anchors.centerIn: parent
                width: parent.width - overflowContent.popupPadding * 2
                height: parent.height - overflowContent.popupPadding * 2
                contentWidth: menuGrid.implicitWidth
                contentHeight: menuGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                interactive: root.useSingleLineOverflowPopup && (overflowContent.popupUsesVerticalLine ? contentHeight > height : contentWidth > width)

                TrayOverflowGrid {
                    id: menuGrid
                    bar: root
                    overflowPopout: root.overflowPopoutRef
                    popupUsesVerticalLine: overflowContent.popupUsesVerticalLine
                    anchors.verticalCenter: overflowContent.popupUsesVerticalLine ? undefined : parent.verticalCenter
                    anchors.horizontalCenter: overflowContent.popupUsesVerticalLine ? parent.horizontalCenter : undefined
                }
            }
        }
    }

    QtObject {
        id: trayMenuState
        property var trayItem: null
        property bool showMenu: false
        property var menuHandle: null
        property bool openedByHover: false
        property real computedWidth: 280
        property real computedHeight: 200

        function close() {
            showMenu = false;
            root._unregisterMenuIfMatches(trayMenuPopout);
            trayMenuPopout.close();
        }
    }

    Binding {
        target: trayMenuPopout
        property: "popupWidth"
        value: trayMenuState.computedWidth
    }
    Binding {
        target: trayMenuPopout
        property: "popupHeight"
        value: trayMenuState.computedHeight
    }

    Connections {
        target: trayMenuPopout
        function onBackgroundClicked() {
            trayMenuState.close();
        }
        function onPopoutClosed() {
            trayMenuState.showMenu = false;
            root._unregisterMenuIfMatches(trayMenuPopout);
        }
    }

    Timer {
        id: pendingActionCloseTimer
        interval: 80
        repeat: false
        onTriggered: trayMenuState.close()
    }

    Component {
        id: trayMenuContentComponent

        Item {
            id: trayMenuContentRoot
            focus: true
            property alias entryStack: trayContent.entryStack

            readonly property real _rawW: Math.min(Theme.launcherWidthMicro, Math.max(Theme.fieldDefaultWidth, trayContent.implicitWidth + BarMetrics.menuPadding * 2))
            readonly property real _rawH: Math.min(Math.max(BarMetrics.menuRowHeight, trayContent.implicitHeight + BarMetrics.menuPadding * 2), Math.max(BarMetrics.menuRowHeight, (root.parentScreen?.height || Theme.launcherHeightDefault) - Theme.spacingXL))

            implicitWidth: _rawW
            implicitHeight: _rawH

            onImplicitWidthChanged: trayMenuState.computedWidth = implicitWidth
            onImplicitHeightChanged: trayMenuState.computedHeight = implicitHeight
            Component.onCompleted: {
                trayMenuState.computedWidth = implicitWidth;
                trayMenuState.computedHeight = implicitHeight;
                trayContent.forceActiveFocus();
            }

            Keys.forwardTo: [trayContent]

            DFlickable {
                id: menuFlickable
                anchors.fill: parent
                anchors.margins: BarMetrics.menuPadding
                contentWidth: width
                contentHeight: trayContent.implicitHeight
                clip: true
                interactive: contentHeight > height

                TrayMenuContent {
                    id: trayContent
                    width: menuFlickable.width
                    trayItem: trayMenuState.trayItem
                    menuHandle: trayMenuState.menuHandle
                    anchorWindow: trayMenuPopout.contentWindow
                    bar: root
                    onCloseRequested: trayMenuState.close()
                    onActionTriggered: pendingActionCloseTimer.restart()
                }
            }
        }
    }

    function showForTrayItemAtGlobalPoint(item, gx, gy, triggerWidth, screen, atBottom, vertical, axisObj, byHover) {
        if (!screen)
            return;

        trayMenuState.close();

        const barPosition = (axisObj?.edge === "left") ? 2 : ((axisObj?.edge === "right") ? 3 : ((axisObj?.edge === "top") ? 0 : 1));
        const localPos = Qt.point(gx - (screen.x || 0), gy - (screen.y || 0));
        const tw = triggerWidth || root.width;
        const pos = SettingsData.getPopupTriggerPosition(localPos, screen, root.barThickness, tw, root.barSpacing, barPosition, root.barConfig);

        const registration = BarWidgetService.registrationForItem(root);
        if (registration?.context?.owner?.overflowAnchor)
            registration.context.surface.positionPopout(trayMenuPopout, root, root.section);
        else
            trayMenuPopout.setTriggerPosition(pos.x, pos.y, pos.width, root.section, screen, barPosition, root.barThickness, root.barSpacing, root.barConfig);

        trayMenuState.trayItem = item;
        trayMenuState.menuHandle = item?.menu ?? null;
        trayMenuState.openedByHover = byHover === true;

        PopoutManager.closeAllPopouts();
        ModalManager.closeAllModalsExcept(null);
        if (root.useOverflowPopup)
            root.menuOpen = false;

        if (screen)
            TrayMenuManager.registerMenu(screen.name, trayMenuPopout);

        trayMenuState.showMenu = true;
        PopoutManager.requestPopout(trayMenuPopout, undefined, "tray-menu-" + (item?.id ?? ""));
    }

    function showForTrayItem(item, anchor, screen, atBottom, vertical, axisObj, byHover) {
        if (!screen)
            return;

        const anchorY = (vertical && anchor) ? (anchor.height / 2 + root.minTooltipY) : 0;
        const globalPos = anchor ? anchor.mapToGlobal(0, anchorY) : Qt.point(0, 0);
        const triggerWidth = anchor ? anchor.width : root.width;
        showForTrayItemAtGlobalPoint(item, globalPos.x, globalPos.y, triggerWidth, screen, atBottom, vertical, axisObj, byHover);
    }

    function _trayLayoutRoot() {
        const contentChildren = root.visualContent?.children;
        if (!contentChildren || contentChildren.length === 0)
            return null;
        const contentRoot = contentChildren[0];
        return contentRoot?.layoutLoader?.item || null;
    }

    function _trayHitAtGlobalPoint(gx, gy) {
        if (!root.visible || root.width <= 0 || root.height <= 0)
            return null;
        const local = root.mapFromItem(null, gx, gy);
        if (local.x < 0 || local.y < 0 || local.x > root.width || local.y > root.height)
            return null;
        const layout = _trayLayoutRoot();
        if (!layout)
            return null;
        const layoutLocal = layout.mapFromItem(null, gx, gy);
        const children = layout.children || [];
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (!child.visible || child.width <= 0 || child.height <= 0)
                continue;
            if (layoutLocal.x < child.x || layoutLocal.x >= child.x + child.width)
                continue;
            if (layoutLocal.y < child.y || layoutLocal.y >= child.y + child.height)
                continue;
            if (child.trayItem)
                return child;
        }
        return null;
    }

    function hoverTriggerAtGlobalPoint(gx, gy) {
        const hit = _trayHitAtGlobalPoint(gx, gy);
        if (!hit?.trayItem?.hasMenu)
            return "";
        return "tray-" + (hit.trayItem.id || hit.itemKey || "");
    }

    function openHoverAtGlobalPoint(gx, gy) {
        const hit = _trayHitAtGlobalPoint(gx, gy);
        if (!hit?.trayItem?.hasMenu)
            return false;
        const anchor = hit.children?.length > 0 ? hit.children[0] : hit;
        showForTrayItem(hit.trayItem, anchor, parentScreen, isAtBottom, isVerticalOrientation, axis, true);
        return true;
    }
}
