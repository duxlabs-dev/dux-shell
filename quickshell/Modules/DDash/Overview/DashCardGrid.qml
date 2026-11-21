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
    property DashEditSession editSession: null

    signal cardFocusChanged(string id)

    signal cardClicked(string cardId)
    signal optionsRequested(string cardId, string instanceId)
    signal navFocusRequested(bool backwards)
    signal detailRequested(var eventData)
    signal editorRequested(var eventData, var initialDate)

    readonly property real columnWidth: (width - DashMetrics.gridGap * (DashMetrics.gridColumns - 1)) / DashMetrics.gridColumns
    readonly property int usedColumns: slotLayout.slots.reduce((used, slot) => slot ? Math.max(used, slot.col + slot.cols) : used, 0)
    readonly property var addableEntries: DashRegistry.addableCards.map(entry => ({
                "entry": entry,
                "size": fitFor(entry.id)
            })).filter(candidate => candidate.size !== null)
    readonly property var categories: DashRegistry.cardCategories
    readonly property var catalog: DashRegistry.addableCards.map(entry => ({
                "id": entry.id,
                "text": entry.card.text,
                "icon": entry.card.icon,
                "category": entry.category,
                "description": entry.description ?? ""
            }))

    sourceItems: DashRegistry.placed
    slotLayout: GridUtils.packCards(layoutItems, placementOrder, DashMetrics.gridColumns, width, DashMetrics.gridGap, DashMetrics.gridRowUnit, I18n.isRtl, DashRegistry.isCardAvailable)
    minimumHeight: DashMetrics.tabMinHeight
    dropHeight: parent?.height ?? 0
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

    function fitFor(id) {
        if (!DashRegistry.addableCards.some(entry => entry.id === id))
            return null;
        return GridUtils.fitNewCard(sourceItems, DashMetrics.gridColumns, rowBudget, id, DashRegistry.defaultSize(id), DashRegistry.minSize(id), DashRegistry.isCardAvailable);
    }

    function canPlace(id) {
        return fitFor(id) !== null;
    }

    function addEntry(id) {
        const size = fitFor(id);
        if (!size)
            return false;
        CardUtils.addCard(id, size.w, size.h);
        return true;
    }

    // A placement may push other cards down, but not past the rows a click-add may use.
    function externalFits() {
        const limit = GridUtils.rowLimit(sourceItems, sourceItems.map((card, i) => i), DashMetrics.gridColumns, rowBudget, DashRegistry.isCardAvailable);
        return externalItem !== null && slotLayout.rows <= limit;
    }

    function hoverNew(id, scenePoint) {
        const size = fitFor(id);
        if (size && hoverExternalAt(Object.assign({
                "id": id
            }, size), scenePoint, DashMetrics.contentPadding) && externalFits())
            return true;
        clearExternal();
        return false;
    }

    function dropNew(id) {
        if (externalItem?.id !== id || !externalFits()) {
            clearExternal();
            return false;
        }
        // Deferred: the write can drop the dragged bubble from the catalog while its drag is still ending.
        Qt.callLater(() => {
            const items = takeExternal();
            if (!items)
                return;
            const dropped = items.pop();
            items.push(Object.assign(CardUtils.newCard(id, dropped.w, dropped.h), {
                "col": dropped.col,
                "row": dropped.row
            }));
            CardUtils.setLayout(items);
        });
        return true;
    }

    function externalGhostSize(id) {
        const size = externalItem?.id === id ? externalItem : (fitFor(id) ?? DashRegistry.defaultSize(id));
        return Qt.size(size.w * columnWidth + (size.w - 1) * DashMetrics.gridGap, size.h * DashMetrics.gridRowUnit + (size.h - 1) * DashMetrics.gridGap);
    }

    function hasItem(key, instanceId) {
        return DashRegistry.isCardAvailable(key) && DashRegistry.configIndex(key, instanceId) >= 0;
    }

    function optionsTarget(key, instanceId) {
        if (!hasItem(key, instanceId))
            return null;
        const card = DashRegistry.entry(key).card;
        return {
            "kind": "card",
            "entryId": key,
            "key": key,
            "instanceId": instanceId ?? "",
            "icon": card.icon,
            "text": card.text
        };
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
            if (slot && slot.focusKey === id)
                return slot.cardItem;
        }
        return null;
    }

    readonly property Item lastFocusTarget: lastFocusEntry
    readonly property bool loading: {
        for (let i = 0; i < slotRepeater.count; i++) {
            if (slotRepeater.itemAt(i)?.loading)
                return true;
        }
        return false;
    }
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
            if (slot?.focusKey === id)
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
            pendingFocusId = wanted.focusKey;
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
        if (slot.focusKey !== pendingFocusId)
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
        cardFocusChanged(slot.focusKey);
        const changed = flashSlot !== null && flashSlot !== slot;
        const keyboard = _focusReason === Qt.TabFocusReason || _focusReason === Qt.BacktabFocusReason;
        flashSlot = slot;
        if (changed && keyboard)
            ringHold.restart();
    }

    function handleKeyEvent(event) {
        if (editMode) {
            if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
                return false;
            for (let i = 0; i < slotRepeater.count; i++) {
                const slot = slotRepeater.itemAt(i);
                if (slot?.keyboardFocused)
                    return slot.selectOptions();
            }
            return false;
        }
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
