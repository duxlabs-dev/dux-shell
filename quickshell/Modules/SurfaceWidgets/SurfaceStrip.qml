pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import "../../Common/settings/DockConfig.js" as DockConfig

FocusScope {
    id: root
    required property var surfaceContext
    required property var components
    property var model: []
    property var applicationStrip: null
    readonly property real crossOverflow: surfaceContext.host?.stripOverflow ?? 0
    property real availableSize: width
    property real spacing: Theme.spacingXS
    property bool fillAvailable: false
    property string align: "start"
    property int layoutRevision: 0
    property int draggingIndex: -1
    property int targetIndex: -1
    property string draggingUnit: ""
    property string targetUnit: ""
    property real dragOffset: 0
    readonly property bool dragActive: draggingIndex >= 0 || draggingUnit !== ""
    readonly property var sourceOrder: model.map((item, index) => index)
    readonly property var visualOrder: {
        if (draggingUnit !== "")
            return DockConfig.unitOrder(model, draggingUnit, targetUnit);
        if (draggingIndex >= 0)
            return DockConfig.move(sourceOrder, draggingIndex, targetIndex);
        return sourceOrder;
    }
    readonly property var positions: layoutPositions(sourceOrder)
    readonly property var restPositions: layoutPositions(visualOrder)
    readonly property var unalignedPositions: layoutPositions(visualOrder, undefined, 0)
    readonly property var previewPositions: magnificationExpand ? layoutPositions(visualOrder, magnificationScales) : restPositions
    readonly property var unitIds: DockConfig.units(model)
    readonly property var unitSpans: {
        const spans = [];
        model.forEach((item, index) => {
            if (!participating[index])
                return;
            const id = DockConfig.unitOf(item);
            const start = positionAt(index);
            const end = start + allocatedSizes[index];
            const last = spans[spans.length - 1];
            if (last?.id === id)
                last.end = end;
            else
                spans.push({
                    id,
                    start,
                    end
                });
        });
        return spans;
    }

    // `scales` widens each slot's footprint so magnified neighbours are pushed apart instead of overlapping.
    function layoutPositions(order, scales, startOffset) {
        const result = [];
        let offset = startOffset ?? alignOffset;
        for (const index of order) {
            const scale = scales?.[index] ?? 1.0;
            const extra = scales ? (scale - 1.0) * allocatedSizes[index] * expansionRatio : 0;
            result[index] = offset + extra / 2;
            if (participating[index])
                offset += allocatedSizes[index] + extra + spacing;
        }
        return result;
    }

    function cancelDrag() {
        draggingIndex = -1;
        targetIndex = -1;
        draggingUnit = "";
        targetUnit = "";
        dragOffset = 0;
    }

    function unitTarget(id, offset) {
        return DockConfig.unitTarget(unitSpans, id, offset);
    }

    function clampedUnitOffset(id, offset) {
        const span = unitSpans.find(span => span.id === id);
        if (!span)
            return offset;
        return Math.max(alignOffset - span.start, Math.min(alignOffset + contentLength - span.end, offset));
    }

    function unitBounds(id) {
        layoutRevision;
        let start = Infinity;
        let end = -Infinity;
        for (let i = 0; i < repeater.count; i++) {
            const slot = repeater.itemAt(i);
            if (!slot || slot.unitId !== id || !participating[i])
                continue;
            start = Math.min(start, vertical ? slot.y : slot.x);
            end = Math.max(end, vertical ? slot.y + slot.height : slot.x + slot.width);
        }
        if (start > end)
            return Qt.rect(0, 0, 0, 0);
        return vertical ? Qt.rect(crossOverflow, start, width, end - start) : Qt.rect(start, crossOverflow, end - start, height);
    }

    // ScriptModel moves delegates on reorder, so the cached sizes must be re-read in the new order.
    onModelChanged: {
        cancelDrag();
        updateLayout.schedule();
    }
    onVisibleChanged: if (!visible)
        cancelDrag()
    readonly property bool contextEditMode: root.surfaceContext?.editMode ?? false

    onContextEditModeChanged: {
        if (!contextEditMode)
            cancelDrag();
    }
    readonly property bool vertical: surfaceContext.isVertical
    readonly property bool magnificationEnabled: (root.surfaceContext.config?.magnification ?? false) && !root.surfaceContext.editMode && root.surfaceContext.live
    readonly property bool magnificationExpand: (root.surfaceContext.config?.magnificationExpand ?? false) && root.magnificationEnabled && !root.fillAvailable
    readonly property string magnificationProfile: root.surfaceContext.config?.magnificationProfile ?? "parabolic"
    readonly property real maxMagnification: Math.max(1.05, Math.min(2.0, (root.surfaceContext.config?.magnificationScale ?? 130) / 100))
    readonly property real baseSlotSize: {
        const baseSize = root.vertical ? root.width : root.height;
        return baseSize > 0 ? baseSize : 42;
    }
    readonly property real influenceRadius: DockConfig.magnificationRadius(baseSlotSize, magnificationProfile)
    readonly property int itemTransformOrigin: {
        const edge = root.surfaceContext.config?.position;
        switch (edge) {
        case SettingsData.Position.Top:
            return Item.Top;
        case SettingsData.Position.Bottom:
            return Item.Bottom;
        case SettingsData.Position.Left:
            return Item.Left;
        case SettingsData.Position.Right:
            return Item.Right;
        default:
            return Item.Center;
        }
    }
    readonly property real hoverCursorX: stripHoverHandler.point.position.x + scroll.contentX - (root.vertical ? root.crossOverflow : 0)
    readonly property real hoverCursorY: stripHoverHandler.point.position.y + scroll.contentY - (root.vertical ? 0 : root.crossOverflow)
    // Strip origin in scene coordinates, latched while the dock is at rest; the dock moves its origin as it grows.
    property real restOriginX: 0
    property real restOriginY: 0
    readonly property real restCursorX: stripHoverHandler.point.scenePosition.x - restOriginX + scroll.contentX - (root.vertical ? root.crossOverflow : 0)
    readonly property real restCursorY: stripHoverHandler.point.scenePosition.y - restOriginY + scroll.contentY - (root.vertical ? 0 : root.crossOverflow)
    Binding {
        target: root
        property: "restOriginX"
        value: stripHoverHandler.point.scenePosition.x - stripHoverHandler.point.position.x
        when: root.magnificationProgress <= 0.001
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "restOriginY"
        value: stripHoverHandler.point.scenePosition.y - stripHoverHandler.point.position.y
        when: root.magnificationProgress <= 0.001
        restoreMode: Binding.RestoreNone
    }
    readonly property bool hoverActive: stripHoverHandler.hovered && !root.dragActive
    property real magnificationProgress: 0.0
    Binding {
        target: root
        property: "magnificationProgress"
        value: (root.hoverActive && root.magnificationEnabled) ? 1.0 : 0.0
        restoreMode: Binding.RestoreNone
    }
    Behavior on magnificationProgress {
        enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            duration: root.hoverActive ? Theme.shorterDuration : Theme.shortDuration
            easing.type: root.hoverActive ? Easing.OutCubic : Easing.InCubic
        }
    }
    readonly property var sizes: {
        layoutRevision;
        const sizes = [];
        for (let i = 0; i < repeater.count; i++)
            sizes.push(repeater.itemAt(i)?.naturalSize ?? 0);
        return sizes;
    }
    readonly property var flexible: model.map(item => item.widgetId === "flexibleSpacer" && item.enabled !== false)
    readonly property var participating: sizes.map((size, index) => size > 0 || flexible[index])
    readonly property real gapSpace: Math.max(0, participating.filter(Boolean).length - 1) * spacing
    readonly property var allocatedSizes: DockConfig.allocation(sizes, flexible, fillAvailable ? Math.max(0, availableSize - gapSpace) : 0, 0)
    // Scales depend only on the pointer in the rest frame (strip origin latched before the dock grows)
    // and on unaligned rest positions, so the displaced layout cannot feed back into them.
    readonly property var magnificationScales: {
        if (!magnificationExpand || magnificationProgress <= 0.001)
            return allocatedSizes.map(() => 1.0);
        const cursor = vertical ? restCursorY : restCursorX;
        return allocatedSizes.map((size, i) => {
            if (flexible[i] || !participating[i])
                return 1.0;
            const center = (unalignedPositions[i] ?? 0) + size / 2;
            const factor = DockConfig.magnificationFactor(Math.abs(center - cursor), influenceRadius, magnificationProfile);
            return 1.0 + (maxMagnification - 1.0) * factor * magnificationProgress;
        });
    }
    // Upper bound for the expansion, set by hosts that have a finite amount of room to grow into.
    property real expansionLimit: Infinity
    readonly property real uncappedMagnificationExpansion: magnificationScales.reduce((sum, scale, i) => sum + (scale - 1.0) * (allocatedSizes[i] ?? 0), 0)
    readonly property real totalMagnificationExpansion: Math.min(expansionLimit, uncappedMagnificationExpansion)
    // Shrinks each slot's extra so the displaced icons fit the capped expansion.
    readonly property real expansionRatio: uncappedMagnificationExpansion > 0 ? totalMagnificationExpansion / uncappedMagnificationExpansion : 1.0
    readonly property real restLength: sizes.reduce((sum, size) => sum + size, 0) + gapSpace
    readonly property real preferredLength: restLength + totalMagnificationExpansion
    readonly property real baseContentLength: allocatedSizes.reduce((sum, size) => sum + size, 0) + gapSpace
    readonly property real contentLength: baseContentLength + totalMagnificationExpansion
    readonly property bool interactionActive: {
        layoutRevision;
        if (dragActive)
            return true;
        for (let i = 0; i < repeater.count; i++) {
            if (repeater.itemAt(i)?.activeFocus || repeater.itemAt(i)?.widgetItem?.interactionActive)
                return true;
        }
        return false;
    }
    readonly property var hoveredButton: {
        layoutRevision;
        for (let i = 0; i < repeater.count; i++) {
            const button = repeater.itemAt(i)?.widgetItem?.hoveredButton;
            if (button)
                return button;
        }
        return null;
    }
    function releaseFocus() {
        for (let i = 0; i < repeater.count; i++) {
            const slot = repeater.itemAt(i);
            if (slot)
                slot.focus = false;
        }
        focus = false;
    }

    function appSlot(appIndex) {
        return model.findIndex(item => item.widgetId === "application" && item.appIndex === appIndex);
    }

    function contentPosition(item, x, y) {
        const point = item.mapToItem(scroll.contentItem, x, y);
        return vertical ? point.y : (I18n.isRtl ? scroll.contentWidth - point.x : point.x);
    }

    function dropIndex(item, x, y, accepts) {
        const position = contentPosition(item, x, y);
        let last = -1;
        for (let i = 0; i < model.length; i++) {
            if (!participating[i] || !accepts(model[i]))
                continue;
            if (position < positionAt(i) + allocatedSizes[i] / 2)
                return i;
            last = i;
        }
        return last;
    }

    signal reorderRequested(string from, string to)
    signal removeRequested(string instanceId)
    implicitWidth: vertical ? surfaceContext.thickness : preferredLength
    implicitHeight: vertical ? preferredLength : surfaceContext.thickness

    readonly property real alignOffset: {
        const slack = Math.max(0, availableSize - contentLength);
        if (align === "center")
            return slack / 2;
        if (align === "end")
            return slack;
        return 0;
    }
    function positionAt(index) {
        return positions[index] ?? alignOffset;
    }
    function revealItem(item) {
        const point = item.mapToItem(scroll.contentItem, 0, 0);
        const position = vertical ? point.y : point.x;
        const size = vertical ? item.height : item.width;
        const offset = vertical ? scroll.contentY : scroll.contentX;
        const next = Math.max(0, Math.min(Math.max(0, contentLength - availableSize), position < offset ? position : Math.max(offset, position + size - availableSize)));
        if (vertical)
            scroll.contentY = next;
        else
            scroll.contentX = next;
    }
    DeferredAction {
        id: updateLayout
        onTriggered: root.layoutRevision++
    }
    DFlickable {
        id: scroll
        x: root.vertical ? -root.crossOverflow : 0
        y: root.vertical ? 0 : -root.crossOverflow
        width: root.width + (root.vertical ? root.crossOverflow * 2 : 0)
        height: root.height + (root.vertical ? 0 : root.crossOverflow * 2)
        clip: root.contentLength > root.availableSize
        contentWidth: root.vertical ? width : root.contentLength
        contentHeight: root.vertical ? root.contentLength : height
        flickableDirection: root.vertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: !root.dragActive && root.contentLength > root.availableSize

        HoverHandler {
            id: stripHoverHandler
            enabled: root.magnificationEnabled
        }

        Repeater {
            id: repeater
            model: ScriptModel {
                values: root.model
                objectProp: "id"
            }
            delegate: FocusScope {
                id: slot
                required property int index
                required property var modelData
                readonly property var widgetItem: appLoader.item ?? loader.item
                readonly property bool flexible: modelData.widgetId === "flexibleSpacer"
                readonly property real naturalSize: modelData.enabled === false || flexible ? 0 : root.vertical ? (widgetItem?.implicitHeight || widgetItem?.height || 0) : (widgetItem?.implicitWidth || widgetItem?.width || 0)
                readonly property bool dragging: root.draggingIndex === index
                readonly property string unitId: DockConfig.unitOf(modelData)
                readonly property bool unitDragging: root.draggingUnit === unitId
                readonly property bool animatesShift: root.dragActive && !dragging && !unitDragging && !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                readonly property real layoutPosition: unitDragging ? root.positionAt(index) + root.dragOffset : (root.previewPositions[index] ?? 0)
                readonly property real targetScale: {
                    if (!root.magnificationEnabled || root.magnificationProgress <= 0.001 || slot.flexible)
                        return 1.0;
                    if (root.magnificationExpand)
                        return root.magnificationScales[index] ?? 1.0;
                    const center = root.vertical ? (slot.y + slot.height / 2) : (slot.x + slot.width / 2);
                    const cursor = root.vertical ? root.hoverCursorY : root.hoverCursorX;
                    const dist = Math.abs(center - cursor);
                    const factor = DockConfig.magnificationFactor(dist, root.influenceRadius, root.magnificationProfile);
                    return 1.0 + (root.maxMagnification - 1.0) * factor * root.magnificationProgress;
                }
                z: dragging || unitDragging ? 100 : (targetScale > 1.01 ? Math.round(targetScale * 10) : 0)

                Binding {
                    target: slot
                    property: "x"
                    value: root.vertical ? root.crossOverflow : (I18n.isRtl ? scroll.contentWidth - slot.layoutPosition - slot.width : slot.layoutPosition)
                    when: !slot.dragging
                    restoreMode: Binding.RestoreNone
                }
                Binding {
                    target: slot
                    property: "y"
                    value: root.vertical ? slot.layoutPosition : root.crossOverflow
                    when: !slot.dragging
                    restoreMode: Binding.RestoreNone
                }
                Behavior on x {
                    enabled: slot.animatesShift
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                    }
                }
                Behavior on y {
                    enabled: slot.animatesShift
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveDefaultSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
                    }
                }
                width: root.vertical ? root.width : root.allocatedSizes[index] ?? 0
                height: root.vertical ? root.allocatedSizes[index] ?? 0 : root.height
                activeFocusOnTab: !flexible && modelData.appData?.type !== "separator" && (root.participating[index] ?? false) && modelData.enabled !== false
                onActiveFocusChanged: if (activeFocus)
                    root.revealItem(slot)
                onNaturalSizeChanged: updateLayout.schedule()
                Component.onCompleted: updateLayout.schedule()
                Accessible.name: widgetItem?.dockButton?.tooltipText ?? modelData.widgetId
                Accessible.role: Accessible.Grouping
                Keys.onPressed: event => {
                    const previous = root.vertical ? Qt.Key_Up : (I18n.isRtl ? Qt.Key_Right : Qt.Key_Left);
                    const next = root.vertical ? Qt.Key_Down : (I18n.isRtl ? Qt.Key_Left : Qt.Key_Right);
                    const direction = event.key === previous ? -1 : event.key === next ? 1 : 0;
                    if (direction && root.surfaceContext.editMode && (event.modifiers & Qt.ControlModifier)) {
                        const unit = root.unitSpans.findIndex(span => span.id === slot.unitId);
                        const target = root.unitSpans[unit + direction];
                        if (unit >= 0 && target)
                            root.reorderRequested(slot.unitId, target.id);
                        event.accepted = true;
                        return;
                    }
                    if (direction) {
                        let target = slot.index + direction;
                        while (target >= 0 && target < repeater.count && !repeater.itemAt(target)?.activeFocusOnTab)
                            target += direction;
                        if (target < 0 || target >= repeater.count)
                            return;
                        repeater.itemAt(target)?.forceActiveFocus();
                        event.accepted = true;
                        return;
                    }
                    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
                        return;
                    if (slot.widgetItem?.activate)
                        slot.widgetItem.activate();
                    else if (slot.widgetItem?.focusFirst)
                        slot.widgetItem.focusFirst();
                    else if (slot.widgetItem?.triggerPopout)
                        slot.widgetItem.triggerPopout();
                    else if (slot.widgetItem?.clicked)
                        slot.widgetItem.clicked();
                    else
                        slot.widgetItem?.forceActiveFocus();
                    event.accepted = true;
                }
                Item {
                    id: visualContent
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    scale: slot.targetScale
                    transformOrigin: root.itemTransformOrigin

                    Loader {
                        id: appLoader
                        anchors.centerIn: parent
                        active: slot.modelData.widgetId === "application" && root.applicationStrip !== null
                        sourceComponent: ApplicationItem {
                            strip: root.applicationStrip
                            modelData: slot.modelData.appData
                            index: slot.modelData.appIndex
                        }
                        onLoaded: updateLayout.schedule()
                    }

                    SurfaceWidgetHost {
                        id: loader
                        anchors.centerIn: parent
                        surfaceContext: root.surfaceContext
                        widgetId: slot.modelData.widgetId
                        widgetData: slot.modelData
                        spacerSize: slot.modelData.size ?? 20
                        instanceId: slot.modelData.id
                        occurrenceOrder: slot.index
                        components: root.components
                        axis: root.surfaceContext.axis
                        isInColumn: root.vertical
                        parentScreen: root.surfaceContext.screen
                        barConfig: root.surfaceContext.config
                        barThickness: root.surfaceContext.thickness
                        widgetThickness: root.surfaceContext.widgetThickness
                        barSpacing: root.spacing
                        section: "center"
                        sectionAvailablePrimarySize: root.availableSize
                        blurBarWindow: root.surfaceContext.host
                        onContentItemReady: updateLayout.schedule()
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: Theme.cornerRadiusS
                    border.width: slot.activeFocus ? Theme.focusRingWidth : 0
                    border.color: Theme.focusRingColor
                }
                MouseArea {
                    property real pressPosition: 0

                    anchors.fill: parent
                    visible: root.surfaceContext.editMode
                    enabled: visible
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: slot.unitDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: mouse => {
                        pressPosition = root.contentPosition(this, mouse.x, mouse.y);
                        root.dragOffset = 0;
                        root.draggingUnit = slot.unitId;
                        root.targetUnit = slot.unitId;
                    }
                    onPositionChanged: mouse => {
                        if (!slot.unitDragging)
                            return;
                        root.dragOffset = root.clampedUnitOffset(slot.unitId, root.contentPosition(this, mouse.x, mouse.y) - pressPosition);
                        root.targetUnit = root.unitTarget(slot.unitId, root.dragOffset);
                    }
                    onReleased: {
                        if (slot.unitDragging && root.targetUnit !== root.draggingUnit)
                            root.reorderRequested(root.draggingUnit, root.targetUnit);
                        root.cancelDrag();
                    }
                    onCanceled: root.cancelDrag()
                    onWheel: wheel => wheel.accepted = false
                }
                DActionButton {
                    visible: root.surfaceContext.editMode && slot.modelData.widgetId !== "application" && (root.participating[slot.index] ?? false)
                    z: 2
                    anchors.top: parent.top
                    anchors.right: parent.right
                    buttonSize: Theme.iconSizeMedium
                    iconSize: Theme.iconSizeSmall
                    iconName: "close"
                    backgroundColor: Theme.errorContainer
                    iconColor: Theme.onErrorContainer
                    Accessible.name: I18n.tr("Remove")
                    onClicked: root.removeRequested(slot.modelData.id)
                }
            }
        }
        Repeater {
            model: root.surfaceContext.editMode ? root.unitIds : []
            delegate: Rectangle {
                required property string modelData
                readonly property rect bounds: root.unitBounds(modelData)
                x: bounds.x
                y: bounds.y
                width: bounds.width
                height: bounds.height
                color: "transparent"
                radius: Theme.cornerRadiusS
                border.width: Theme.dividerWidth
                border.color: root.draggingUnit === modelData ? Theme.primary : Theme.outline
            }
        }
    }
}
