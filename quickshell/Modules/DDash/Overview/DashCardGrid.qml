pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.DDash
import "../../../Common/GridLayout.js" as GridUtils
import "../utils/cards.js" as CardUtils
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

DEditableGrid {
    id: root

    property bool live: true
    property int rowBudget: DashMetrics.minimumTabRows
    property int columnCap: DashMetrics.maximumGridColumns
    property bool panelPreviewing: false
    property string preferredFocusId: "calendar"
    property var transientSurfaceTracker: null
    property string pendingFocusId: ""
    property int pendingFocusReason: Qt.OtherFocusReason
    property Item flashSlot: null

    signal cardFocusChanged(string id)

    signal cardClicked(string cardId)
    signal optionsRequested(string cardId)
    signal navFocusRequested(bool backwards)
    signal detailRequested(var eventData)
    signal editorRequested(var eventData, var initialDate)

    readonly property real columnWidth: (width - DashMetrics.gridGap * (DashMetrics.gridColumns - 1)) / DashMetrics.gridColumns
    readonly property int usedColumns: slotLayout.slots.reduce((used, slot) => slot ? Math.max(used, slot.col + slot.cols) : used, 0)
    readonly property var addableEntries: DashRegistry.unplaced.map(entry => ({
                "entry": entry,
                "size": GridUtils.fitNewCard(sourceItems, DashMetrics.gridColumns, rowBudget, entry.id, DashRegistry.defaultSize(entry.id), DashRegistry.minSize(entry.id), DashRegistry.isCardAvailable)
            })).filter(candidate => candidate.size !== null)

    sourceItems: DashRegistry.placed
    slotLayout: GridUtils.packCards(layoutItems, placementOrder, DashMetrics.gridColumns, width, DashMetrics.gridGap, DashMetrics.gridRowUnit, I18n.isRtl, DashRegistry.isCardAvailable)
    minimumHeight: DashMetrics.tabMinHeight
    placeholderRadius: DashMetrics.cardRadius

    commitHandler: items => {
        commitPanelPreview();
        CardUtils.setLayout(items);
    }
    onSizePreviewChanged: {
        if (!sizePreview)
            clearPanelPreview();
    }

    function previewPanelColumns(startCol, size) {
        const base = DashMetrics.storedPanelColumns(DashMetrics.overviewId) || DashMetrics.defaultGridColumns;
        const wanted = Math.max(base, Math.min(columnCap, startCol + size.w));
        if (wanted === base) {
            clearPanelPreview();
            return;
        }
        if (panelPreviewing && DashMetrics.panelPreview?.columns === wanted)
            return;
        DashMetrics.panelPreview = {
            "id": DashMetrics.overviewId,
            "columns": wanted,
            "rows": DashMetrics.panelFloorRowsFor(DashMetrics.overviewId)
        };
        panelPreviewing = true;
    }

    function clearPanelPreview() {
        if (!panelPreviewing)
            return;
        panelPreviewing = false;
        DashMetrics.panelPreview = null;
    }

    function commitPanelPreview() {
        if (!panelPreviewing)
            return;
        DashRegistry.setOptions(DashMetrics.overviewId, {
            "panelColumns": DashMetrics.panelPreview.columns
        });
        clearPanelPreview();
    }

    function fittedSize(index, w, h) {
        const card = sourceItems[index];
        const want = DashRegistry.clampSize(card.id, w, h);
        const fitted = GridUtils.fitResize(pinnedItems, placementOrder, DashMetrics.gridColumns, rowBudget, index, want, DashRegistry.minSize(card.id), DashRegistry.isCardAvailable);
        return fitted ?? {
            "w": card.w,
            "h": card.h
        };
    }

    function cardItemFor(id) {
        for (let i = 0; i < slotRepeater.count; i++) {
            const slot = slotRepeater.itemAt(i);
            if (slot && slot.cardId === id)
                return slot.cardItem;
        }
        return null;
    }

    readonly property Item lastFocusTarget: lastFocusEntry
    readonly property bool blocksTabNavigation: {
        for (let i = 0; i < slotRepeater.count; i++) {
            const slot = slotRepeater.itemAt(i);
            if (slot?.keyboardFocused)
                return slot.cardItem?.blocksTabNavigation ?? false;
        }
        return false;
    }

    function keyboardSlots() {
        const slots = [];
        for (let i = 0; i < slotRepeater.count; i++) {
            const slot = slotRepeater.itemAt(i);
            if (!slot?.visible || !slot.enabled || !slot.focusTarget?.enabled || !slot.focusTarget.visible)
                continue;
            slots.push(slot);
        }
        return slots.sort((a, b) => a.y - b.y || (I18n.isRtl ? b.x - a.x : a.x - b.x));
    }

    function slotFor(id) {
        for (let i = 0; i < slotRepeater.count; i++) {
            const slot = slotRepeater.itemAt(i);
            if (slot?.cardId === id)
                return slot;
        }
        return null;
    }

    function requestFocus(backwards) {
        if (editMode) {
            navFocusRequested(backwards);
            return;
        }
        if (backwards) {
            const slots = keyboardSlots();
            const last = slots[slots.length - 1];
            last ? focusSlot(last, Qt.BacktabFocusReason) : navFocusRequested(true);
            return;
        }
        if (!focusPreferred(Qt.TabFocusReason))
            navFocusRequested(false);
    }

    function restoreFocus() {
        if (editMode)
            return false;
        ringHold.stop();
        return focusPreferred(Qt.OtherFocusReason);
    }

    function focusPreferred(reason) {
        const wanted = slotFor(preferredFocusId) ?? slotFor("calendar");
        if (wanted?.loading) {
            pendingFocusId = wanted.cardId;
            pendingFocusReason = reason;
            return true;
        }
        const slot = preferredSlot(keyboardSlots());
        if (!slot)
            return false;
        flashSlot = slot;
        focusSlot(slot, reason);
        return true;
    }

    function slotLoaded(slot) {
        if (slot.cardId !== pendingFocusId)
            return;
        pendingFocusId = "";
        if (editMode)
            return;
        flashSlot = slot;
        focusSlot(slot, pendingFocusReason);
    }

    property int _focusReason: Qt.OtherFocusReason

    function focusSlot(slot, reason) {
        _focusReason = reason;
        slot.focusContent(reason);
        _focusReason = Qt.OtherFocusReason;
    }

    function noteSlotFocus(slot) {
        cardFocusChanged(slot.cardId);
        const changed = flashSlot !== null && flashSlot !== slot;
        const keyboard = _focusReason === Qt.TabFocusReason || _focusReason === Qt.BacktabFocusReason;
        flashSlot = slot;
        if (changed && keyboard)
            ringHold.restart();
    }

    function handleKeyEvent(event) {
        if (editMode)
            return false;
        const slots = keyboardSlots();
        const index = slots.findIndex(slot => slot.keyboardFocused);
        if (index < 0)
            return false;
        const card = slots[index].cardItem;
        if (typeof card.handleKeyEvent === "function" && card.handleKeyEvent(event) === true)
            return true;
        if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
            return false;
        if (card.blocksTabNavigation)
            return false;
        const backwards = event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier);
        if (!cycleFocus(backwards))
            navFocusRequested(backwards);
        return true;
    }

    function preferredSlot(slots) {
        const wanted = slotFor(preferredFocusId) ?? slotFor("calendar");
        return (wanted && slots.includes(wanted) ? wanted : null) ?? slots[0] ?? null;
    }

    function moveCardFocus(direction) {
        if (editMode)
            return false;
        const slots = keyboardSlots();
        const index = slots.findIndex(slot => slot.keyboardFocused);
        if (index < 0)
            return focusPreferred(Qt.TabFocusReason);
        const nextIndex = GridUtils.neighborInDirection(slots.map(slot => slot.slot), index, direction);
        if (nextIndex < 0)
            return false;
        focusSlot(slots[nextIndex], Qt.TabFocusReason);
        return true;
    }

    function cycleFocus(backwards) {
        return FocusNavigation.moveFocus(keyboardSlots().map(slot => slot.focusTarget), backwards);
    }

    function cycleCardFocus(backwards) {
        if (editMode)
            return false;
        const slots = keyboardSlots();
        if (!slots.length)
            return false;
        const index = slots.findIndex(slot => slot.keyboardFocused);
        const step = backwards ? -1 : 1;
        const next = index < 0 ? (backwards ? slots.length - 1 : 0) : (index + step + slots.length) % slots.length;
        focusSlot(slots[next], backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason);
        return true;
    }

    Item {
        id: lastFocusEntry
        function requestFocus() {
            root.requestFocus(true);
        }
    }

    Repeater {
        id: slotRepeater
        model: root.tileModel

        DashCardSlot {
            grid: root
        }
    }

    Timer {
        id: ringHold
        interval: DashMetrics.focusFlashHold
    }

    Rectangle {
        x: root.flashSlot?.x ?? 0
        y: root.flashSlot?.y ?? 0
        width: root.flashSlot?.width ?? 0
        height: root.flashSlot?.height ?? 0
        z: 3
        radius: DashMetrics.cardRadius
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRingColor
        visible: root.flashSlot !== null && opacity > 0
        opacity: ringHold.running ? 1 : 0

        Behavior on opacity {
            enabled: DashMetrics.animationsEnabled
            NumberAnimation {
                duration: DashMetrics.fadeDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }
}
