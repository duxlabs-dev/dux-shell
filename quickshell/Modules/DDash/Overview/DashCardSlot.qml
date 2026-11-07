import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import "../utils/cards.js" as CardUtils

DEditableGridSlot {
    id: root

    readonly property var cardData: JSON.parse(json)
    readonly property string cardId: cardData.id ?? ""
    readonly property var entry: DashRegistry.entry(cardId)
    readonly property var cardItem: cardLoader.item
    readonly property int previewW: resizing ? grid.sizePreview.changes.w : (cardData.w || 1)
    readonly property int previewH: resizing ? grid.sizePreview.changes.h : (cardData.h || 1)

    property int resizeStartColumns: 0
    property int resizeStartRows: 0
    property int resizeStartCol: 0
    property real resizeStartCellWidth: 0

    function startResize(px, py) {
        resizeStartColumns = slot?.cols ?? 1;
        resizeStartRows = slot?.rows ?? 1;
        resizeStartCol = slot?.col ?? 0;
        resizeStartCellWidth = grid.columnWidth;
        beginResize(px, py);
    }

    onResizeRequested: (requestedWidth, requestedHeight) => {
        const w = Math.round((requestedWidth + DashMetrics.gridGap) / (resizeStartCellWidth + DashMetrics.gridGap));
        const h = Math.round((requestedHeight + DashMetrics.gridGap) / (DashMetrics.gridRowUnit + DashMetrics.gridGap));
        const want = {
            "w": Math.max(1, Math.min(w, grid.columnCap - resizeStartCol)),
            "h": h
        };
        grid.previewPanelColumns(resizeStartCol, want);
        let size = grid.fittedSize(index, want.w, want.h);
        if (size.w !== want.w || size.h !== want.h) {
            grid.previewPanelColumns(resizeStartCol, size);
            size = grid.fittedSize(index, size.w, size.h);
        }
        grid.previewSize(index, {
            "w": w === resizeStartColumns ? cardData.w : size.w,
            "h": h === resizeStartRows ? cardData.h : size.h
        });
    }

    function inject(item) {
        if (!item)
            return;
        if ("entryId" in item)
            item.entryId = root.cardId;
        if ("transientSurfaceTracker" in item)
            item.transientSurfaceTracker = Qt.binding(() => root.grid.transientSurfaceTracker);
        if (!root.entry?.isPlugin)
            return;
        if ("pluginId" in item)
            item.pluginId = root.entry.pluginId;
        if ("pluginService" in item)
            item.pluginService = PluginService;
        if ("popoutService" in item)
            item.popoutService = PopoutService;
    }

    readonly property Item focusTarget: cardItem && "focusTarget" in cardItem ? cardItem.focusTarget : (cardItem?.clickable ? cardItem : null)
    readonly property bool keyboardFocused: keyboardScope.activeFocus
    readonly property bool loading: cardLoader.status === Loader.Loading

    function focusContent(reason) {
        focusTarget?.forceActiveFocus(reason);
    }

    FocusScope {
        id: keyboardScope
        anchors.fill: parent
        onActiveFocusChanged: {
            if (activeFocus)
                root.grid.noteSlotFocus(root);
        }

        Loader {
            id: cardLoader
            anchors.fill: parent
            focus: true
            asynchronous: root.entry?.card?.async === true
            sourceComponent: root.slot ? DashRegistry.cardComponentFor(root.cardId) : null
            onLoaded: {
                root.inject(item);
                root.grid.slotLoaded(root);
            }
        }
    }

    Binding {
        target: root.cardItem
        property: "live"
        value: root.grid.live
        when: root.cardItem !== null
    }

    Binding {
        target: root.cardItem
        property: "interactive"
        value: !root.grid.editMode
        when: root.cardItem !== null
    }

    Connections {
        target: root.cardItem
        ignoreUnknownSignals: true

        function onClicked() {
            if (root.grid.editMode || root.cardItem?.opensTab === false)
                return;
            root.grid.cardClicked(root.cardId);
        }

        function onNavFocusRequested() {
            root.grid.navFocusRequested(false);
        }

        function onDetailRequested(eventData) {
            root.grid.detailRequested(eventData);
        }

        function onEditorRequested(eventData, initialDate) {
            root.grid.editorRequested(eventData, initialDate);
        }
    }

    DSpinner {
        anchors.centerIn: parent
        size: DashMetrics.spinnerSize
        visible: cardLoader.status === Loader.Loading
    }

    Loader {
        anchors.fill: parent
        anchors.margins: -PopoutMetrics.editOverflow
        z: 2
        active: root.grid.editMode || root.resizing

        sourceComponent: DashEditChrome {
            visible: root.grid.editMode
            enabled: root.interactionEnabled
            sizeText: root.previewW + "×" + root.previewH
            dragging: root.dragging
            resizing: root.resizing
            hasOptions: DashRegistry.hasOptions(root.cardId)
            onOptionsRequested: root.grid.optionsRequested(root.cardId)
            onRemoveRequested: CardUtils.removeCard(root.index)
            onResizeStarted: (px, py) => root.startResize(px, py)
            onResizeCanceled: root.cancelResize()
            onResizeMoved: (px, py) => root.resizeTo(px, py)
            onResizeEnded: root.finishResize()
        }
    }
}
