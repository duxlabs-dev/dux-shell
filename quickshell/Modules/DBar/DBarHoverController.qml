pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

Item {
    id: root

    required property var barContent
    required property var barWindow
    required property var barConfig
    property var widgetOwner: null
    property var sections: []

    property var leftWidgetsModel
    property var centerWidgetsModel
    property var rightWidgetsModel

    property string activeHoverTrigger: ""
    readonly property bool hoverPopoutsEnabled: barConfig?.hoverPopouts ?? false
    readonly property int hoverPopoutDelay: Math.max(0, barConfig?.hoverPopoutDelay ?? 150)

    property real _lastHoverGlobalX: 0
    property real _lastHoverGlobalY: 0
    property bool _hitTestPending: false
    property bool _barHovered: false
    property var _pendingHoverHit: null
    property string _pendingHoverTrigger: ""
    property string _hoverReopenSuppressedTrigger: ""

    property bool _candidateCacheValid: false
    property var _candidateCache: []
    property var _candidateWatchers: []
    property bool _lastLookupWasMiss: false

    width: 0
    height: 0

    onLeftWidgetsModelChanged: invalidateCandidateCache()
    onCenterWidgetsModelChanged: invalidateCandidateCache()
    onRightWidgetsModelChanged: invalidateCandidateCache()
    onSectionsChanged: invalidateCandidateCache()

    onHoverPopoutsEnabledChanged: {
        invalidateCandidateCache();
        if (hoverPopoutsEnabled)
            return;
        cancelQueuedHitTest();
        _cancelPendingHover();
        _hoverCloseTimer.stop();
        if (hasOpenHoverSurface() && !isActiveHoverSurfacePinned())
            closeHoverSurfaces();
        activeHoverTrigger = "";
        _hoverReopenSuppressedTrigger = "";
    }

    Component.onDestruction: _disconnectCandidateWatchers()

    Connections {
        target: root.widgetOwner || root.barContent
        enabled: root.hoverPopoutsEnabled

        function onWidthChanged() {
            root.invalidateCandidateCache();
        }

        function onHeightChanged() {
            root.invalidateCandidateCache();
        }
    }

    readonly property var barWindowScreen: root.barWindow?.screen ?? null

    onBarWindowScreenChanged: invalidateCandidateCache()

    Connections {
        target: PopoutManager
        enabled: root.hoverPopoutsEnabled

        function onPopoutChanged() {
            root._reconcileClosedHoverSurface();
        }

        function onPopoutToggledClosed(screenName) {
            root._suppressReopenAfterToggleClose(screenName);
        }
    }

    Connections {
        target: BarWidgetService
        enabled: root.hoverPopoutsEnabled

        function onWidgetRegistered(_widgetId, screenName) {
            if (screenName === root.barWindow?.screen?.name)
                root.invalidateCandidateCache();
        }

        function onWidgetUnregistered(_widgetId, screenName) {
            if (screenName === root.barWindow?.screen?.name)
                root.invalidateCandidateCache();
        }
    }

    FrameAnimation {
        running: root._hitTestPending
        onTriggered: {
            root._hitTestPending = false;
            root.checkHoverPopout(root._lastHoverGlobalX, root._lastHoverGlobalY);
        }
    }

    Timer {
        id: _hoverIntentTimer
        interval: root.hoverPopoutDelay
        repeat: false
        onTriggered: root._commitPendingHover()
    }

    // Grace timer to prevent flicker when crossing gaps.
    Timer {
        id: _hoverCloseTimer
        interval: 120
        repeat: false
        onTriggered: root._commitHoverClose()
    }

    function queueHoverPoint(gx, gy) {
        _lastHoverGlobalX = gx;
        _lastHoverGlobalY = gy;
        _barHovered = true;
        PopoutManager.updateHoverCursor(gx, gy);
        if (hoverPopoutsEnabled)
            _hitTestPending = true;
    }

    function updateBarHovered(hovered) {
        _barHovered = hovered;
        if (hovered) {
            _hoverCloseTimer.stop();
            return;
        }

        cancelQueuedHitTest();
        _cancelPendingHover();
        _hoverReopenSuppressedTrigger = "";
        if (!hoverPopoutsEnabled || isActiveHoverSurfacePinned())
            return;
        _hoverCloseTimer.restart();
    }

    function cancelQueuedHitTest() {
        _hitTestPending = false;
    }

    function recheckLatestPoint() {
        checkHoverPopout(_lastHoverGlobalX, _lastHoverGlobalY);
    }

    function resetForBarGeometryChange() {
        invalidateCandidateCache();
        cancelQueuedHitTest();
        _cancelPendingHover();
        _hoverCloseTimer.stop();
        _hoverReopenSuppressedTrigger = "";
        barContent.cancelQueuedWidgetPopout();

        const activePopout = PopoutManager.getActivePopout(barWindow?.screen);
        const hasTransientSurface = activeHoverTrigger !== "" || activePopout?.hoverDismissEnabled === true;
        if (hasTransientSurface && !isActiveHoverSurfacePinned())
            closeHoverSurfaces();
        else
            activeHoverTrigger = "";
    }

    function invalidateCandidateCache() {
        _candidateCacheValid = false;
        _candidateCache = [];
        _lastLookupWasMiss = false;
        _disconnectCandidateWatchers();
    }

    function _disconnectCandidateWatchers() {
        const watchers = _candidateWatchers;
        _candidateWatchers = [];
        for (let i = 0; i < watchers.length; i++) {
            const watcher = watchers[i];
            try {
                const signal = watcher.object?.[watcher.signalName];
                if (signal && typeof signal.disconnect === "function")
                    signal.disconnect(watcher.callback);
            } catch (e) {}
        }
    }

    function _watchCandidateObject(object) {
        if (!object)
            return;
        for (let i = 0; i < _candidateWatchers.length; i++) {
            if (_candidateWatchers[i].object === object)
                return;
        }

        const signalNames = ["xChanged", "yChanged", "widthChanged", "heightChanged", "visibleChanged", "parentChanged", "childrenChanged", "itemChanged", "activeChanged", "destroyed"];
        for (let i = 0; i < signalNames.length; i++) {
            const signalName = signalNames[i];
            try {
                const signal = object[signalName];
                if (!signal || typeof signal.connect !== "function")
                    continue;
                const callback = function () {
                    root.invalidateCandidateCache();
                };
                signal.connect(callback);
                _candidateWatchers.push({
                    object,
                    signalName,
                    callback
                });
            } catch (e) {}
        }
    }

    function _getBarSections() {
        return root.sections || [];
    }

    function _itemBelongsToThisBar(item) {
        const owner = root.widgetOwner || barContent;
        if (!owner || !item)
            return true;
        let node = item;
        let guard = 0;
        while (node && guard < 100) {
            if (node === owner)
                return true;
            node = node.parent;
            guard++;
        }
        return false;
    }

    function _findWidgetHostInWrapper(wrapper) {
        if (wrapper.inOverflow)
            return null;
        if (wrapper.host)
            return wrapper.host;
        if (wrapper.widgetId !== undefined)
            return wrapper;
        const children = wrapper.children || [];
        for (let i = 0; i < children.length; i++) {
            if (children[i].widgetId !== undefined)
                return children[i];
        }
        return null;
    }

    function _collectSectionWrappers(section) {
        _watchCandidateObject(section);
        const layoutLoader = section.widgetLayoutLoader;
        _watchCandidateObject(layoutLoader);
        const layout = layoutLoader?.item;
        if (layout) {
            _watchCandidateObject(layout);
            return layout.children || [];
        }
        const children = section.children || [];
        const wrappers = [];
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            if (!child || child === layoutLoader)
                continue;
            if (child.itemData !== undefined || child.widgetId !== undefined || _findWidgetHostInWrapper(child))
                wrappers.push(child);
        }
        return wrappers;
    }

    readonly property var _hoverSpecs: ({
            launcherButton: {
                loader: "appDrawerLoader",
                triggerSource: "appDrawer",
                useVisualItem: true
            },
            clipboard: {
                loader: "clipboardHistoryPopoutLoader",
                triggerSource: "clipboard",
                prepare: popout => popout.activeTab = "recents"
            },
            clock: {
                loader: "dankDashPopoutLoader",
                dashTab: "overview"
            },
            music: {
                loader: "dankDashPopoutLoader",
                dashTab: "media"
            },
            weather: {
                loader: "dankDashPopoutLoader",
                dashTab: "weather"
            },
            cpuUsage: {
                loader: "processListPopoutLoader",
                triggerSource: "cpu"
            },
            memUsage: {
                loader: "processListPopoutLoader",
                triggerSource: "memory"
            },
            cpuTemp: {
                loader: "processListPopoutLoader",
                triggerSource: "cpu_temp"
            },
            gpuTemp: {
                loader: "processListPopoutLoader",
                triggerSource: "gpu_temp"
            },
            notificationButton: {
                loader: "notificationCenterLoader",
                triggerSource: "notifications",
                setTriggerScreen: true
            },
            battery: {
                loader: "batteryPopoutLoader",
                triggerSource: "battery"
            },
            layout: {
                loader: "layoutPopoutLoader",
                triggerSource: "layout"
            },
            vpn: {
                loader: "vpnPopoutLoader",
                triggerSource: "vpn"
            },
            powerMenuButton: {
                loader: "powerMenuPopoutLoader",
                triggerSource: "powerMenu"
            },
            colorPicker: {
                loader: "colorPickerPopoutLoader",
                triggerSource: "colorPicker"
            },
            controlCenterButton: {
                loader: "controlCenterLoader",
                triggerSource: "controlCenter",
                setTriggerScreen: true,
                afterOpen: loader => {
                    if (loader.item?.shouldBeVisible && NetworkService.wifiEnabled)
                        NetworkService.scanWifi();
                }
            },
            systemUpdate: {
                loader: "systemUpdateLoader",
                triggerSource: "systemUpdate",
                useVisualItem: true
            }
        })

    function _widgetSupportsHoverPopout(widgetId, widgetItem) {
        if (!widgetId || !widgetItem)
            return false;
        if (typeof widgetItem.triggerHoverPopout === "function")
            return true;
        if (widgetId === "systemTray")
            return typeof widgetItem.openHoverAtGlobalPoint === "function";
        return widgetId === "notepadButton" || _hoverSpecs[widgetId] !== undefined;
    }

    function _enumerateWidgetHosts() {
        const hosts = [];
        const sections = _getBarSections();
        for (let s = 0; s < sections.length; s++) {
            const sectionEntry = sections[s];
            const section = sectionEntry.section;
            if (!section)
                continue;
            const wrappers = _collectSectionWrappers(section);
            for (let i = 0; i < wrappers.length; i++) {
                const wrapper = wrappers[i];
                const host = _findWidgetHostInWrapper(wrapper);
                if (!host?.widgetId)
                    continue;
                _watchCandidateObject(wrapper);
                _watchCandidateObject(host);
                hosts.push({
                    host,
                    wrapper,
                    section: sectionEntry.name
                });
            }
        }
        return hosts;
    }

    function _collectHoverCandidates() {
        const screenName = barWindow.screen?.name;
        const candidates = [];
        const seen = new Set();

        function addCandidate(widgetId, widgetItem, sectionHint) {
            if (!widgetId || !widgetItem || seen.has(widgetItem))
                return;
            if (!root._itemBelongsToThisBar(widgetItem))
                return;
            if (!root._widgetSupportsHoverPopout(widgetId, widgetItem))
                return;
            if (!root.barContent.getWidgetVisible(widgetId))
                return;
            seen.add(widgetItem);
            candidates.push({
                widgetId,
                widgetItem,
                section: widgetItem.section || sectionHint || "right",
                wrapper: null,
                host: null
            });
        }

        if (screenName) {
            const registry = BarWidgetService.widgetRegistry;
            if (registry && typeof registry === "object") {
                for (const widgetId in registry) {
                    const screenMap = registry[widgetId];
                    if (!screenMap || typeof screenMap !== "object")
                        continue;
                    const widgetItem = screenMap[screenName];
                    if (widgetItem)
                        addCandidate(widgetId, widgetItem, widgetItem.section);
                }
            }
        }

        const hosts = _enumerateWidgetHosts();
        for (let i = 0; i < hosts.length; i++) {
            const entry = hosts[i];
            if (!entry.host?.item)
                continue;
            const existing = candidates.find(candidate => candidate.widgetItem === entry.host.item);
            if (existing) {
                existing.wrapper = entry.wrapper;
                existing.host = entry.host;
                if (!existing.section)
                    existing.section = entry.section;
                continue;
            }
            if (!_widgetSupportsHoverPopout(entry.host.widgetId, entry.host.item))
                continue;
            candidates.push({
                widgetId: entry.host.widgetId,
                widgetItem: entry.host.item,
                section: entry.host.item.section || entry.section,
                wrapper: entry.wrapper,
                host: entry.host
            });
        }

        return candidates;
    }

    Connections {
        target: root.barWindow?.hostWindow ?? null
        enabled: root.hoverPopoutsEnabled

        function onMarginsChanged() {
            root.invalidateCandidateCache();
        }
    }

    function _globalItemBounds(item) {
        try {
            const topLeft = barContent.surfaceContext.screenPoint(item, 0, 0);
            return {
                x: topLeft.x,
                y: topLeft.y,
                width: item.width,
                height: item.height
            };
        } catch (e) {
            return null;
        }
    }

    function _hitBoundsForWidget(widgetItem, wrapper) {
        try {
            if (!widgetItem?.visible)
                return null;

            if (widgetItem.visualContent !== undefined) {
                const visual = widgetItem.visualContent;
                if (visual && visual.width > 0 && visual.height > 0)
                    return _globalItemBounds(visual);
            }

            if (widgetItem.width > 0 && widgetItem.height > 0)
                return _globalItemBounds(widgetItem);

            if (wrapper && wrapper.width > 0 && wrapper.height > 0)
                return _globalItemBounds(wrapper);
        } catch (e) {}
        return null;
    }

    function _pointInBounds(gx, gy, bounds) {
        return gx >= bounds.x && gx < bounds.x + bounds.width && gy >= bounds.y && gy < bounds.y + bounds.height;
    }

    function _sameBounds(a, b) {
        return !!a && !!b && a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
    }

    function _buildCandidateCache() {
        _disconnectCandidateWatchers();
        const candidates = _collectHoverCandidates();
        const cache = [];
        for (let i = 0; i < candidates.length; i++) {
            const entry = candidates[i];
            const bounds = _hitBoundsForWidget(entry.widgetItem, entry.wrapper);
            _watchCandidateObject(entry.widgetItem);
            _watchCandidateObject(entry.wrapper);
            _watchCandidateObject(entry.host);
            try {
                _watchCandidateObject(entry.widgetItem?.visualContent);
            } catch (e) {}
            if (!bounds || bounds.width <= 0 || bounds.height <= 0)
                continue;
            cache.push({
                widgetId: entry.widgetId,
                widgetItem: entry.widgetItem,
                section: entry.section,
                wrapper: entry.wrapper,
                bounds
            });
        }
        _candidateCache = cache;
        _candidateCacheValid = true;
        _lastLookupWasMiss = false;
    }

    function _scanCandidateCache(gx, gy) {
        let best = null;
        let bestArea = Infinity;
        for (let i = 0; i < _candidateCache.length; i++) {
            const entry = _candidateCache[i];
            const bounds = entry.bounds;
            if (!_pointInBounds(gx, gy, bounds))
                continue;
            const area = bounds.width * bounds.height;
            if (area < bestArea) {
                bestArea = area;
                best = entry;
            }
        }
        return best;
    }

    function _validatedHit(entry, gx, gy) {
        if (!entry)
            return null;
        const liveBounds = _hitBoundsForWidget(entry.widgetItem, entry.wrapper);
        if (!liveBounds || !_pointInBounds(gx, gy, liveBounds))
            return null;
        if (!_sameBounds(entry.bounds, liveBounds))
            return null;
        return {
            widgetId: entry.widgetId,
            widgetItem: entry.widgetItem,
            section: entry.section
        };
    }

    function findWidgetAtGlobalPoint(gx, gy) {
        if (!_candidateCacheValid)
            _buildCandidateCache();

        let entry = _scanCandidateCache(gx, gy);
        let hit = _validatedHit(entry, gx, gy);
        if (entry && !hit) {
            invalidateCandidateCache();
            _buildCandidateCache();
            entry = _scanCandidateCache(gx, gy);
            hit = _validatedHit(entry, gx, gy);
        } else if (!entry && !_lastLookupWasMiss) {
            // One live rebuild on entry into an empty gap covers layout changes whose
            // source did not expose a QML geometry signal without rescanning every frame.
            invalidateCandidateCache();
            _buildCandidateCache();
            entry = _scanCandidateCache(gx, gy);
            hit = _validatedHit(entry, gx, gy);
        }

        _lastLookupWasMiss = !hit;
        return hit;
    }

    function dashTriggerSource(section, tabId) {
        return (barConfig?.id ?? "default") + "-" + section + "-" + tabId;
    }

    function _notepadWidgetForScreen() {
        // Prefer this bar's own enumerated candidates; the registry is screen-keyed and a
        // sibling bar on the same screen can shadow it.
        if (!_candidateCacheValid)
            _buildCandidateCache();
        for (let i = 0; i < _candidateCache.length; i++) {
            if (_candidateCache[i].widgetId === "notepadButton")
                return _candidateCache[i].widgetItem;
        }
        const screenName = barWindow?.screen?.name;
        const fromRegistry = screenName ? BarWidgetService.getWidget("notepadButton", screenName) : null;
        if (fromRegistry && _itemBelongsToThisBar(fromRegistry))
            return fromRegistry;
        return null;
    }

    function notepadContainsGlobalPoint(gx, gy) {
        const instance = _notepadWidgetForScreen()?.notepadInstance;
        if (!instance?.isVisible || typeof instance.containsGlobalPoint !== "function")
            return false;
        return instance.containsGlobalPoint(gx, gy);
    }

    function isActiveHoverSurfacePinned() {
        if (activeHoverTrigger === "notepadButton") {
            const instance = _notepadWidgetForScreen()?.notepadInstance;
            if (instance?.hoverDismissSuspended === true)
                return true;
        }
        return PopoutManager.isActivePopoutPinned(barWindow?.screen);
    }

    function cursorOverHoverChain(gx, gy, excludedBarWindow) {
        if (PopoutManager.cursorOverBar(gx, gy, undefined, excludedBarWindow))
            return true;
        const popout = PopoutManager.getActivePopout(barWindow?.screen);
        if (popout?.containsGlobalPoint?.(gx, gy))
            return true;
        if (notepadContainsGlobalPoint(gx, gy))
            return true;
        const screenName = barWindow.screen?.name;
        if (screenName && TrayMenuManager.activeTrayMenus[screenName])
            return true;
        return false;
    }

    function _closeHoverNotepad() {
        if (activeHoverTrigger !== "notepadButton")
            return;
        const instance = _notepadWidgetForScreen()?.notepadInstance;
        if (!instance)
            return;
        if (instance.hoverDismissEnabled !== undefined)
            instance.hoverDismissEnabled = false;
        if (typeof instance.hideFromHoverDismiss === "function")
            instance.hideFromHoverDismiss();
        else if (typeof instance.hide === "function")
            instance.hide();
    }

    function closeHoverSurfaces() {
        _closeHoverNotepad();
        activeHoverTrigger = "";
        PopoutManager.dismissHoverPopoutForScreen(barWindow?.screen);
        TrayMenuManager.closeHoverMenus();
    }

    function _beginSupersededCloseForActive() {
        const popout = PopoutManager.getActivePopout(barWindow?.screen);
        if (popout && typeof popout.beginSupersededClose === "function")
            popout.beginSupersededClose();
    }

    function openNotepadHover(widgetItem) {
        const instance = widgetItem.prepareNotepadInstance?.(widgetItem.notepadInstance) ?? widgetItem.notepadInstance;
        if (!instance || typeof instance.show !== "function")
            return false;
        if (instance.hoverDismissEnabled !== undefined)
            instance.hoverDismissEnabled = true;
        instance.show();
        return true;
    }

    function _reconcileClosedHoverSurface() {
        const hadStaleTrigger = activeHoverTrigger !== "" && !hasOpenHoverSurface();
        if (hadStaleTrigger)
            activeHoverTrigger = "";
        // A cursor resting on the trigger emits no further points; retest so the popout
        // reopens without needing the cursor to leave and come back.
        if (hadStaleTrigger && _barHovered && hoverPopoutsEnabled)
            recheckLatestPoint();
    }

    function _suppressReopenAfterToggleClose(screenName) {
        if (screenName !== barWindow?.screen?.name)
            return;
        activeHoverTrigger = "";
        if (!hoverPopoutsEnabled)
            return;
        _cancelPendingHover();
        const gx = PopoutManager.hoverCursorGlobalX;
        const gy = PopoutManager.hoverCursorGlobalY;
        const hit = findWidgetAtGlobalPoint(gx, gy);
        _hoverReopenSuppressedTrigger = hit ? _triggerKeyForHit(hit, gx, gy) : "";
    }

    function _syncHoverTriggerState() {
        if (activeHoverTrigger === "notepadButton") {
            const instance = _notepadWidgetForScreen()?.notepadInstance;
            if (!instance?.isVisible) {
                _hoverReopenSuppressedTrigger = activeHoverTrigger;
                activeHoverTrigger = "";
            }
            return;
        }
        if (activeHoverTrigger !== "" && !hasOpenHoverSurface()) {
            // Tray menus close outside PopoutManager; popout closures reconcile via
            // onPopoutChanged and must not leave a suppression that eats the next hover.
            _hoverReopenSuppressedTrigger = activeHoverTrigger.startsWith("tray-") ? activeHoverTrigger : "";
            activeHoverTrigger = "";
        }
    }

    function hasOpenHoverSurface() {
        if (activeHoverTrigger === "")
            return false;
        if (activeHoverTrigger === "notepadButton") {
            const instance = _notepadWidgetForScreen()?.notepadInstance;
            return instance?.isVisible ?? false;
        }
        if (activeHoverTrigger.startsWith("tray-")) {
            const screenName = barWindow.screen?.name;
            return !!(screenName && TrayMenuManager.activeTrayMenus[screenName]);
        }
        const popout = PopoutManager.getActivePopout(barWindow?.screen);
        if (!popout)
            return false;
        if (popout.dashVisible !== undefined)
            return !!popout.dashVisible || !!popout.isClosing;
        if (popout.notificationHistoryVisible !== undefined)
            return !!popout.notificationHistoryVisible || !!popout.isClosing;
        return !!(popout.shouldBeVisible || popout.isClosing);
    }

    function _loaderForWidgetId(widgetId) {
        const loaderName = _hoverSpecs[widgetId]?.loader;
        return loaderName ? PopoutService[loaderName] : null;
    }

    function openHoverPopoutForHit(hit) {
        if (!hit?.widgetItem)
            return false;

        const widgetItem = hit.widgetItem;
        if (hit.widgetId === "systemTray") {
            if (typeof widgetItem.openHoverAtGlobalPoint !== "function")
                return false;
            return !!widgetItem.openHoverAtGlobalPoint(hit.globalX, hit.globalY);
        }
        if (typeof widgetItem.triggerHoverPopout === "function") {
            widgetItem.triggerHoverPopout(hit.widgetId);
            return true;
        }
        if (hit.widgetId === "notepadButton")
            return openNotepadHover(widgetItem);

        const spec = _hoverSpecs[hit.widgetId];
        if (!spec)
            return false;

        const loader = PopoutService[spec.loader];
        const request = {
            widgetItem,
            section: hit.section,
            mode: "hover",
            loader,
            triggerSource: spec.dashTab ? dashTriggerSource(hit.section, spec.dashTab) : spec.triggerSource
        };
        if (spec.dashTab) {
            request.prepare = popout => popout.requestTab(spec.dashTab);
            request.useCenterSection = true;
            request.setTriggerScreen = true;
        }
        if (spec.prepare)
            request.prepare = spec.prepare;
        if (spec.setTriggerScreen)
            request.setTriggerScreen = true;
        if (spec.useVisualItem)
            request.visualItem = widgetItem;

        if (!barContent.openWidgetPopout(request))
            return false;
        if (spec.afterOpen)
            spec.afterOpen(loader);
        return true;
    }

    function checkHoverPopout(gx, gy) {
        if (!hoverPopoutsEnabled)
            return;

        _lastHoverGlobalX = gx;
        _lastHoverGlobalY = gy;
        PopoutManager.updateHoverCursor(gx, gy);
        _syncHoverTriggerState();

        if (isActiveHoverSurfacePinned())
            return;

        const hit = findWidgetAtGlobalPoint(gx, gy);
        if (!hit) {
            _hoverReopenSuppressedTrigger = "";
            _cancelPendingHover();
            scheduleHoverClose(gx, gy);
            return;
        }

        hit.globalX = gx;
        hit.globalY = gy;

        const triggerKey = _triggerKeyForHit(hit, gx, gy);

        if (!triggerKey) {
            _cancelPendingHover();
            scheduleHoverClose(gx, gy);
            return;
        }

        if (_hoverReopenSuppressedTrigger === triggerKey) {
            _cancelPendingHover();
            _hoverCloseTimer.stop();
            return;
        }
        if (_hoverReopenSuppressedTrigger !== "")
            _hoverReopenSuppressedTrigger = "";

        _hoverCloseTimer.stop();

        if (triggerKey === activeHoverTrigger && hasOpenHoverSurface() && PopoutManager.getActivePopout(barWindow?.screen)?.isClosing !== true) {
            _cancelPendingHover();
            return;
        }

        _pendingHoverHit = hit;
        if (_pendingHoverTrigger !== triggerKey) {
            _pendingHoverTrigger = triggerKey;
            if (hoverPopoutDelay <= 0)
                _commitPendingHover();
            else
                _hoverIntentTimer.restart();
        }
    }

    function _cancelPendingHover() {
        _hoverIntentTimer.stop();
        _pendingHoverHit = null;
        _pendingHoverTrigger = "";
    }

    function _hitTargetsActivePopout(hit) {
        const active = PopoutManager.getActivePopout(barWindow?.screen);
        if (!active || !hit)
            return false;
        const loader = _loaderForWidgetId(hit.widgetId);
        if (!loader)
            return false;
        return barContent.resolvePopoutFromLoader(loader) === active;
    }

    function _commitPendingHover() {
        const hit = _pendingHoverHit;
        const triggerKey = _pendingHoverTrigger;
        _pendingHoverHit = null;
        _pendingHoverTrigger = "";
        if (!hit || !hoverPopoutsEnabled)
            return;
        if (isActiveHoverSurfacePinned())
            return;
        if (!PopoutManager.cursorOverBar(_lastHoverGlobalX, _lastHoverGlobalY))
            return;

        const activePopout = PopoutManager.getActivePopout(barWindow?.screen);
        const targetLoader = _loaderForWidgetId(hit.widgetId);
        const targetPopout = barContent.resolvePopoutFromLoader(targetLoader);

        const managerOwnsTransition = !!(activePopout && targetPopout);

        if (triggerKey !== activeHoverTrigger && activeHoverTrigger !== "" && !_hitTargetsActivePopout(hit)) {
            if (!managerOwnsTransition) {
                _beginSupersededCloseForActive();
                closeHoverSurfaces();
            }
        }

        if (!openHoverPopoutForHit(hit)) {
            if (activeHoverTrigger !== "")
                closeHoverSurfaces();
            return;
        }

        activeHoverTrigger = triggerKey;
    }

    function scheduleHoverClose(gx, gy) {
        cancelQueuedHitTest();
        _cancelPendingHover();
        if (!hoverPopoutsEnabled)
            return;
        if (!hasOpenHoverSurface())
            return;
        if (isActiveHoverSurfacePinned())
            return;
        if (cursorOverHoverChain(gx, gy, barWindow?.hostWindow ?? null))
            return;
        _hoverCloseTimer.restart();
    }

    function _triggerKeyForHit(hit, gx, gy) {
        if (hit.widgetId === "systemTray")
            return hit.widgetItem.hoverTriggerAtGlobalPoint?.(gx, gy) || "";
        const dashTab = _hoverSpecs[hit.widgetId]?.dashTab;
        return dashTab ? dashTriggerSource(hit.section, dashTab) : hit.widgetId;
    }

    function _cursorRestsOnActiveTrigger(gx, gy) {
        if (activeHoverTrigger === "")
            return false;
        const hit = findWidgetAtGlobalPoint(gx, gy);
        if (!hit)
            return false;
        return _triggerKeyForHit(hit, gx, gy) === activeHoverTrigger;
    }

    function _commitHoverClose() {
        const gx = PopoutManager.hoverCursorGlobalX;
        const gy = PopoutManager.hoverCursorGlobalY;
        if (isActiveHoverSurfacePinned())
            return;
        // A popout surface mapping can pull pointer focus off the bar on Hyprland; a leave
        // with the cursor still resting on the trigger widget is not a real exit (#3248).
        if (_cursorRestsOnActiveTrigger(gx, gy))
            return;
        if (cursorOverHoverChain(gx, gy, barWindow?.hostWindow ?? null))
            return;
        closeHoverSurfaces();
    }
}
