import QtQuick
import qs.Common
import qs.Services

Item {
    id: root
    readonly property var log: Log.scoped("DPopout")

    property string layerNamespace: "dms:popout"
    property Component content: null
    property Component overlayContent: null
    property real popupWidth: 400
    property real popupHeight: 300
    property real triggerX: 0
    property real triggerY: 0
    property real triggerWidth: 40
    property string triggerSection: ""
    property string positioning: "center"
    property int animationDuration: Theme.popoutAnimationDuration
    property real animationScaleCollapsed: Theme.effectScaleCollapsed
    property real animationOffset: Theme.effectAnimOffset
    property list<real> animationEnterCurve: Theme.variantPopoutEnterCurve
    property list<real> animationExitCurve: Theme.variantPopoutExitCurve
    property list<real> resizeCurve: Theme.variantPopoutResizeCurve
    property int resizeDuration: animationDuration
    property bool resizeMotion: false
    property bool resizing: false
    property real surfacePadding: 0
    // Content hung outside the surface, kept on screen, blurred and clickable.
    property real bottomOverflow: 0
    property real topOverflow: 0
    property real inputMargin: 0
    property bool suspendShadowWhileResizing: false
    property bool shouldBeVisible: false
    property bool hoverDismissEnabled: false
    property bool hoverDismissSuspended: false
    property var customKeyboardFocus: null
    readonly property alias transientSurfaceTracker: _transientSurfaceTracker
    readonly property bool effectiveHoverDismissSuspended: hoverDismissSuspended || (transientSurfaceTracker?.active ?? false)
    property bool backgroundInteractive: true
    property bool contentHandlesKeys: false
    property bool fullHeightSurface: false
    property real minimumSurfaceWidth: 0
    property bool _primeContent: false
    property bool _warmContent: false

    property real storedBarThickness: Theme.barThickness(SettingsData.getPrimaryBarConfig()?.innerPadding ?? SettingsData.barInnerPaddingDefault, 1)
    property real storedBarSpacing: 4
    property var storedBarConfig: null
    property var sourceRegistration: null
    property bool closesWithSource: true
    readonly property bool sourceActive: !sourceRegistration || BarWidgetService.registrationActive(sourceRegistration)
    onSourceActiveChanged: if (!sourceActive && closesWithSource)
        close()
    property var sourceDock: null
    readonly property var inlineDockBounds: storedBarConfig?.widgetExpansion === "inline" ? sourceDock?.surfaceBounds ?? null : null
    property bool triggerUsesOverlayLayer: false
    property var adjacentBarInfo: ({
            "topBar": 0,
            "bottomBar": 0,
            "leftBar": 0,
            "rightBar": 0
        })
    property var screen: null
    property int effectiveBarPosition: 0
    property real effectiveBarBottomGap: 0

    signal opened
    signal popoutClosed
    signal closeAnimationFinished
    signal backgroundClicked

    readonly property var contentLoader: impl.item ? impl.item.contentLoader : _fallbackContentLoader
    readonly property var overlayLoader: impl.item ? impl.item.overlayLoader : _fallbackOverlayLoader
    readonly property var backgroundWindow: impl.item ? impl.item.backgroundWindow : null
    readonly property var contentWindow: impl.item ? impl.item.contentWindow : null

    TransientSurfaceTracker {
        id: _transientSurfaceTracker
    }

    // Hyprland OnDemand grab: whitelist popout surfaces and bars so dismiss clicks still land.
    DFocusGrab {
        windows: {
            const list = root.contentWindow ? [root.contentWindow] : [];
            const transientWindows = root.transientSurfaceTracker?.focusWindows ?? [];
            if (!(impl.item?.contentActive ?? false) && !root.transientSurfaceTracker?.active)
                return list.concat(transientWindows);
            if (root.backgroundWindow && root.backgroundWindow !== root.contentWindow)
                list.push(root.backgroundWindow);
            return list.concat(transientWindows).concat(KeyboardFocus.barWindows);
        }
        wanted: KeyboardFocus.wantsGrab(root.shouldBeVisible, root.customKeyboardFocus)
    }

    Loader {
        id: _fallbackContentLoader
        active: false
    }
    Loader {
        id: _fallbackOverlayLoader
        active: false
    }
    readonly property bool isClosing: impl.item ? (impl.item.isClosing ?? false) : false
    readonly property real dpr: impl.item ? impl.item.dpr : 1
    readonly property color surfaceColor: impl.item?.usesConnectedSurfaceChrome ? Theme.connectedSurfaceColor : Theme.readableSurface
    readonly property real screenWidth: impl.item ? impl.item.screenWidth : 0
    readonly property real screenHeight: impl.item ? impl.item.screenHeight : 0
    readonly property real alignedX: impl.item ? impl.item.alignedX : 0
    readonly property real alignedY: impl.item ? impl.item.alignedY : 0
    readonly property real alignedWidth: impl.item ? impl.item.alignedWidth : 0
    readonly property real alignedHeight: impl.item ? impl.item.alignedHeight : 0
    readonly property real renderedAlignedX: impl.item ? (impl.item.renderedAlignedX ?? impl.item.alignedX) : 0
    readonly property real renderedAlignedY: impl.item ? (impl.item.renderedAlignedY ?? impl.item.alignedY) : 0
    readonly property real renderedAlignedWidth: impl.item ? (impl.item.renderedAlignedWidth ?? impl.item.alignedWidth) : 0
    readonly property real renderedAlignedHeight: impl.item ? (impl.item.renderedAlignedHeight ?? impl.item.alignedHeight) : 0
    readonly property real maxBodyWidth: impl.item ? impl.item.maxBodyWidth : 0
    readonly property real maxBodyHeight: impl.item ? impl.item.maxBodyHeight : 0

    function alignedXFor(width) {
        return impl.item?.alignedXFor(width) ?? 0;
    }

    function alignedYFor(overTop, overBottom) {
        return impl.item?.alignedYFor(overTop, overBottom) ?? 0;
    }
    readonly property vector4d surfaceCornerRadii: impl.item?.surfaceCornerRadii ?? Qt.vector4d(Theme.windowRadius, Theme.windowRadius, Theme.windowRadius, Theme.windowRadius)
    readonly property real maskX: impl.item ? impl.item.maskX : 0
    readonly property real maskY: impl.item ? impl.item.maskY : 0
    readonly property real maskWidth: impl.item ? impl.item.maskWidth : 0
    readonly property real maskHeight: impl.item ? impl.item.maskHeight : 0
    readonly property real barX: impl.item ? impl.item.barX : 0
    readonly property real barY: impl.item ? impl.item.barY : 0
    readonly property real barWidth: impl.item ? impl.item.barWidth : 0
    readonly property real barHeight: impl.item ? impl.item.barHeight : 0
    readonly property bool useConnectedBackend: _usesConnectedBackendForScreen(screen)
    property bool _resolvedConnected: false
    property bool _pendingOpen: false

    Timer {
        id: _pendingOpenTimer
        interval: 0
        onTriggered: {
            if (!root._pendingOpen || !impl.item)
                return;
            root._pendingOpen = false;
            impl.item.open();
        }
    }

    onUseConnectedBackendChanged: _maybeResolveBackend()
    Component.onCompleted: _loadHost(_usesConnectedBackendForScreen(screen))

    Connections {
        target: SettingsData
        function onConnectedFrameModeActiveChanged() {
            root._maybeResolveBackend();
        }
        function onFrameEnabledChanged() {
            root._maybeResolveBackend();
        }
        function onFrameScreenPreferencesChanged() {
            root._maybeResolveBackend();
        }
        function onDockConfigsChanged() {
            root._maybeResolveBackend();
        }
        function onBarConfigsChanged() {
            root._maybeResolveBackend();
        }
    }

    function _usesConnectedBackendForScreen(targetScreen) {
        return CompositorService.usesConnectedFrameChromeForScreen(targetScreen);
    }

    function _maybeResolveBackend() {
        _resolveBackendForScreen(screen);
    }

    function _resolveBackendForScreen(targetScreen) {
        const connected = _usesConnectedBackendForScreen(targetScreen);
        if (_resolvedConnected === connected)
            return;
        if (impl.item && (impl.item.shouldBeVisible || impl.item.isClosing))
            return;
        _loadHost(connected);
    }

    function _loadHost(connected) {
        impl.sourceComponent = null;
        _resolvedConnected = connected;
        impl.sourceComponent = hostComponent;
    }

    function open() {
        _maybeResolveBackend();
        if (impl.item) {
            _pendingOpen = false;
            impl.item.open();
            return;
        }
        _pendingOpen = true;
    }

    function close() {
        _close(false);
    }

    function instantClose() {
        _close(true);
    }

    function _close(instant) {
        _pendingOpen = false;
        _pendingOpenTimer.stop();
        transientSurfaceTracker?.closeAll?.();
        if (impl.item) {
            instant ? impl.item.instantClose() : impl.item.close();
            return;
        }
        PopoutManager.hidePopout(root);
        if (!shouldBeVisible)
            return;
        shouldBeVisible = false;
        popoutClosed();
    }

    function cancelHoverDismiss() {
        if (impl.item?.cancelHoverDismiss)
            impl.item.cancelHoverDismiss();
    }

    // Fade out in place during morph switch transitions.
    function beginSupersededClose() {
        if (impl.item)
            impl.item.beginSupersededClose();
    }

    function closeFromHoverDismiss() {
        if (effectiveHoverDismissSuspended)
            return;
        transientSurfaceTracker?.closeAll?.();
        hoverDismissEnabled = false;
        // Enable animations using standard Theme-bound popout motion to preserve bindings.
        if (impl.item)
            impl.item.animationsEnabled = true;
        for (const prop of ["dashVisible", "notificationHistoryVisible"]) {
            if (root[prop] !== undefined) {
                root[prop] = false;
                return;
            }
        }
        if (impl.item)
            impl.item.close();
        else
            close();
    }

    function toggle() {
        (shouldBeVisible || _pendingOpen) ? close() : open();
    }

    function setBarContext(position, bottomGap) {
        effectiveBarPosition = position !== undefined ? position : 0;
        effectiveBarBottomGap = bottomGap !== undefined ? bottomGap : 0;
    }

    function _triggerBarUsesOverlayLayer(targetScreen, barConfig) {
        const frameHostsBar = CompositorService.frameHostsBarForConfig(targetScreen, barConfig);
        const frameRequiresOverlay = CompositorService.framePeerSurfacesUseOverlayForScreen(targetScreen) && !frameHostsBar;
        return LayerShell.envUsesOverlay("DMS_DANKBAR_LAYER", (barConfig?.useOverlayLayer ?? false) || frameRequiresOverlay);
    }

    function dockClearance(side, popupGap) {
        if (!screen)
            return 0;
        const reserved = SettingsData.dockReservationForEdge(screen, side);
        const frameInset = CompositorService.frameWindowVisibleForScreen(screen) ? SettingsData.frameEdgeInsetForSide(screen, side) : 0;
        let clearance = reserved > 0 ? reserved + frameInset : 0;
        if (sourceDock?.config?.enabled && sourceDock.reveal && sourceDock.connectedBarSide === side) {
            const bounds = sourceDock.surfaceBounds;
            switch (side) {
            case "top":
                clearance = Math.max(clearance, bounds.y + bounds.height);
                break;
            case "bottom":
                clearance = Math.max(clearance, screen.height - bounds.y);
                break;
            case "left":
                clearance = Math.max(clearance, bounds.x + bounds.width);
                break;
            case "right":
                clearance = Math.max(clearance, screen.width - bounds.x);
                break;
            }
        }
        return clearance > 0 ? clearance + popupGap : 0;
    }

    function setTriggerPosition(x, y, width, section, targetScreen, barPosition, barThickness, barSpacing, barConfig, sourceItem) {
        sourceRegistration = BarWidgetService.registrationForItem(sourceItem);
        sourceDock = null;
        for (let item = sourceItem; item; item = item.parent) {
            if (item.surfaceContext?.kind !== "dock")
                continue;
            sourceDock = item.surfaceContext.host;
            break;
        }
        if (barConfig?.widgetExpansion === "inline" && sourceDock) {
            const bounds = sourceDock.surfaceBounds;
            const gap = CompositorService.usesConnectedFrameChromeForScreen(targetScreen) && !barConfig.useOverlayLayer ? 0 : (barConfig.popupGapsAuto !== false ? Math.max(4, barSpacing) : barConfig.popupGapsManual ?? 4);
            switch (barPosition) {
            case SettingsData.Position.Top:
                y = bounds.y + bounds.height + gap;
                break;
            case SettingsData.Position.Bottom:
                y = bounds.y - gap;
                break;
            case SettingsData.Position.Left:
                x = bounds.x + bounds.width + gap;
                break;
            case SettingsData.Position.Right:
                x = bounds.x - gap;
                break;
            }
        }
        if (barConfig?.widgetExpansion === "popout" && targetScreen) {
            const anchor = BarWidgetService.naturalPopoutAnchor(targetScreen, sourceItem, section);
            if (!anchor)
                return;
            x = anchor.trigger.x;
            y = anchor.trigger.y;
            width = anchor.trigger.width;
            section = anchor.section;
            barPosition = anchor.position;
            barThickness = anchor.thickness;
            barSpacing = anchor.spacing;
            barConfig = anchor.config;
        }
        triggerX = x;
        triggerY = y;
        triggerWidth = width;
        triggerSection = section;
        screen = targetScreen;

        storedBarThickness = barThickness !== undefined ? barThickness : Theme.barThickness(SettingsData.getPrimaryBarConfig()?.innerPadding ?? SettingsData.barInnerPaddingDefault, 1);
        storedBarSpacing = barSpacing !== undefined ? barSpacing : 4;
        storedBarConfig = barConfig;
        triggerUsesOverlayLayer = _triggerBarUsesOverlayLayer(targetScreen, barConfig);

        const pos = barPosition !== undefined ? barPosition : 0;
        const bottomGap = barConfig ? (barConfig.bottomGap !== undefined ? barConfig.bottomGap : 0) : 0;

        adjacentBarInfo = SettingsData.getAdjacentBarInfo(targetScreen, pos, barConfig);
        setBarContext(pos, bottomGap);
        _resolveBackendForScreen(targetScreen);
    }

    function updateSurfacePosition() {
        if (impl.item)
            impl.item.updateSurfacePosition();
    }

    function containsGlobalPoint(gx, gy) {
        if (!screen)
            return false;
        const presented = shouldBeVisible || (impl.item?.isClosing ?? false);
        if (!presented)
            return false;
        const padding = 24;
        const x = renderedAlignedX - padding;
        const y = renderedAlignedY - padding;
        const w = renderedAlignedWidth + padding * 2;
        const h = renderedAlignedHeight + padding * 2;
        return gx >= x && gx <= x + w && gy >= y && gy <= y + h;
    }

    Loader {
        id: impl
        active: root.screen !== null
        onItemChanged: if (item)
            root._wireBackend(item)
    }

    Component {
        id: hostComponent
        DPopoutHost {
            id: host

            popoutHandle: root
            connected: root._resolvedConnected

            onShouldBeVisibleChanged: {
                if (root.shouldBeVisible !== host.shouldBeVisible)
                    root.shouldBeVisible = host.shouldBeVisible;
            }
            onOpened: root.opened()
            onCloseAnimationFinished: root.closeAnimationFinished()
            onPopoutClosed: {
                root.popoutClosed();
                root._maybeResolveBackend();
            }
            onBackgroundClicked: root.backgroundClicked()
        }
    }

    function _wireBackend(it) {
        if (root.shouldBeVisible && !_pendingOpen)
            root.shouldBeVisible = false;
        if (root._primeContent)
            it.primeContent();
        if (root._warmContent)
            it.warmContent();
        if (_pendingOpen)
            _pendingOpenTimer.restart();
    }

    function primeContent() {
        _primeContent = true;
        if (impl.item)
            impl.item.primeContent();
    }

    function clearPrimedContent() {
        _primeContent = false;
        if (impl.item)
            impl.item.clearPrimedContent();
    }

    function warmContent() {
        _warmContent = true;
        if (impl.item)
            impl.item.warmContent();
    }

    onShouldBeVisibleChanged: {
        if (!shouldBeVisible)
            transientSurfaceTracker?.closeAll?.();
        if (impl.item && impl.item.shouldBeVisible !== shouldBeVisible)
            impl.item.shouldBeVisible = shouldBeVisible;
    }
}
