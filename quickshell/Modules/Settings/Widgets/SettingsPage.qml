import QtQuick
import qs.Common
import qs.DCommon.Widgets

DFlickable {
    id: root

    default property alias content: column.data
    property alias spacing: column.spacing
    property alias columnWidth: column.width
    property real contentMaxWidth: SettingsMetrics.contentMaxWidth
    property Item fabBar: null
    // A page shown inside another page's column takes its content height and leaves scrolling to that page
    readonly property Item embedHost: {
        for (let p = parent; p; p = p.parent) {
            if (p.embedsSettingsPage === true)
                return p;
        }
        return null;
    }
    readonly property bool embedded: embedHost !== null

    anchors.fill: parent
    anchors.leftMargin: embedded ? 0 : -SettingsMetrics.focusGutter
    anchors.rightMargin: embedded ? 0 : -SettingsMetrics.focusGutter
    anchors.topMargin: embedded ? 0 : -SettingsMetrics.focusGutter
    clip: !embedded
    interactive: !embedded
    wheelEnabled: !embedded
    showScrollBar: !embedded
    fadeEdges: !embedded
    contentHeight: column.height + Theme.spacingXL
    contentWidth: width
    fadeSideInset: (width - column.width) / 2

    Binding {
        target: root.embedHost
        property: "pageHeight"
        value: column.height
        when: root.embedded
    }

    readonly property Item pageHost: {
        for (let p = parent; p; p = p.parent) {
            if (p.firstScreenReady !== undefined)
                return p;
        }
        return null;
    }
    readonly property bool settled: pageHost?.pageSettled ?? true
    property bool firstScreenBuilt: false
    property var _later: []
    property var _incubating: []

    Component.onCompleted: buildFirstScreen()
    onHeightChanged: buildFirstScreen()
    onVisibleChanged: buildFirstScreen()
    onSettledChanged: Qt.callLater(_buildLater)

    function buildFirstScreen() {
        if (embedded || height <= 0) {
            firstScreenBuilt = true;
            return;
        }
        if (!visible)
            return;
        if (pageHost?.pageActive ?? true) {
            firstScreenBuilt = _fill(Infinity);
            return;
        }
        firstScreenBuilt = _fill(0);
        if (!firstScreenBuilt)
            Qt.callLater(_fillSlice);
    }

    // A page still waiting to be shown builds in slices, so the window keeps drawing frames meanwhile
    function _fillSlice() {
        if (!visible)
            return;
        firstScreenBuilt = _fill(SettingsMetrics.pageBuildSlice);
        if (!firstScreenBuilt)
            Qt.callLater(_fillSlice);
    }

    // Cards past the first screen incubate between frames, one at a time and only while the page is the one on screen
    function buildLater(card) {
        if (_later.includes(card))
            return;
        _later.push(card);
        Qt.callLater(_buildLater);
    }

    function cardBuilt() {
        Qt.callLater(_buildLater);
    }

    function _buildLater() {
        if (!settled)
            return;
        _incubating = _incubating.filter(card => card.status === Loader.Loading);
        while (_later.length > 0 && _incubating.length < SettingsMetrics.pageIncubationDepth) {
            const card = _later.shift();
            card.active = true;
            _incubating.push(card);
        }
    }

    function _fill(budget) {
        const started = Date.now();
        for (const card of _deferredCards(column, 0, [])) {
            if (card.status === Loader.Loading)
                return false;
            if (_topOf(card) > height)
                return true;
            if (Date.now() - started >= budget)
                return false;
            card.buildNow();
        }
        return true;
    }

    // Cards and positioners take their size on polish, which a page still being built has not had
    function _polishFlow(flow) {
        const cards = flow.children;
        for (let i = 0; i < cards.length; i++) {
            const built = typeof cards[i].buildNow === "function" ? cards[i].item : cards[i];
            built?.ensurePolished();
        }
        flow.ensurePolished();
    }

    // An unbuilt card has no height, so its positioner leaves it where it was created
    function _topOf(card) {
        const flow = card.parent;
        _polishFlow(column);
        _polishFlow(flow);
        const siblings = flow.children;
        let above = null;
        for (let i = 0; siblings[i] !== card; i++) {
            if (siblings[i].visible && siblings[i].height > 0)
                above = siblings[i];
        }
        if (!above)
            return flow.mapToItem(column, 0, 0).y;
        // A grid cell can share its row with the one before it
        return above.mapToItem(column, 0, flow.columns > 1 ? 0 : above.height).y;
    }

    function _deferredCards(item, depth, found, built = false) {
        const children = item.children;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (typeof child.buildNow === "function") {
                if (child.section === null && (built ? child.status === Loader.Ready : child.when && child.status !== Loader.Ready))
                    found.push(child);
                continue;
            }
            if (depth < SettingsMetrics.deferredCardSearchDepth)
                _deferredCards(child, depth + 1, found, built);
        }
        return found;
    }

    // A page torn down in one step costs frames, so its cards go first, one per call
    function unbuildCard() {
        const card = _deferredCards(column, 0, [], true).pop();
        if (!card)
            return false;
        card.active = false;
        return true;
    }

    Column {
        id: column
        topPadding: root.embedded ? 0 : Theme.spacingXS + SettingsMetrics.focusGutter
        width: root.embedded ? parent.width : Math.min(root.contentMaxWidth, parent.width - SettingsMetrics.focusGutter * 2)
        bottomPadding: (root.embedded ? 0 : SettingsMetrics.pagePaddingV) + (root.fabBar?.reservedHeight ?? 0)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: SettingsMetrics.cardGap
    }
}
