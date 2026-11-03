pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../Common/ConnectedSurfaceGeometry.js" as SurfaceGeometry
import "../Common/FluidGeometry.js" as FluidGeometry

Item {
    id: root
    readonly property var log: Log.scoped("DPopoutHost")

    required property var popoutHandle
    property bool connected: true
    readonly property bool fluidMotionEnabled: Theme.isFluidEffect && (!connected || frameOwnsConnectedChrome)
    property bool _fluidMotionActive: false
    property string layerNamespace: popoutHandle.layerNamespace
    property alias content: contentLoader.sourceComponent
    property alias contentLoader: contentLoader
    property Component overlayContent: popoutHandle.overlayContent
    property alias overlayLoader: overlayLoader
    readonly property var backgroundWindow: connected ? contentWindow : (backgroundLayer.item?.window ?? null)
    readonly property alias contentWindow: contentWindow
    property real popupWidth: popoutHandle.popupWidth
    property real popupHeight: popoutHandle.popupHeight
    property list<real> resizeCurve: popoutHandle.resizeCurve
    property int resizeDuration: popoutHandle.resizeDuration
    property bool resizeMotion: popoutHandle.resizeMotion
    property bool resizing: popoutHandle.resizing
    property real bottomOverflow: popoutHandle.bottomOverflow
    property real topOverflow: popoutHandle.topOverflow
    property real inputMargin: popoutHandle.inputMargin
    property real triggerX: popoutHandle.triggerX
    property real triggerY: popoutHandle.triggerY
    property real triggerWidth: popoutHandle.triggerWidth
    property string triggerSection: popoutHandle.triggerSection
    property string positioning: popoutHandle.positioning
    property int animationDuration: popoutHandle.animationDuration
    property real animationScaleCollapsed: popoutHandle.animationScaleCollapsed
    property real animationOffset: popoutHandle.animationOffset
    property list<real> animationEnterCurve: popoutHandle.animationEnterCurve
    property list<real> animationExitCurve: popoutHandle.animationExitCurve
    property bool suspendShadowWhileResizing: popoutHandle.suspendShadowWhileResizing
    property bool shouldBeVisible: false
    property bool _presentPending: false
    property bool _surfaceFrameReady: false
    property var customKeyboardFocus: popoutHandle.customKeyboardFocus
    property bool backgroundInteractive: popoutHandle.backgroundInteractive
    property bool contentHandlesKeys: popoutHandle.contentHandlesKeys
    property bool fullHeightSurface: popoutHandle.fullHeightSurface
    property real minimumSurfaceWidth: popoutHandle.minimumSurfaceWidth
    property bool _primeContent: false
    property bool _contentWarm: false
    property bool _backgroundWarm: false
    property bool _contentRenderActive: Theme.isDirectionalEffect || shouldBeVisible
    // Keyboard focus grabbed one tick after emerge starts, to avoid stalling first frames.
    property bool _keyboardReady: false
    readonly property bool contentActive: focusHelper.Window.active
    property bool _resizeActive: false
    property real _chromeAnimTravelX: 1
    property real _chromeAnimTravelY: 1
    property bool _fullSyncQueued: false
    property bool _publishedBodyValid: false
    property real _publishedBodyX: 0
    property real _publishedBodyY: 0
    property real _publishedBodyW: 0
    property real _publishedBodyH: 0
    property real _surfaceX: 0
    property real _surfaceY: 0
    property real _surfaceW: 0
    property real _surfaceH: 0
    property bool _anchorEndX: false
    property bool _anchorEndY: false
    property var _pendingSurfaceX: null
    property var _pendingSurfaceY: null
    property real _surfaceBodyX: 0
    property real _surfaceBodyY: 0
    property real _surfaceBodyW: 0
    property real _surfaceBodyH: 0

    property real storedBarThickness: popoutHandle.storedBarThickness
    property real storedBarSpacing: popoutHandle.storedBarSpacing
    property var storedBarConfig: popoutHandle.storedBarConfig
    property bool triggerUsesOverlayLayer: popoutHandle.triggerUsesOverlayLayer
    property var adjacentBarInfo: popoutHandle.adjacentBarInfo
    property var screen: popoutHandle.screen
    property var surfaceScreen: null
    readonly property bool frameGapStandaloneActive: CompositorService.frameConfiguredForScreen(screen) && !CompositorService.usesConnectedFrameChromeForScreen(screen)
    readonly property bool directionalRevealActive: Theme.isDirectionalEffect
    readonly property var effectivePopoutLayer: LayerShell.fromEnv("DMS_POPOUT_LAYER", root.triggerUsesOverlayLayer ? WlrLayer.Overlay : WlrLayer.Top, {
        "allow": ["top", "overlay"],
        "invalidLayer": WlrLayer.Top,
        "label": "popouts"
    })

    readonly property real effectiveBarThickness: {
        if (root.usesConnectedSurfaceChrome)
            return Math.max(0, storedBarThickness);
        return Theme.barThickness(storedBarConfig?.innerPadding ?? SettingsData.barInnerPaddingDefault, dpr) + storedBarSpacing;
    }

    readonly property var barBounds: {
        const dockBounds = connected ? popoutHandle?.inlineDockBounds : null;
        if (dockBounds)
            return {
                x: dockBounds.x,
                y: dockBounds.y,
                width: dockBounds.width,
                height: dockBounds.height,
                wingSize: 0
            };
        if (!screen)
            return {
                "x": 0,
                "y": 0,
                "width": 0,
                "height": 0,
                "wingSize": 0
            };
        return SettingsData.getBarBounds(screen, effectiveBarThickness, effectiveBarPosition, storedBarConfig);
    }

    readonly property real barX: barBounds.x
    readonly property real barY: barBounds.y
    readonly property real barWidth: barBounds.width
    readonly property real barHeight: barBounds.height
    readonly property real barWingSize: barBounds.wingSize

    signal opened
    signal popoutClosed
    signal closeAnimationFinished
    signal backgroundClicked

    Timer {
        id: _syncTimer
        interval: 0
        onTriggered: root._flushSync()
    }

    ConnectedSurfaceLease {
        id: chromeLease
        claimPrefix: root.layerNamespace
        screenName: root.screen ? root.screen.name : ""
        enabled: root.frameOwnsConnectedChrome
        active: contentWindow.visible || root.shouldBeVisible
        presented: contentWindow.visible || root.shouldBeVisible
        renewTokenOnRecovery: false
        slot: "popout"
        exclusive: true
        requirePresentedState: true
        isCurrentOwner: name => PopoutManager.isCurrentPopout(root.popoutHandle, name)
        onClaimIdChanged: root._resetPublishedBody()
        onRecoveryRequested: {
            root._resetPublishedBody();
            root._queueFullSync();
        }
    }

    property var _lastOpenedScreen: null
    readonly property var _openScreen: connected ? _lastOpenedScreen : surfaceScreen
    property bool isClosing: false

    property int effectiveBarPosition: popoutHandle.effectiveBarPosition
    property real effectiveBarBottomGap: popoutHandle.effectiveBarBottomGap
    readonly property string autoBarShadowDirection: {
        const section = triggerSection || "center";
        switch (effectiveBarPosition) {
        case SettingsData.Position.Top:
            if (section === "left")
                return "topLeft";
            if (section === "right")
                return "topRight";
            return "top";
        case SettingsData.Position.Bottom:
            if (section === "left")
                return "bottomLeft";
            if (section === "right")
                return "bottomRight";
            return "bottom";
        case SettingsData.Position.Left:
            if (section === "left")
                return "topLeft";
            if (section === "right")
                return "bottomLeft";
            return "left";
        case SettingsData.Position.Right:
            if (section === "left")
                return "topRight";
            if (section === "right")
                return "bottomRight";
            return "right";
        default:
            return "top";
        }
    }
    readonly property string effectiveShadowDirection: Theme.elevationLightDirection === "autoBar" ? autoBarShadowDirection : Theme.elevationLightDirection

    function primeContent() {
        _primeContent = true;
    }

    function clearPrimedContent() {
        _primeContent = false;
    }

    function warmContent() {
        _backgroundWarm = true;
        _contentWarm = true;
    }

    function _captureChromeAnimTravel() {
        _chromeAnimTravelX = Math.max(1, Math.abs(contentContainer.offsetX));
        _chromeAnimTravelY = Math.max(1, Math.abs(contentContainer.offsetY));
    }

    function _connectedChromeAnimX() {
        const barSide = contentContainer.connectedBarSide;
        if (barSide !== "left" && barSide !== "right")
            return contentContainer.animX;

        const extent = Math.max(0, root.pubBodyW);
        const progress = Math.min(1, Math.abs(contentContainer.animX) / Math.max(1, _chromeAnimTravelX));
        const offset = Theme.snap(extent * progress, root.dpr);
        return contentContainer.animX < 0 ? -offset : offset;
    }

    function _connectedChromeAnimY() {
        const barSide = contentContainer.connectedBarSide;
        if (barSide !== "top" && barSide !== "bottom")
            return contentContainer.animY;

        const extent = Math.max(0, root.pubBodyH + root.topOverflow + root.bottomOverflow);
        const progress = Math.min(1, Math.abs(contentContainer.animY) / Math.max(1, _chromeAnimTravelY));
        const offset = Theme.snap(extent * progress, root.dpr);
        return contentContainer.animY < 0 ? -offset : offset;
    }

    function _connectedChromeState(visibleOverride) {
        // Track intent rather than the transient wl_surface state during remap.
        const visible = visibleOverride !== undefined ? !!visibleOverride : (contentWindow.visible || root.shouldBeVisible);
        const presented = contentWindow.visible || root.shouldBeVisible;
        const phase = root.isClosing ? "closing" : (!presented ? "hidden" : (!contentWindow.visible && root.shouldBeVisible ? "opening" : "open"));
        const bodyX = Theme.snap(root.pubBodyX, root.dpr);
        const bodyY = Theme.snap(root.pubBodyY, root.dpr);
        const bodyW = Theme.snap(root.pubBodyW, root.dpr);
        const bodyH = Theme.snap(root.pubBodyH, root.dpr);
        const bodyRect = {
            "x": bodyX,
            "y": bodyY,
            "width": bodyW,
            "height": bodyH
        };
        const animationOffset = {
            "x": _connectedChromeAnimX(),
            "y": _connectedChromeAnimY()
        };
        return {
            "kind": "popout",
            "screenName": root.screen ? root.screen.name : "",
            "phase": phase,
            "visible": visible,
            "presented": presented,
            "layer": root.effectivePopoutLayer === WlrLayer.Overlay ? "overlay" : "top",
            "barSide": contentContainer.connectedBarSide,
            "bodyRect": bodyRect,
            "animationOffset": animationOffset,
            "scale": 1,
            "opacity": Theme.connectedSurfaceColor.a,
            "bodyX": bodyX,
            "bodyY": bodyY,
            "bodyW": bodyW,
            "bodyH": bodyH,
            "animX": animationOffset.x,
            "animY": animationOffset.y,
            "screen": root.screen ? root.screen.name : "",
            "omitStartConnector": root._closeGapOmitStartConnector(),
            "omitEndConnector": root._closeGapOmitEndConnector(),
            "overflowTop": Theme.snap(root.topOverflow, root.dpr),
            "overflowBottom": Theme.snap(root.bottomOverflow, root.dpr)
        };
    }

    function _publishConnectedChromeState(forceClaim, visibleOverride) {
        if (!root.frameOwnsConnectedChrome || !root.screen)
            return false;
        const state = _connectedChromeState(visibleOverride);
        const published = chromeLease.publish(state, !!forceClaim);
        if (published)
            _rememberPublishedBody(state.bodyX, state.bodyY, state.bodyW, state.bodyH);
        return published;
    }

    function _releaseConnectedChromeState() {
        _resetPublishedBody();
        chromeLease.release();
    }

    function _claimConnectedChrome() {
        if (!root.frameOwnsConnectedChrome) {
            chromeLease.release();
            return;
        }
        chromeLease.beginClaim();
        _publishConnectedChromeState(true, true);
    }

    function _syncPopoutChromeState() {
        if (!root.frameOwnsConnectedChrome) {
            _releaseConnectedChromeState();
            return;
        }
        if (!root.screen) {
            _releaseConnectedChromeState();
            return;
        }
        if (!contentWindow.visible && !shouldBeVisible)
            return;
        _publishConnectedChromeState(false);
    }

    function _syncPopoutAnim(axis) {
        if (!root.frameOwnsConnectedChrome || !chromeLease.claimId)
            return;
        if (!contentWindow.visible && !shouldBeVisible)
            return;
        const barSide = contentContainer.connectedBarSide;
        const syncX = axis === "x" && (barSide === "left" || barSide === "right");
        const syncY = axis === "y" && (barSide === "top" || barSide === "bottom");
        if (!syncX && !syncY)
            return;
        chromeLease.updateAnim(syncX ? _connectedChromeAnimX() : undefined, syncY ? _connectedChromeAnimY() : undefined);
    }

    function _syncPopoutBody() {
        if (!root.frameOwnsConnectedChrome || !chromeLease.claimId)
            return;
        if (!contentWindow.visible && !shouldBeVisible)
            return;
        const body = root.morphTravelEnabled ? root._boundTravel(travelSpring.value) : root.travelTarget;
        const bodyX = Theme.snap(body.x, root.dpr);
        const bodyY = Theme.snap(body.y, root.dpr);
        const bodyW = Theme.snap(body.width, root.dpr);
        const bodyH = Theme.snap(body.height, root.dpr);
        if (_publishedBodyValid && _publishedBodyX === bodyX && _publishedBodyY === bodyY && _publishedBodyW === bodyW && _publishedBodyH === bodyH)
            return;
        if (chromeLease.updateBody(bodyX, bodyY, bodyW, bodyH))
            _rememberPublishedBody(bodyX, bodyY, bodyW, bodyH);
        if (morph.running)
            _syncPopoutAnim(contentContainer.barLeft || contentContainer.barRight ? "x" : "y");
    }

    function _rememberPublishedBody(bodyX, bodyY, bodyW, bodyH) {
        _publishedBodyX = bodyX;
        _publishedBodyY = bodyY;
        _publishedBodyW = bodyW;
        _publishedBodyH = bodyH;
        _publishedBodyValid = true;
    }

    function _resetPublishedBody() {
        _publishedBodyValid = false;
    }

    function _queueFullSync() {
        if (!connected)
            return;
        _fullSyncQueued = true;
        if (!_syncTimer.running)
            _syncTimer.restart();
    }
    function _flushSync() {
        if (!_fullSyncQueued)
            return;
        _fullSyncQueued = false;
        _syncPopoutChromeState();
    }

    readonly property bool settingsConnectedFrameModeActive: SettingsData.connectedFrameModeActive
    readonly property bool settingsFrameCloseGaps: SettingsData.frameCloseGaps
    readonly property var connectedSurfaceDescriptors: ConnectedModeState.surfaceDescriptors

    function _syncAlignedGeometry() {
        if (connected) {
            _queueFullSync();
            return;
        }
        _setAnimatedSurfaceEnvelope();
    }

    onAlignedXChanged: _syncAlignedGeometry()
    onAlignedYChanged: {
        _retargetBody();
        _syncAlignedGeometry();
    }
    onAlignedWidthChanged: {
        _retargetBody();
        _syncAlignedGeometry();
    }
    onConnectedChanged: {
        if (!connected)
            _setAnimatedSurfaceEnvelope();
        _surfaceSwitching = contentWindow.visible && Math.abs(contentWindow.width - (connected ? screenWidth : _surfaceW)) > 1;
    }
    property bool _surfaceSwitching: false
    readonly property real _contentWindowWidth: contentWindow.width
    readonly property real _contentWindowHeight: contentWindow.height
    on_ContentWindowWidthChanged: {
        _surfaceSwitching = false;
        _flushPendingSurface("x", false);
    }
    on_ContentWindowHeightChanged: _flushPendingSurface("y", false)
    onResizingChanged: {
        if (!resizing)
            backgroundLayer.item?.surfaceMoved();
    }
    onScreenChanged: {
        if (!connected)
            return;
        _resetPublishedBody();
        _queueFullSync();
    }
    onEffectiveBarPositionChanged: {
        if (!connected)
            return;
        _queueFullSync();
    }
    onFrameOwnsConnectedChromeChanged: {
        if (!connected)
            return;
        _syncPopoutChromeState();
    }

    onSurfaceBodyWidthChanged: {
        if (connected)
            return;
        _setAnimatedSurfaceEnvelope();
    }

    Timer {
        id: surfaceStepTimerX
        interval: 100
        onTriggered: root._flushPendingSurface("x", true)
    }

    Timer {
        id: surfaceStepTimerY
        interval: 100
        onTriggered: root._flushPendingSurface("y", true)
    }

    onSettingsConnectedFrameModeActiveChanged: {
        if (!connected)
            return;
        if (frameOwnsConnectedChrome) {
            if ((contentWindow.visible || shouldBeVisible) && screen && PopoutManager.isCurrentPopout(popoutHandle, screen.name))
                _publishConnectedChromeState(true);
        } else {
            _releaseConnectedChromeState();
        }
    }
    onSettingsFrameCloseGapsChanged: {
        if (!connected)
            return;
        _syncPopoutChromeState();
    }
    onTopOverflowChanged: {
        if (!connected)
            return;
        _syncPopoutChromeState();
    }
    onBottomOverflowChanged: {
        if (!connected)
            return;
        _syncPopoutChromeState();
    }
    onConnectedSurfaceDescriptorsChanged: {
        if (!connected)
            return;
        chromeLease.checkRecovery();
    }

    Connections {
        target: PopoutManager
        enabled: root.connected
        function onPopoutChanged() {
            chromeLease.requestRecovery();
        }
    }

    property bool _overStackedModal: false
    readonly property bool frameOwnsConnectedChrome: connected && !_overStackedModal && effectivePopoutLayer === WlrLayer.Top && CompositorService.canShareConnectedFrameChromeForScreen(root.screen)
    readonly property bool usesConnectedSurfaceChrome: connected && Theme.isConnectedEffect
    readonly property bool usesLocalConnectedSurfaceChrome: usesConnectedSurfaceChrome && !frameOwnsConnectedChrome

    property bool animationsEnabled: true
    property bool hoverDismissEnabled: popoutHandle.hoverDismissEnabled
    property bool hoverDismissSuspended: popoutHandle.effectiveHoverDismissSuspended

    function cancelHoverDismiss() {
        hoverDismissController.cancelPending();
    }

    function closeFromHoverDismiss() {
        if (hoverDismissSuspended || isClosing || !shouldBeVisible)
            return;
        if (popoutHandle?.closeFromHoverDismiss)
            popoutHandle.closeFromHoverDismiss();
        else
            close();
    }

    DeferredAction {
        id: showSurfaceAction
        onTriggered: {
            if (!root.screen || !(root.shouldBeVisible || root._presentPending))
                return;
            root.surfaceScreen = root.screen;
            if (backgroundLayer.item)
                backgroundLayer.item.show();
            contentWindow.visible = true;
            chromeLoader.item.blur.kick();
            root._setSettledSurfaceGeometry();
        }
    }

    function _canPreserveMotion() {
        if (!contentWindow.visible || _openScreen !== screen || _supersededClose)
            return false;
        return !frameOwnsConnectedChrome || ConnectedModeState.hasSurfaceOwner(root.screen.name, "popout", chromeLease.claimId);
    }

    function open() {
        if (!screen)
            return;
        if (!contentWindow.visible || _openScreen !== screen)
            _overStackedModal = ModalManager.hasStackedModal(screen.name);
        const preserveMotion = _canPreserveMotion();
        _resetPublishedBody();
        closeTimer.stop();
        isClosing = false;
        _snapBody();
        if (!preserveMotion) {
            animationsEnabled = false;
            _fluidMotionActive = fluidMotionEnabled;
        }
        _primeContent = true;
        _contentWarm = true;
        _supersededClose = false;

        if (_openScreen !== null && _openScreen !== screen)
            contentWindow.visible = false;
        if (!contentWindow.visible) {
            _anchorEndX = surfaceBodyX + surfaceBodyWidth / 2 > screenWidth / 2;
            _anchorEndY = !fullHeightSurface && alignedY + alignedHeight / 2 > screenHeight / 2;
        }
        _lastOpenedScreen = screen;
        if (connected)
            PopoutManager.showPopout(popoutHandle);

        if (!shouldBeVisible && !preserveMotion)
            morph.retarget(0);
        _captureChromeAnimTravel();

        if (!preserveMotion)
            _beginMorphTravel();

        if (morphTravelEnabled && !preserveMotion)
            morph.retarget(1);

        _claimConnectedChrome();
        _setSurfaceGeometry(surfaceBodyX, alignedY, surfaceBodyWidth, alignedHeight);

        if (!contentWindow.visible)
            showSurfaceAction.schedule();

        animationsEnabled = true;
        if (!connected && !_surfaceFrameReady) {
            _presentPending = true;
            return;
        }
        _present();
    }

    function _present() {
        _presentPending = false;
        shouldBeVisible = true;
        _setSettledSurfaceGeometry();
        if (morphTravelEnabled)
            _retargetMorphTravel();
        Qt.callLater(() => {
            if (root.shouldBeVisible)
                root._keyboardReady = true;
        });
        if (!connected)
            PopoutManager.showPopout(popoutHandle);
        opened();
    }

    on_SurfaceFrameReadyChanged: {
        if (_surfaceFrameReady && _presentPending)
            _present();
    }

    function close() {
        showSurfaceAction.cancel();
        if (!contentWindow.visible || _presentPending) {
            instantClose();
            return;
        }
        if (!connected && _fluidMotionActive && (SettingsData.reduceMotion || animationDuration <= 0)) {
            instantClose();
            return;
        }
        if (_supersededClose && morphTravelEnabled)
            _freezeMorphTravel();
        _resetPublishedBody();
        isClosing = true;
        shouldBeVisible = false;
        _keyboardReady = false;
        _primeContent = false;
        PopoutManager.popoutChanged();
        _retractFluidTravel();
        if (!isClosing)
            return;
        closeTimer.restart();
    }

    function _finishClose() {
        if (shouldBeVisible || !isClosing)
            return;
        closeTimer.stop();
        contentWindow.visible = false;
        morph.snapTo(0);
        _endMorphTravel();
        _fluidMotionActive = false;
        isClosing = false;
        _snapBody();
        PopoutManager.hidePopout(popoutHandle);
        popoutClosed();
    }

    function instantClose() {
        showSurfaceAction.cancel();
        _presentPending = false;
        closeTimer.stop();
        _endMorphTravel();
        _resetPublishedBody();
        animationsEnabled = false;
        isClosing = false;
        shouldBeVisible = false;
        _keyboardReady = false;
        _primeContent = false;
        contentWindow.visible = false;
        _fluidMotionActive = false;
        _snapBody();
        PopoutManager.hidePopout(popoutHandle);
        popoutClosed();
        Qt.callLater(() => animationsEnabled = true);
    }

    function toggle() {
        shouldBeVisible ? close() : open();
    }

    readonly property var quickshellScreens: Quickshell.screens

    onQuickshellScreensChanged: {
        if (!shouldBeVisible || !screen)
            return;
        const currentScreenName = screen.name;
        let screenStillExists = false;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === currentScreenName) {
                screenStillExists = true;
                break;
            }
        }
        if (!screenStillExists) {
            close();
        } else {
            _queueFullSync();
        }
    }

    Timer {
        id: closeTimer
        interval: Math.max(Theme.variantCloseInterval(root.animationDuration), morph.settleDurationMs + 32, root._fluidMotionActive ? travelSpring.settleDurationMs * 2 + 32 : 0)
        onTriggered: root._finishClose()
    }

    Component.onDestruction: _releaseConnectedChromeState()

    readonly property real screenWidth: screen ? screen.width : 0
    readonly property real screenHeight: screen ? screen.height : 0
    // devicePixelRatio rounds to integer under fractional scaling; use the real scale Qt renders at.
    readonly property real dpr: screen ? (CompositorService.getScreenScale(screen) || screen.devicePixelRatio) : 1
    readonly property bool closeFrameGapsActive: SettingsData.frameCloseGaps && frameOwnsConnectedChrome
    readonly property real frameInset: {
        if (!root.frameOwnsConnectedChrome)
            return 0;
        const ft = SettingsData.frameThickness;
        const fr = SettingsData.frameRounding;
        const ccr = Theme.connectedCornerRadius;
        return Math.max(ft * 4, ft + ccr * 2, fr);
    }

    function _popupGapValue() {
        const useAutoGaps = storedBarConfig?.popupGapsAuto !== undefined ? storedBarConfig.popupGapsAuto : true;
        const manualGapValue = storedBarConfig?.popupGapsManual !== undefined ? storedBarConfig.popupGapsManual : 4;
        const rawPopupGap = useAutoGaps ? Math.max(4, storedBarSpacing) : manualGapValue;
        return root.usesConnectedSurfaceChrome ? 0 : rawPopupGap;
    }

    function _frameEdgeInset(side) {
        if (!root.frameOwnsConnectedChrome)
            return 0;
        return Math.max(0, SettingsData.frameEdgeReservation(root.screen, side));
    }

    function _edgeGapFor(side, popupGap) {
        const dockInset = popoutHandle?.dockClearance?.(side, popupGap) ?? 0;
        if (root.closeFrameGapsActive)
            return Math.max(popupGap, _frameEdgeInset(side), dockInset);
        return Math.max(popupGap, frameInset, dockInset);
    }

    function _frameGapMargin(side) {
        return SettingsData.frameEdgeInsetForSide(screen, side) + Theme.popupDistance;
    }

    function _edgeClearance(side, popupGap, adjacentInset) {
        const dockInset = popoutHandle?.dockClearance?.(side, popupGap) ?? 0;
        if (frameGapStandaloneActive)
            return Math.max(adjacentInset, _frameGapMargin(side), dockInset);
        return Math.max(adjacentInset > 0 ? adjacentInset : popupGap, dockInset);
    }

    function _sideAdjacentClearance(side) {
        switch (side) {
        case "left":
            return adjacentBarClearance(adjacentBarInfo.leftBar);
        case "right":
            return adjacentBarClearance(adjacentBarInfo.rightBar);
        case "top":
            return adjacentBarClearance(adjacentBarInfo.topBar);
        case "bottom":
            return adjacentBarClearance(adjacentBarInfo.bottomBar);
        default:
            return 0;
        }
    }

    function _nearFrameBound(value, bound) {
        return Math.abs(value - bound) <= Math.max(1, Theme.hairline(root.dpr) * 2);
    }

    // Snap positions within connector radius flush to the frame edge (avoids pinched arcs).
    function _snapNearFrameBound(value, minBound, maxBound, minIsFrame, maxIsFrame) {
        if (!root.usesConnectedSurfaceChrome || !root.closeFrameGapsActive)
            return value;
        const snapDist = Theme.connectedCornerRadius;
        if (maxIsFrame && value < maxBound && maxBound - value < snapDist && maxBound - value <= value - minBound)
            return maxBound;
        if (minIsFrame && value > minBound && value - minBound < snapDist)
            return minBound;
        return value;
    }

    function _closeGapClampedToFrameSide(side) {
        if (!root.closeFrameGapsActive)
            return false;
        const popupGap = _popupGapValue();
        const edgeGap = _edgeGapFor(side, popupGap);
        const adjacentGap = _sideAdjacentClearance(side);
        if (edgeGap < adjacentGap - Math.max(1, Theme.hairline(root.dpr) * 2))
            return false;

        switch (side) {
        case "left":
            return _nearFrameBound(root.alignedX, edgeGap);
        case "right":
            return _nearFrameBound(root.alignedX, screenWidth - popupWidth - edgeGap);
        case "top":
            return _nearFrameBound(root.alignedY, edgeGap);
        case "bottom":
            return _nearFrameBound(root.alignedY, screenHeight - popupHeight - edgeGap);
        default:
            return false;
        }
    }

    function _closeGapOmitStartConnector() {
        const side = contentContainer.connectedBarSide;
        if (side === "top" || side === "bottom")
            return _closeGapClampedToFrameSide("left");
        return _closeGapClampedToFrameSide("top");
    }

    function _closeGapOmitEndConnector() {
        const side = contentContainer.connectedBarSide;
        if (side === "top" || side === "bottom")
            return _closeGapClampedToFrameSide("right");
        return _closeGapClampedToFrameSide("bottom");
    }

    readonly property var shadowLevel: Theme.elevationLevel2
    readonly property real shadowFallbackOffset: Theme.spacingXS
    readonly property real shadowRenderPadding: (Theme.elevationEnabled && SettingsData.popoutElevationEnabled) ? Theme.elevationRenderPadding(shadowLevel, effectiveShadowDirection, shadowFallbackOffset, 8, 16) : 0
    readonly property real shadowMotionPadding: directionalRevealActive ? 0 : Math.max(0, animationOffset)
    readonly property real shadowBuffer: Theme.snap(Math.max(popoutHandle.surfacePadding, shadowRenderPadding + shadowMotionPadding), dpr)
    readonly property real alignedWidth: Theme.px(popupWidth, dpr)
    readonly property real alignedHeight: Theme.pxCeil(popupHeight, dpr)
    readonly property real surfaceBodyWidth: Math.max(alignedWidth, Theme.px(Math.min(minimumSurfaceWidth, screenWidth), dpr))
    readonly property real surfaceBodyX: Theme.snap(_standaloneAlignedXFor(surfaceBodyWidth), dpr)
    readonly property real _surfaceOriginX: connected ? 0 : _surfaceX
    readonly property real _surfaceOriginY: connected || fullHeightSurface ? 0 : _surfaceY
    readonly property var _geometrySpringParams: Theme.springPreset("default", root.animationDuration)

    readonly property real renderedAlignedX: alignedXFor(renderedAlignedWidth)
    property real renderedAlignedY: alignedY
    property real renderedAlignedWidth: alignedWidth
    property real renderedAlignedHeight: alignedHeight
    // Snap rendered geometry while the entrance morph runs so it doesn't ride a second animation.
    readonly property bool _settlingToOpen: shouldBeVisible && (morph.running || travelSpring.running)
    readonly property bool _geometryMotion: animationsEnabled && !SettingsData.reduceMotion && resizeDuration > 0 && contentWindow.visible && shouldBeVisible && !_settlingToOpen && !resizing
    property real _bodyGlide: 1
    property bool _bodyBatch: false
    property real _bodyFromY: 0
    property real _bodyFromWidth: 0
    property real _bodyFromHeight: 0

    NumberAnimation {
        id: bodyGlide
        target: root
        property: "_bodyGlide"
        from: 0
        to: 1
        duration: root.resizeDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.resizeCurve
    }

    on_BodyGlideChanged: _setBody(_bodyFromY + (alignedY - _bodyFromY) * _bodyGlide, resizeMotion ? _bodyFromWidth + (alignedWidth - _bodyFromWidth) * _bodyGlide : renderedAlignedWidth, _bodyFromHeight + (alignedHeight - _bodyFromHeight) * _bodyGlide)

    // One notification per body change: travelTarget would otherwise fire once per component write.
    function _setBody(y, width, height) {
        if (renderedAlignedY === y && renderedAlignedWidth === width && renderedAlignedHeight === height)
            return;
        _bodyBatch = true;
        renderedAlignedY = y;
        renderedAlignedWidth = width;
        renderedAlignedHeight = height;
        _bodyBatch = false;
        _bodyChanged();
    }

    function _bodyChanged() {
        if (_bodyBatch)
            return;
        if (morphTravelEnabled && shouldBeVisible && !_supersededClose)
            _retargetMorphTravel();
        if (connected)
            _syncPopoutBody();
    }

    on_GeometryMotionChanged: {
        if (_geometryMotion)
            return;
        if (isClosing) {
            bodyGlide.stop();
            return;
        }
        _snapBody();
    }

    function _snapBody() {
        bodyGlide.stop();
        _setBody(alignedY, alignedWidth, alignedHeight);
    }

    function _retargetBody() {
        if (isClosing)
            return;
        if (!resizeMotion)
            _setBody(renderedAlignedY, alignedWidth, renderedAlignedHeight);
        if (!_geometryMotion) {
            _snapBody();
            return;
        }
        if (renderedAlignedY === alignedY && renderedAlignedWidth === alignedWidth && renderedAlignedHeight === alignedHeight) {
            bodyGlide.stop();
            return;
        }
        _bodyFromY = renderedAlignedY;
        _bodyFromWidth = renderedAlignedWidth;
        _bodyFromHeight = renderedAlignedHeight;
        bodyGlide.restart();
    }

    property bool morphTravelEnabled: false
    property bool _travelFromHandoff: false
    readonly property string _travelSpringPreset: _travelFromHandoff ? "fast" : "default"
    readonly property rect travelTarget: Qt.rect(renderedAlignedX, renderedAlignedY, renderedAlignedWidth, renderedAlignedHeight)
    readonly property point _fluidOrigin: connected ? Qt.point(0, 0) : Qt.point(renderedAlignedX, renderedAlignedY)
    readonly property rect fluidTarget: Qt.rect(renderedAlignedX - _fluidOrigin.x, renderedAlignedY - _fluidOrigin.y, renderedAlignedWidth, renderedAlignedHeight)
    readonly property rect fluidCollapsedRect: !_fluidMotionActive ? fluidTarget : FluidGeometry.collapsed(fluidTarget, contentContainer.connectedBarSide, contentContainer.barTop || contentContainer.barBottom ? triggerX + triggerWidth / 2 - _fluidOrigin.x : triggerY - _fluidOrigin.y, triggerWidth)

    RectSpringMotion {
        id: travelSpring
        enabled: root.morphTravelEnabled && root.animationsEnabled
        reducedMotion: root.animationDuration <= 0 || SettingsData.reduceMotion
        positionEpsilon: 0.25 / root.dpr
        velocityEpsilon: positionEpsilon * damping / Math.max(0.001, 2 * mass)
        stiffness: Theme.springPreset(root._travelSpringPreset, root.animationDuration).stiffness
        damping: Theme.springPreset(root._travelSpringPreset, root.animationDuration).damping
        onValueChanged: root._syncPopoutBody()
        onRunningChanged: root._finishMorphTravel()
    }

    function _boundTravel(rect) {
        return _fluidMotionActive && !_travelFromHandoff ? FluidGeometry.limitOvershoot(rect, travelTarget, Theme.fluidOvershootLimit) : rect;
    }
    readonly property rect travelBody: morphTravelEnabled ? _boundTravel(travelSpring.value) : travelTarget
    readonly property real pubBodyX: travelBody.x
    readonly property real pubBodyY: travelBody.y
    readonly property real pubBodyW: travelBody.width
    readonly property real pubBodyH: travelBody.height
    readonly property real fluidContentOpacity: !_fluidMotionActive ? 1 : FluidGeometry.contentOpacity(travelBody, travelTarget)

    onTravelTargetChanged: _bodyChanged()

    function _retargetMorphTravel() {
        travelSpring.retarget(_fluidMotionActive && !shouldBeVisible ? fluidCollapsedRect : travelTarget);
        _finishMorphTravel();
    }

    function _finishMorphTravel() {
        if (!morphTravelEnabled || travelSpring.running || _supersededClose)
            return;
        if (!travelSpring.isSettled(travelSpring.value, travelSpring.velocity))
            return;
        if (shouldBeVisible) {
            _endMorphTravel();
            return;
        }
        if (_fluidMotionActive)
            _finishClose();
    }

    function _beginMorphTravel() {
        morphTravelEnabled = false;
        _travelFromHandoff = false;
        if (!root.frameOwnsConnectedChrome || !root.screen)
            return;
        const handoff = root.hoverDismissEnabled ? ConnectedModeState.takePopoutMotion(root.screen.name, contentContainer.connectedBarSide) : null;
        if (!handoff && !_fluidMotionActive)
            return;
        if (handoff && (handoff.rect.width <= 0 || handoff.rect.height <= 0))
            return;
        _travelFromHandoff = !!handoff;
        travelSpring.snapTo(handoff ? handoff.rect : fluidCollapsedRect, handoff?.velocity);
        morphTravelEnabled = true;
    }

    function _retractFluidTravel() {
        if (!connected || !_fluidMotionActive || _supersededClose)
            return;
        if (!morphTravelEnabled) {
            travelSpring.snapTo(travelTarget);
            morphTravelEnabled = true;
        }
        _retargetMorphTravel();
    }

    function _freezeMorphTravel() {
        travelSpring.snapTo(travelSpring.value);
        _syncPopoutBody();
    }

    function _endMorphTravel() {
        morphTravelEnabled = false;
    }

    property bool _supersededClose: false
    property real _supersededContentX: 0
    property real _supersededContentY: 0
    property real _supersededContentScale: 1

    function beginSupersededClose() {
        if (!frameOwnsConnectedChrome || _supersededClose || !contentWindow.visible || !root.screen)
            return;
        if ((!hoverDismissEnabled && !isClosing) || !ConnectedModeState.hasSurfaceOwner(root.screen.name, "popout", chromeLease.claimId))
            return;
        // Hand off the bare body; the overflow stays on this descriptor.
        const state = _connectedChromeState();
        state.overflowTop = 0;
        state.overflowBottom = 0;
        const body = SurfaceGeometry.animatedBodyRect(state, root.dpr);
        const traveling = morphTravelEnabled && !morph.running;
        const rect = traveling ? root._boundTravel(travelSpring.value) : Qt.rect(body.x, body.y, Math.max(1, body.width), Math.max(1, body.height));
        const velocity = traveling ? travelSpring.velocity : Qt.vector4d(0, 0, 0, 0);
        const contentWrapper = chromeLoader.item.contentWrapper;
        ConnectedModeState.savePopoutMotion(chromeLease.claimId, root.screen.name, contentContainer.connectedBarSide, rect, velocity);
        _supersededContentX = contentContainer.x + contentWrapper.x - rect.x;
        _supersededContentY = contentContainer.y + contentWrapper.y - rect.y;
        _supersededContentScale = contentWrapper.scale;
        _supersededClose = true;
        travelSpring.snapTo(rect);
        morphTravelEnabled = true;
        morph.snapTo(1);
        _syncPopoutBody();
    }

    readonly property real connectedAnchorX: {
        if (!root.usesConnectedSurfaceChrome)
            return triggerX;
        switch (effectiveBarPosition) {
        case SettingsData.Position.Left:
            return barX + barWidth;
        case SettingsData.Position.Right:
            return barX;
        default:
            return triggerX;
        }
    }
    readonly property real connectedAnchorY: {
        if (!root.usesConnectedSurfaceChrome)
            return triggerY;
        switch (effectiveBarPosition) {
        case SettingsData.Position.Top:
            return barY + barHeight;
        case SettingsData.Position.Bottom:
            return barY;
        default:
            return triggerY;
        }
    }

    function adjacentBarClearance(exclusion) {
        if (exclusion <= 0)
            return 0;
        if (!root.usesConnectedSurfaceChrome)
            return exclusion;
        return exclusion + Theme.connectedCornerRadius * 2;
    }

    onAlignedHeightChanged: {
        _retargetBody();
        if (suspendShadowWhileResizing && shouldBeVisible) {
            _resizeActive = true;
            resizeSettleTimer.restart();
        }
        _syncAlignedGeometry();
    }
    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            _contentRenderActive = true;
            return;
        }
        _resizeActive = false;
        resizeSettleTimer.stop();
    }
    on_ContentRenderActiveChanged: {
        if (!_contentRenderActive && isClosing && !shouldBeVisible)
            closeAnimationFinished();
    }

    Timer {
        id: resizeSettleTimer
        interval: 80
        repeat: false
        onTriggered: root._resizeActive = false
    }

    Timer {
        id: surfaceSettleTimer
        interval: Math.max(0, root.resizeDuration + 32)
        repeat: false
        onTriggered: root._setSettledSurfaceGeometry()
    }

    function _setSurfaceGeometry(bodyX, bodyY, bodyW, bodyH) {
        if (connected)
            return;
        const newX = Theme.snap(bodyX, dpr);
        const newY = Theme.snap(bodyY, dpr);
        const newW = Theme.snap(bodyW, dpr);
        const newH = Theme.snap(bodyH, dpr);
        const changed = newX !== _surfaceBodyX || newY !== _surfaceBodyY || newW !== _surfaceBodyW || newH !== _surfaceBodyH;
        _surfaceBodyX = newX;
        _surfaceBodyY = newY;
        _surfaceBodyW = newW;
        _surfaceBodyH = newH;
        _requestSurfaceAxis("x", newX - shadowBuffer, newW + shadowBuffer * 2);
        if (!fullHeightSurface)
            _requestSurfaceAxis("y", newY - shadowBuffer, newH + shadowBuffer * 2);
        if (changed && !resizing && backgroundLayer.item)
            backgroundLayer.item.surfaceMoved();
    }

    // Compositors place the old buffer at the new origin until the configure round trip lands, and niri
    // clamps sizes to the output. Anchoring the far edge lets the surface grow with its origin fixed, so
    // the origin only moves once the buffer already spans the target; shrinks keep the body covered anyway.
    function _requestSurfaceAxis(axis, start, size) {
        const x = axis === "x";
        const pendingProp = x ? "_pendingSurfaceX" : "_pendingSurfaceY";
        const timer = x ? surfaceStepTimerX : surfaceStepTimerY;
        root[pendingProp] = null;
        timer.stop();
        const currentStart = x ? _surfaceX : _surfaceY;
        const actualSize = x ? contentWindow.width : contentWindow.height;
        const growSize = (x ? _anchorEndX : _anchorEndY) ? size : Math.min(size, (x ? screenWidth : screenHeight) - currentStart);
        if (!contentWindow.visible || start >= currentStart || growSize === actualSize) {
            _applySurfaceAxis(axis, start, size);
            return;
        }
        root[pendingProp] = {
            "start": start,
            "size": size
        };
        _applySurfaceAxis(axis, currentStart, size);
        timer.restart();
    }

    function _applySurfaceAxis(axis, start, size) {
        if (axis === "x") {
            _surfaceX = start;
            _surfaceW = size;
            return;
        }
        _surfaceY = start;
        _surfaceH = size;
    }

    function _flushPendingSurface(axis, timedOut) {
        const x = axis === "x";
        const pendingProp = x ? "_pendingSurfaceX" : "_pendingSurfaceY";
        const pending = root[pendingProp];
        if (!pending)
            return;
        const actualSize = x ? contentWindow.width : contentWindow.height;
        const reachedEdge = (x ? _surfaceX : _surfaceY) + actualSize >= (x ? screenWidth : screenHeight);
        if (!timedOut && pending.size !== actualSize && !reachedEdge)
            return;
        root[pendingProp] = null;
        (x ? surfaceStepTimerX : surfaceStepTimerY).stop();
        _applySurfaceAxis(axis, pending.start, pending.size);
    }

    function _setSettledSurfaceGeometry() {
        if (connected || !shouldBeVisible || surfaceScreen !== screen)
            return;
        _setSurfaceGeometry(surfaceBodyX, alignedY, surfaceBodyWidth, alignedHeight);
    }

    function _setAnimatedSurfaceEnvelope() {
        if (connected || !shouldBeVisible || surfaceScreen !== screen)
            return;
        const currentX = renderedAlignedX;
        const currentRight = renderedAlignedX + renderedAlignedWidth;
        // Handlers run before sibling bindings settle, so derive the target from the inputs.
        const targetWidth = Math.max(Theme.px(popupWidth, dpr), Theme.px(Math.min(minimumSurfaceWidth, screenWidth), dpr));
        const targetX = Theme.snap(_standaloneAlignedXFor(targetWidth), dpr);
        const targetRight = targetX + targetWidth;
        const envelopeX = Math.min(currentX, targetX);
        const envelopeWidth = Math.max(0, Math.max(currentRight, targetRight) - envelopeX);
        if (fullHeightSurface) {
            _setSurfaceGeometry(envelopeX, alignedY, envelopeWidth, alignedHeight);
            surfaceSettleTimer.restart();
            return;
        }

        const currentY = renderedAlignedY;
        const currentBottom = renderedAlignedY + renderedAlignedHeight;
        const targetY = alignedY;
        const targetBottom = alignedY + alignedHeight;
        const envelopeY = Math.min(currentY, targetY);
        const envelopeBottom = Math.max(currentBottom, targetBottom);
        _setSurfaceGeometry(envelopeX, envelopeY, envelopeWidth, Math.max(0, envelopeBottom - envelopeY));
        surfaceSettleTimer.restart();
    }

    function updateSurfacePosition() {
        _setSettledSurfaceGeometry();
    }

    function _connectedAlignedXFor(width) {
        const popupGap = _popupGapValue();
        const edgeGapLeft = _edgeGapFor("left", popupGap);
        const edgeGapRight = _edgeGapFor("right", popupGap);
        const anchorX = root.usesConnectedSurfaceChrome ? connectedAnchorX : triggerX;

        switch (effectiveBarPosition) {
        case SettingsData.Position.Left:
            return Math.max(popupGap, Math.min(screenWidth - width - edgeGapRight, anchorX));
        case SettingsData.Position.Right:
            return Math.max(edgeGapLeft, Math.min(screenWidth - width - popupGap, anchorX - width));
        default:
            const rawX = triggerX + (triggerWidth / 2) - (width / 2);
            const clearLeft = adjacentBarClearance(adjacentBarInfo.leftBar);
            const clearRight = adjacentBarClearance(adjacentBarInfo.rightBar);
            const minX = Math.max(edgeGapLeft, clearLeft);
            const maxX = screenWidth - width - Math.max(edgeGapRight, clearRight);
            return _snapNearFrameBound(Math.max(minX, Math.min(maxX, rawX)), minX, maxX, edgeGapLeft >= clearLeft, edgeGapRight >= clearRight);
        }
    }

    function _connectedAlignedY(overTop, overBottom) {
        const popupGap = _popupGapValue();
        const edgeGapTop = _edgeGapFor("top", popupGap);
        const edgeGapBottom = _edgeGapFor("bottom", popupGap);
        const anchorY = root.usesConnectedSurfaceChrome ? connectedAnchorY : triggerY;

        switch (effectiveBarPosition) {
        case SettingsData.Position.Bottom:
            return Math.max(edgeGapTop + overTop, Math.min(screenHeight - popupHeight - overBottom - popupGap, anchorY - popupHeight - overBottom));
        case SettingsData.Position.Top:
            return Math.max(popupGap + overTop, Math.min(screenHeight - popupHeight - overBottom - edgeGapBottom, anchorY + overTop));
        default:
            const rawY = triggerY - (popupHeight / 2);
            const clearTop = adjacentBarClearance(adjacentBarInfo.topBar);
            const clearBottom = adjacentBarClearance(adjacentBarInfo.bottomBar);
            const minY = Math.max(edgeGapTop, clearTop) + overTop;
            const maxY = screenHeight - popupHeight - overBottom - Math.max(edgeGapBottom, clearBottom);
            return _snapNearFrameBound(Math.max(minY, Math.min(maxY, rawY)), minY, maxY, edgeGapTop >= clearTop, edgeGapBottom >= clearBottom);
        }
    }

    function _standalonePopupGap() {
        const useAutoGaps = storedBarConfig?.popupGapsAuto !== undefined ? storedBarConfig.popupGapsAuto : true;
        const manualGapValue = storedBarConfig?.popupGapsManual !== undefined ? storedBarConfig.popupGapsManual : 4;
        return useAutoGaps ? Math.max(4, storedBarSpacing) : manualGapValue;
    }

    function _standaloneAlignedXFor(width) {
        const popupGap = _standalonePopupGap();
        const leftGap = _edgeClearance("left", popupGap, adjacentBarInfo.leftBar > 0 ? adjacentBarInfo.leftBar : 0);
        const rightGap = _edgeClearance("right", popupGap, adjacentBarInfo.rightBar > 0 ? adjacentBarInfo.rightBar : 0);

        switch (effectiveBarPosition) {
        case SettingsData.Position.Left:
            return Math.max(leftGap, Math.min(screenWidth - width - rightGap, triggerX));
        case SettingsData.Position.Right:
            return Math.max(leftGap, Math.min(screenWidth - width - rightGap, triggerX - width));
        default:
            const rawX = triggerX + (triggerWidth / 2) - (width / 2);
            const minX = leftGap;
            const maxX = screenWidth - width - rightGap;
            return Math.max(minX, Math.min(maxX, rawX));
        }
    }

    function _standaloneAlignedY(overTop, overBottom) {
        const popupGap = _standalonePopupGap();
        const topGap = _edgeClearance("top", popupGap, adjacentBarInfo.topBar > 0 ? adjacentBarInfo.topBar : 0);
        const bottomGap = _edgeClearance("bottom", popupGap, adjacentBarInfo.bottomBar > 0 ? adjacentBarInfo.bottomBar : 0);

        switch (effectiveBarPosition) {
        case SettingsData.Position.Bottom:
            return Math.max(topGap + overTop, Math.min(screenHeight - popupHeight - overBottom - bottomGap, triggerY - popupHeight - overBottom));
        case SettingsData.Position.Top:
            return Math.max(topGap + overTop, Math.min(screenHeight - popupHeight - overBottom - bottomGap, triggerY + overTop));
        default:
            const rawY = triggerY - (popupHeight / 2);
            const minY = topGap + overTop;
            const maxY = screenHeight - popupHeight - overBottom - bottomGap;
            return Math.max(minY, Math.min(maxY, rawY));
        }
    }

    function alignedXFor(width) {
        return Theme.snap(connected ? _connectedAlignedXFor(width) : _standaloneAlignedXFor(width), dpr);
    }

    readonly property real alignedX: alignedXFor(popupWidth)

    function alignedYFor(overTop, overBottom) {
        return Theme.snap(connected ? _connectedAlignedY(overTop, overBottom) : _standaloneAlignedY(overTop, overBottom), dpr);
    }

    readonly property real alignedY: alignedYFor(topOverflow, bottomOverflow)

    function _maxBodyWidthFor(startGap, endGap, anchorX) {
        switch (effectiveBarPosition) {
        case SettingsData.Position.Left:
            return screenWidth - anchorX - endGap;
        case SettingsData.Position.Right:
            return anchorX - startGap;
        default:
            return screenWidth - startGap - endGap;
        }
    }

    function _maxBodyHeightFor(startGap, endGap, anchorY) {
        switch (effectiveBarPosition) {
        case SettingsData.Position.Top:
            return screenHeight - anchorY - endGap;
        case SettingsData.Position.Bottom:
            return anchorY - startGap;
        default:
            return screenHeight - startGap - endGap;
        }
    }

    readonly property real maxBodyWidth: {
        if (connected) {
            const popupGap = _popupGapValue();
            const startGap = Math.max(_edgeGapFor("left", popupGap), adjacentBarClearance(adjacentBarInfo.leftBar));
            const endGap = Math.max(_edgeGapFor("right", popupGap), adjacentBarClearance(adjacentBarInfo.rightBar));
            return Math.max(0, _maxBodyWidthFor(startGap, endGap, usesConnectedSurfaceChrome ? connectedAnchorX : triggerX));
        }
        const popupGap = _standalonePopupGap();
        const startGap = _edgeClearance("left", popupGap, Math.max(0, adjacentBarInfo.leftBar));
        const endGap = _edgeClearance("right", popupGap, Math.max(0, adjacentBarInfo.rightBar));
        return Math.max(0, _maxBodyWidthFor(startGap, endGap, triggerX));
    }

    readonly property real maxBodyHeight: {
        if (connected) {
            const popupGap = _popupGapValue();
            const startGap = Math.max(_edgeGapFor("top", popupGap), adjacentBarClearance(adjacentBarInfo.topBar));
            const endGap = Math.max(_edgeGapFor("bottom", popupGap), adjacentBarClearance(adjacentBarInfo.bottomBar));
            return Math.max(0, _maxBodyHeightFor(startGap, endGap, usesConnectedSurfaceChrome ? connectedAnchorY : triggerY));
        }
        const popupGap = _standalonePopupGap();
        const startGap = _edgeClearance("top", popupGap, Math.max(0, adjacentBarInfo.topBar));
        const endGap = _edgeClearance("bottom", popupGap, Math.max(0, adjacentBarInfo.bottomBar));
        return Math.max(0, _maxBodyHeightFor(startGap, endGap, triggerY));
    }

    readonly property vector4d surfaceCornerRadii: chromeLoader.item?.surfaceCornerRadii ?? Qt.vector4d(Theme.windowRadius, Theme.windowRadius, Theme.windowRadius, Theme.windowRadius)
    readonly property real maskX: _dismissZone.x
    readonly property real maskY: _dismissZone.y
    readonly property real maskWidth: _dismissZone.width
    readonly property real maskHeight: _dismissZone.height

    DismissZone {
        id: _dismissZone
        barPosition: root.effectiveBarPosition
        barX: root.barX
        barY: root.barY
        barWidth: root.barWidth
        barHeight: root.barHeight
        screenWidth: root.screenWidth
        screenHeight: root.screenHeight
        adjacentBarInfo: root.adjacentBarInfo
    }

    Loader {
        id: backgroundLayer
        active: !root.connected
        sourceComponent: Item {
            id: background

            readonly property alias window: backgroundWindow
            readonly property bool dismissRequired: root.backgroundInteractive
            readonly property bool required: dismissRequired || root.overlayContent !== null
            readonly property bool overlayActive: overlayLoader.item?.visible ?? false
            // Snapshot mask geometry to prevent background damage on bar updates
            property real frozenMaskX: 0
            property real frozenMaskY: 0
            property real frozenMaskWidth: 0
            property real frozenMaskHeight: 0
            // Keeps the contentHoleRect carve-out tracking the body so clicks in newly grown areas do not dismiss.
            property bool commitWindow: false
            // An idle layer surface won't commit the cleared blur region on auto-close; pulse updatesEnabled to force it.
            property bool blurCommitSuppress: false

            readonly property bool popoutShown: root.shouldBeVisible
            // The idle surface never commits the emptied input region on close without a frame.
            onPopoutShownChanged: {
                if (popoutShown || !backgroundWindow.visible)
                    return;
                holdCommits();
            }

            function show() {
                if (required)
                    backgroundWindow.visible = true;
                holdCommits();
            }

            function holdCommits() {
                commitWindow = true;
                commitSettleTimer.restart();
            }

            function surfaceMoved() {
                if (!backgroundWindow.visible)
                    return;
                holdCommits();
                if (typeof backgroundWindow.update === "function")
                    backgroundWindow.update();
            }

            function pulseBlurCommit() {
                if (!backgroundWindow.visible)
                    return;
                blurCommitSuppress = true;
                blurCommitPulseTimer.restart();
                // Land the off->on toggle on a commit even after overlayActive has dropped.
                holdCommits();
            }

            onRequiredChanged: {
                if (root.shouldBeVisible)
                    backgroundWindow.visible = required;
            }

            Timer {
                id: commitSettleTimer
                interval: 250
                onTriggered: background.commitWindow = false
            }

            Timer {
                id: blurCommitPulseTimer
                interval: 16
                onTriggered: background.blurCommitSuppress = false
            }

            Connections {
                target: overlayLoader.item
                ignoreUnknownSignals: true
                function onOverlayBlurActiveChanged() {
                    background.pulseBlurCommit();
                }
            }

            Connections {
                target: root
                function onOpened() {
                    background.frozenMaskX = root.maskX;
                    background.frozenMaskY = root.maskY;
                    background.frozenMaskWidth = root.maskWidth;
                    background.frozenMaskHeight = root.maskHeight;
                    if (contentWindow.visible && background.required)
                        backgroundWindow.visible = true;
                    background.holdCommits();
                }
            }

            readonly property bool contentWindowVisible: contentWindow.visible

            onContentWindowVisibleChanged: {
                if (!contentWindowVisible)
                    backgroundWindow.visible = false;
            }

            PanelWindow {
                id: backgroundWindow
                screen: root.surfaceScreen
                visible: false
                color: "transparent"
                // Idle full-screen surface skips buffer updates, else it damages the whole screen every frame.
                updatesEnabled: !background.blurCommitSuppress && (background.overlayActive || background.commitWindow)

                WlrLayershell.namespace: root.layerNamespace + ":background"
                WlrLayershell.layer: root.effectivePopoutLayer
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                mask: Region {
                    item: maskRect
                    Region {
                        item: contentHoleRect
                        intersection: Intersection.Subtract
                    }
                }

                Rectangle {
                    id: maskRect
                    visible: false
                    color: "transparent"
                    x: background.dismissRequired ? background.frozenMaskX : 0
                    y: background.dismissRequired ? background.frozenMaskY : 0
                    width: (background.dismissRequired && root.shouldBeVisible && root.backgroundInteractive) ? background.frozenMaskWidth : 0
                    height: (background.dismissRequired && root.shouldBeVisible && root.backgroundInteractive) ? background.frozenMaskHeight : 0
                }

                Rectangle {
                    id: contentHoleRect
                    visible: false
                    color: "transparent"
                    x: background.dismissRequired ? root.renderedAlignedX - root.inputMargin : 0
                    y: background.dismissRequired ? root._surfaceBodyY - root.inputMargin : 0
                    width: (background.dismissRequired && root.shouldBeVisible) ? root.renderedAlignedWidth + root.inputMargin * 2 : 0
                    height: (background.dismissRequired && root.shouldBeVisible) ? root._surfaceBodyH + root.inputMargin * 2 : 0
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: false
                    enabled: background.dismissRequired && root.shouldBeVisible && root.backgroundInteractive
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: root.backgroundClicked()
                }

                HoverHandler {
                    enabled: root.hoverDismissEnabled && root.shouldBeVisible

                    function notePointer() {
                        if (!hovered)
                            return;
                        PopoutManager.updateHoverCursor(point.position.x, point.position.y);
                        hoverDismissController.notePointerMoved();
                    }

                    onHoveredChanged: notePointer()
                    onPointChanged: notePointer()
                }
            }
        }
    }

    PanelWindow {
        id: contentWindow
        screen: root.surfaceScreen
        visible: false
        color: "transparent"
        onVisibleChanged: {
            if (!visible) {
                root._surfaceFrameReady = false;
                root._pendingSurfaceX = null;
                root._pendingSurfaceY = null;
                surfaceStepTimerX.stop();
                surfaceStepTimerY.stop();
                if (!root.shouldBeVisible)
                    root._contentRenderActive = false;
                if (Qt.inputMethod) {
                    Qt.inputMethod.hide();
                    Qt.inputMethod.reset();
                }
            }
            if (!root.connected)
                return;
            if (visible)
                root._publishConnectedChromeState(true);
            else
                root._releaseConnectedChromeState();
        }

        Connections {
            target: contentContainer.Window.window
            enabled: contentWindow.visible && !root._surfaceFrameReady

            function onFrameSwapped() {
                root._surfaceFrameReady = true;
            }
        }

        PopoutHoverDismiss {
            id: hoverDismissController
            anchors.fill: parent
            dismissEnabled: root.hoverDismissEnabled
            dismissSuspended: root.hoverDismissSuspended
            surfaceVisible: root.shouldBeVisible
            globalOffsetX: root._surfaceOriginX
            globalOffsetY: root._surfaceOriginY
            onDismissRequested: root.closeFromHoverDismiss()
        }

        WlrLayershell.namespace: root.layerNamespace
        WlrLayershell.layer: root.effectivePopoutLayer
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: KeyboardFocus.keyboardFocus(root.shouldBeVisible && (root._keyboardReady || !root.connected), root.customKeyboardFocus)

        anchors {
            left: root.connected || !root._anchorEndX
            top: root.connected || root.fullHeightSurface || !root._anchorEndY
            right: root.connected || root._anchorEndX
            bottom: root.connected || root.fullHeightSurface || root._anchorEndY
        }

        WlrLayershell.margins {
            left: root.connected || root._anchorEndX ? 0 : root._surfaceX
            top: root.connected || root.fullHeightSurface || root._anchorEndY ? 0 : root._surfaceY
            right: !root.connected && root._anchorEndX ? root.screenWidth - root._surfaceX - root._surfaceW : 0
            bottom: !root.connected && !root.fullHeightSurface && root._anchorEndY ? root.screenHeight - root._surfaceY - root._surfaceH : 0
        }

        implicitWidth: root.connected ? 0 : root._surfaceW
        implicitHeight: root.connected || root.fullHeightSurface ? 0 : root._surfaceH

        mask: contentInputMask

        Region {
            id: contentInputMask
            item: (root.connected && root.shouldBeVisible && root.backgroundInteractive) ? backgroundDismissalMask : contentMaskRect
        }

        Item {
            id: backgroundDismissalMask
            visible: false
            x: root.maskX
            y: root.maskY
            width: root.maskWidth
            height: root.maskHeight
        }

        // Empty input region to avoid the animating surface taking pointer events
        Item {
            id: contentMaskRect
            visible: false
            x: contentContainer.x - contentContainer.horizontalConnectorExtent - root.inputMargin
            y: contentContainer.y - contentContainer.verticalConnectorExtent - root.inputMargin
            width: root.shouldBeVisible ? root.renderedAlignedWidth + contentContainer.horizontalConnectorExtent * 2 + root.inputMargin * 2 : 0
            height: root.shouldBeVisible ? root.renderedAlignedHeight + contentContainer.verticalConnectorExtent * 2 + root.inputMargin * 2 : 0
        }

        Loader {
            z: -1
            anchors.fill: parent
            active: root.connected
            sourceComponent: Item {
                id: backgroundClickCatcher
                enabled: root.shouldBeVisible && root.backgroundInteractive

                // Four edge strips that exclude the popup body, so cursor shapes
                // inside the content propagate correctly (full-screen MouseAreas
                // at z:-1 can suppress child cursorShape on Wayland).
                MouseArea {
                    x: 0
                    y: 0
                    width: parent.width
                    height: Math.max(0, root.renderedAlignedY - root.topOverflow)
                    enabled: parent.enabled
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: root.backgroundClicked()
                }
                MouseArea {
                    x: 0
                    y: root.renderedAlignedY + root.renderedAlignedHeight + root.bottomOverflow
                    width: parent.width
                    height: Math.max(0, parent.height - y)
                    enabled: parent.enabled
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: root.backgroundClicked()
                }
                MouseArea {
                    x: 0
                    y: root.renderedAlignedY - root.topOverflow
                    width: root.renderedAlignedX
                    height: root.renderedAlignedHeight + root.topOverflow + root.bottomOverflow
                    enabled: parent.enabled
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: root.backgroundClicked()
                }
                MouseArea {
                    x: root.renderedAlignedX + root.renderedAlignedWidth
                    y: root.renderedAlignedY - root.topOverflow
                    width: Math.max(0, parent.width - root.renderedAlignedX - root.renderedAlignedWidth)
                    height: root.renderedAlignedHeight + root.topOverflow + root.bottomOverflow
                    enabled: parent.enabled
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: root.backgroundClicked()
                }
            }
        }

        Item {
            id: contentContainer
            clip: root.morphTravelEnabled
            x: (root.morphTravelEnabled ? Theme.snap(root.pubBodyX, root.dpr) : root.renderedAlignedX) - root._surfaceOriginX
            y: (root.morphTravelEnabled ? Theme.snap(root.pubBodyY, root.dpr) : root.renderedAlignedY) - root._surfaceOriginY
            width: root.morphTravelEnabled ? Theme.snap(root.pubBodyW, root.dpr) : root.renderedAlignedWidth
            height: root.morphTravelEnabled ? Theme.snap(root.pubBodyH, root.dpr) : root.renderedAlignedHeight

            readonly property bool barTop: effectiveBarPosition === SettingsData.Position.Top
            readonly property bool barBottom: effectiveBarPosition === SettingsData.Position.Bottom
            readonly property bool barLeft: effectiveBarPosition === SettingsData.Position.Left
            readonly property bool barRight: effectiveBarPosition === SettingsData.Position.Right
            readonly property string connectedBarSide: barTop ? "top" : (barBottom ? "bottom" : (barLeft ? "left" : "right"))
            readonly property bool directionalEffect: Theme.isDirectionalEffect
            readonly property bool depthEffect: Theme.isDepthEffect
            readonly property real directionalTravelX: Math.max(root.animationOffset, root.renderedAlignedWidth + Theme.spacingL)
            readonly property real directionalTravelY: Math.max(root.animationOffset, root.renderedAlignedHeight + root.topOverflow + root.bottomOverflow + Theme.spacingL)
            readonly property real depthTravel: Math.max(root.animationOffset * 0.7, 28)
            readonly property real sectionTilt: (triggerSection === "left" ? -1 : (triggerSection === "right" ? 1 : 0))
            readonly property real horizontalConnectorExtent: root.usesConnectedSurfaceChrome && (barTop || barBottom) ? Theme.connectedCornerRadius : 0
            readonly property real verticalConnectorExtent: root.usesConnectedSurfaceChrome && (barLeft || barRight) ? Theme.connectedCornerRadius : 0

            readonly property real offsetX: {
                if (directionalEffect) {
                    if (barLeft)
                        return -directionalTravelX;
                    if (barRight)
                        return directionalTravelX;
                    if (barTop || barBottom)
                        return 0;
                    return sectionTilt * directionalTravelX * 0.2;
                }
                if (depthEffect) {
                    if (barLeft)
                        return -depthTravel;
                    if (barRight)
                        return depthTravel;
                    if (barTop || barBottom)
                        return 0;
                    return sectionTilt * depthTravel * 0.2;
                }
                return barLeft ? root.animationOffset : (barRight ? -root.animationOffset : 0);
            }
            readonly property real offsetY: {
                if (directionalEffect) {
                    if (barBottom)
                        return directionalTravelY;
                    if (barTop)
                        return -directionalTravelY;
                    if (barLeft || barRight)
                        return 0;
                    return directionalTravelY;
                }
                if (depthEffect) {
                    if (barBottom)
                        return depthTravel;
                    if (barTop)
                        return -depthTravel;
                    if (barLeft || barRight)
                        return 0;
                    return depthTravel;
                }
                return barBottom ? -root.animationOffset : (barTop ? root.animationOffset : 0);
            }

            readonly property real computedScaleCollapsed: root.animationScaleCollapsed
            readonly property real morphTravelPx: Math.max(1, Math.abs(offsetX), Math.abs(offsetY), (1 - computedScaleCollapsed) * Math.max(root.alignedWidth, root.alignedHeight), root._fluidMotionActive ? Math.max(root.alignedWidth, root.alignedHeight) : 0)

            PopoutHoverBodyTracker {
                controller: hoverDismissController
                trackingEnabled: root.hoverDismissEnabled && root.shouldBeVisible
            }

            SpringMotion {
                id: morph
                onRunningChanged: {
                    if (!running && (Theme.isDirectionalEffect || root._fluidMotionActive) && root.isClosing && !root.shouldBeVisible)
                        root.closeAnimationFinished();
                }
                enabled: root.animationsEnabled && !(root.connected && root._fluidMotionActive)
                reducedMotion: root.animationDuration <= 0
                positionEpsilon: Math.max(0.001, 0.25 / root.dpr / contentContainer.morphTravelPx)
                velocityEpsilon: positionEpsilon * damping / Math.max(0.001, 2 * mass)
                stiffness: root._geometrySpringParams.stiffness
                damping: root._geometrySpringParams.damping

                Component.onCompleted: snapTo(root.shouldBeVisible ? 1 : 0)
            }
            readonly property bool morphSettled: !morph.running || Math.abs(morph.value - morph.target) < Theme.morphLayerEpsilon
            readonly property real morphProgress: root.connected || !morphSettled ? morph.value : morph.target
            readonly property real animX: root._fluidMotionActive ? 0 : contentContainer.offsetX * (1 - morphProgress)
            readonly property real animY: root._fluidMotionActive ? 0 : contentContainer.offsetY * (1 - morphProgress)
            onAnimXChanged: {
                if (!root.connected)
                    return;
                root._syncPopoutAnim("x");
            }
            onAnimYChanged: {
                if (!root.connected)
                    return;
                root._syncPopoutAnim("y");
            }
            readonly property real scaleValue: root._fluidMotionActive ? 1 : contentContainer.computedScaleCollapsed + (1.0 - contentContainer.computedScaleCollapsed) * morphProgress

            Component.onCompleted: root._captureChromeAnimTravel()

            readonly property bool rootShouldBeVisible: root.shouldBeVisible

            onRootShouldBeVisibleChanged: {
                root._captureChromeAnimTravel();
                // Skip reverse emerge animation during a superseded close.
                morph.retarget((rootShouldBeVisible || root._supersededClose) ? 1 : 0);
            }

            Loader {
                id: chromeLoader
                anchors.fill: parent
                sourceComponent: root.connected ? connectedChrome : standaloneChrome
            }

            Loader {
                id: contentLoader
                parent: chromeLoader.item ? chromeLoader.item.contentWrapper : contentContainer
                anchors.fill: parent
                sourceComponent: root.popoutHandle.content
                // _contentWarm keeps the tree loaded across close for fast re-open; reclaimed by PopoutService on lock/idle.
                active: root._primeContent || root.shouldBeVisible || contentWindow.visible || root._contentWarm
                asynchronous: root._backgroundWarm && !root._primeContent && !root.shouldBeVisible && !contentWindow.visible
            }
        }

        Item {
            id: focusHelper
            parent: contentContainer
            anchors.fill: parent
            visible: !root.contentHandlesKeys
            enabled: !root.contentHandlesKeys
            focus: !root.contentHandlesKeys
            Keys.onPressed: event => {
                if (root.contentHandlesKeys)
                    return;
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
    }

    Loader {
        id: overlayLoader
        parent: root.backgroundWindow ? root.backgroundWindow.contentItem : root
        z: 1
        anchors.fill: parent
        active: root.overlayContent !== null && (root.backgroundWindow?.visible ?? false)
        sourceComponent: root.overlayContent
    }

    Component {
        id: connectedChrome

        Item {
            id: chrome

            readonly property alias contentWrapper: contentWrapper
            readonly property alias blur: popoutBlur
            readonly property real surfaceRadius: root.usesConnectedSurfaceChrome ? Theme.connectedSurfaceRadius : Theme.windowRadius
            readonly property color surfaceColor: root.usesConnectedSurfaceChrome ? Theme.connectedSurfaceColor : Theme.readableSurface
            readonly property color surfaceBorderColor: root.usesConnectedSurfaceChrome ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor
            readonly property real surfaceBorderWidth: root.usesConnectedSurfaceChrome ? 0 : BlurService.borderWidth
            readonly property real surfaceTopLeftRadius: root.usesConnectedSurfaceChrome && (contentContainer.barTop || contentContainer.barLeft) ? 0 : surfaceRadius
            readonly property real surfaceTopRightRadius: root.usesConnectedSurfaceChrome && (contentContainer.barTop || contentContainer.barRight) ? 0 : surfaceRadius
            readonly property real surfaceBottomLeftRadius: root.usesConnectedSurfaceChrome && (contentContainer.barBottom || contentContainer.barLeft) ? 0 : surfaceRadius
            readonly property real surfaceBottomRightRadius: root.usesConnectedSurfaceChrome && (contentContainer.barBottom || contentContainer.barRight) ? 0 : surfaceRadius
            readonly property vector4d surfaceCornerRadii: Qt.vector4d(surfaceTopLeftRadius, surfaceTopRightRadius, surfaceBottomRightRadius, surfaceBottomLeftRadius)

            WindowBlur {
                id: popoutBlur
                targetWindow: contentWindow
                blurEnabled: !root.frameOwnsConnectedChrome && (!root.usesConnectedSurfaceChrome || Theme.connectedSurfaceBlurEnabled)
                surfaceColor: chrome.surfaceColor

                readonly property real s: Math.min(1, contentContainer.scaleValue)
                readonly property bool trackBlurFromBarEdge: root.usesConnectedSurfaceChrome

                readonly property real _overflowExtent: root.topOverflow + root.bottomOverflow
                readonly property real _dyClamp: (contentContainer.barTop || contentContainer.barBottom) ? Math.max(-contentContainer.height - _overflowExtent, Math.min(contentContainer.animY, contentContainer.height + _overflowExtent)) : 0
                readonly property real _dxClamp: (contentContainer.barLeft || contentContainer.barRight) ? Math.max(-contentContainer.width, Math.min(contentContainer.animX, contentContainer.width)) : 0

                blurX: trackBlurFromBarEdge ? contentContainer.x + (contentContainer.barRight ? _dxClamp : 0) : contentContainer.x + contentContainer.width * (1 - s) * 0.5 + Theme.snap(contentContainer.animX, root.dpr) - contentContainer.horizontalConnectorExtent * s
                blurY: (trackBlurFromBarEdge ? contentContainer.y + (contentContainer.barBottom ? _dyClamp : 0) : contentContainer.y + contentContainer.height * (1 - s) * 0.5 + Theme.snap(contentContainer.animY, root.dpr) - contentContainer.verticalConnectorExtent * s) - root.topOverflow
                blurWidth: root.shouldBeVisible ? (trackBlurFromBarEdge ? Math.max(0, contentContainer.width - Math.abs(_dxClamp)) : (contentContainer.width + contentContainer.horizontalConnectorExtent * 2) * s) : 0
                blurHeight: root.shouldBeVisible ? (trackBlurFromBarEdge ? Math.max(0, contentContainer.height + _overflowExtent - Math.abs(_dyClamp)) : (contentContainer.height + contentContainer.verticalConnectorExtent * 2) * s + _overflowExtent) : 0
                blurRadius: root.usesConnectedSurfaceChrome ? Theme.connectedCornerRadius : Theme.windowRadius
            }

            Item {
                id: directionalClipMask

                visible: !root._surfaceSwitching
                readonly property bool shouldClip: Theme.isDirectionalEffect || root.usesConnectedSurfaceChrome
                readonly property real clipOversize: 1000
                // inputMargin is only non-zero while a grid is being edited; let its chrome cross the connected edge instead of clipping it.
                readonly property real connectedClipAllowance: {
                    if (!root.usesConnectedSurfaceChrome)
                        return 0;
                    if (root.frameOwnsConnectedChrome)
                        return root.inputMargin;
                    return -Theme.connectedCornerRadius + root.inputMargin;
                }

                clip: shouldClip

                x: shouldClip ? (contentContainer.barLeft ? -connectedClipAllowance : -clipOversize) : 0
                y: shouldClip ? (contentContainer.barTop ? -connectedClipAllowance : -clipOversize) : 0

                width: {
                    if (!shouldClip)
                        return parent.width;
                    if (contentContainer.barLeft)
                        return parent.width + connectedClipAllowance + clipOversize;
                    if (contentContainer.barRight)
                        return parent.width + clipOversize + connectedClipAllowance;
                    return parent.width + clipOversize * 2;
                }
                height: {
                    if (!shouldClip)
                        return parent.height;
                    if (contentContainer.barTop)
                        return parent.height + connectedClipAllowance + clipOversize;
                    if (contentContainer.barBottom)
                        return parent.height + clipOversize + connectedClipAllowance;
                    return parent.height + clipOversize * 2;
                }

                Item {
                    id: rollOutAdjuster
                    readonly property real baseWidth: root.renderedAlignedWidth
                    readonly property real baseHeight: root.renderedAlignedHeight

                    x: directionalClipMask.x !== 0 ? -directionalClipMask.x : 0
                    y: directionalClipMask.y !== 0 ? -directionalClipMask.y : 0
                    width: baseWidth
                    height: baseHeight

                    clip: false

                    ElevationShadow {
                        visible: !root.usesConnectedSurfaceChrome
                        width: rollOutAdjuster.baseWidth
                        height: rollOutAdjuster.baseHeight + root.topOverflow + root.bottomOverflow
                        opacity: contentWrapper.publishedOpacity
                        scale: contentWrapper.scale
                        x: contentWrapper.x
                        y: contentWrapper.y - root.topOverflow
                        level: root.shadowLevel
                        direction: root.effectiveShadowDirection
                        fallbackOffset: root.shadowFallbackOffset
                        targetRadius: chrome.surfaceRadius
                        topLeftRadius: chrome.surfaceTopLeftRadius
                        topRightRadius: chrome.surfaceTopRightRadius
                        bottomLeftRadius: chrome.surfaceBottomLeftRadius
                        bottomRightRadius: chrome.surfaceBottomRightRadius
                        // Shadow only; contentWrapper paints the fill.
                        targetColor: "transparent"
                        shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1" && !(root.suspendShadowWhileResizing && root._resizeActive) && !root.frameOwnsConnectedChrome
                    }

                    Item {
                        id: localChrome
                        visible: root.usesLocalConnectedSurfaceChrome

                        readonly property real extraLeft: (contentContainer.barTop || contentContainer.barBottom) ? Theme.connectedCornerRadius : 0
                        readonly property real extraTop: (contentContainer.barLeft || contentContainer.barRight) ? Theme.connectedCornerRadius : 0

                        readonly property bool shadowsOn: Theme.elevationEnabled && SettingsData.popoutElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1" && !(root.suspendShadowWhileResizing && root._resizeActive)
                        readonly property real shadowBlurPx: root.shadowLevel && root.shadowLevel.blurPx !== undefined ? root.shadowLevel.blurPx : 0
                        readonly property real shadowSpreadPx: root.shadowLevel && root.shadowLevel.spreadPx !== undefined ? root.shadowLevel.spreadPx : 0
                        readonly property real shadowOffsetX: Theme.elevationOffsetXFor(root.shadowLevel, root.effectiveShadowDirection, root.shadowFallbackOffset)
                        readonly property real shadowOffsetY: Theme.elevationOffsetYFor(root.shadowLevel, root.effectiveShadowDirection, root.shadowFallbackOffset)
                        readonly property color shadowTint: Theme.elevationShadowColor(root.shadowLevel)
                        readonly property var ambient: Theme.elevationAmbient(root.shadowLevel)
                        readonly property real pad: shadowsOn ? Math.ceil(Math.max(shadowBlurPx + shadowSpreadPx + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)), ambient.blurPx + ambient.spreadPx) + 2) : 0

                        width: rollOutAdjuster.baseWidth + extraLeft * 2
                        height: rollOutAdjuster.baseHeight + extraTop * 2 + root.topOverflow + root.bottomOverflow
                        opacity: contentWrapper.publishedOpacity
                        scale: contentWrapper.scale
                        x: contentWrapper.x - extraLeft
                        y: contentWrapper.y - extraTop - root.topOverflow

                        ShaderEffect {
                            anchors.fill: parent
                            anchors.topMargin: contentContainer.barTop ? 0 : -localChrome.pad
                            anchors.bottomMargin: contentContainer.barBottom ? 0 : -localChrome.pad
                            anchors.leftMargin: contentContainer.barLeft ? 0 : -localChrome.pad
                            anchors.rightMargin: contentContainer.barRight ? 0 : -localChrome.pad
                            fragmentShader: Qt.resolvedUrl("../Shaders/qsb/connected_chrome.frag.qsb")

                            property real widthPx: width
                            property real heightPx: height
                            property vector4d surfaceColor: Qt.vector4d(chrome.surfaceColor.r, chrome.surfaceColor.g, chrome.surfaceColor.b, chrome.surfaceColor.a)
                            property vector4d shadowColor: Qt.vector4d(localChrome.shadowTint.r, localChrome.shadowTint.g, localChrome.shadowTint.b, localChrome.shadowsOn ? localChrome.shadowTint.a : 0)
                            property vector4d shadowParam: Qt.vector4d(Math.max(0, localChrome.shadowBlurPx), localChrome.shadowSpreadPx, localChrome.shadowOffsetX, localChrome.shadowOffsetY)
                            property vector4d ambientParam: Qt.vector4d(localChrome.ambient.blurPx, localChrome.ambient.spreadPx, localChrome.shadowsOn ? localChrome.ambient.alpha : 0, 0)
                            property vector4d bodyRect: Qt.vector4d((contentContainer.barLeft ? 0 : localChrome.pad) + localChrome.extraLeft, (contentContainer.barTop ? 0 : localChrome.pad) + localChrome.extraTop, rollOutAdjuster.baseWidth, rollOutAdjuster.baseHeight + root.topOverflow + root.bottomOverflow)
                            property vector4d cornerRadius: Qt.vector4d(chrome.surfaceTopLeftRadius, chrome.surfaceTopRightRadius, chrome.surfaceBottomRightRadius, chrome.surfaceBottomLeftRadius)
                            property vector4d edgeParam: Qt.vector4d(contentContainer.barTop ? 0 : (contentContainer.barBottom ? 1 : (contentContainer.barLeft ? 2 : 3)), Theme.connectedCornerRadius, 0, 0)
                        }
                    }

                    DLayer {
                        id: contentWrapper
                        width: rollOutAdjuster.baseWidth
                        height: rollOutAdjuster.baseHeight

                        property bool _animating: false
                        readonly property bool _fadeWithOpacity: (!root._fluidMotionActive && !Theme.isDirectionalEffect) || root._supersededClose
                        readonly property bool _supersededFade: root._supersededClose && !root.shouldBeVisible
                        readonly property real _targetOpacity: root._supersededClose ? (root.shouldBeVisible ? 1 : 0) : (root._fluidMotionActive ? root.fluidContentOpacity : (Theme.isDirectionalEffect ? 1 : (root.shouldBeVisible ? 1 : 0)))
                        readonly property real publishedOpacity: opacity

                        opacity: _targetOpacity
                        visible: root._contentRenderActive

                        scale: root._supersededClose ? root._supersededContentScale : contentContainer.scaleValue
                        x: root._supersededClose ? root._supersededContentX : (root._fluidMotionActive ? root.renderedAlignedX - contentContainer.x : Theme.snap(contentContainer.animX, root.dpr))
                        y: root._supersededClose ? root._supersededContentY : (root._fluidMotionActive ? root.renderedAlignedY - contentContainer.y : Theme.snap(contentContainer.animY, root.dpr))

                        layer.enabled: _animating || (_fadeWithOpacity && publishedOpacity < 1)
                        fallbackDevicePixelRatio: root.dpr

                        Behavior on opacity {
                            enabled: contentWrapper._fadeWithOpacity
                            NumberAnimation {
                                duration: contentWrapper._supersededFade ? Theme.shorterDuration : Math.round(Theme.variantDuration(root.animationDuration, root.shouldBeVisible) * Theme.variantOpacityDurationScale)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.shouldBeVisible ? root.animationEnterCurve : root.animationExitCurve
                                onRunningChanged: {
                                    contentWrapper._animating = running;
                                    if (!running && !root.shouldBeVisible)
                                        root._contentRenderActive = false;
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            clip: false
                            visible: !root.usesConnectedSurfaceChrome

                            Rectangle {
                                y: -root.topOverflow
                                width: parent.width
                                height: parent.height + root.topOverflow + root.bottomOverflow
                                antialiasing: true
                                topLeftRadius: chrome.surfaceTopLeftRadius
                                topRightRadius: chrome.surfaceTopRightRadius
                                bottomLeftRadius: chrome.surfaceBottomLeftRadius
                                bottomRightRadius: chrome.surfaceBottomRightRadius
                                color: chrome.surfaceColor
                                border.color: chrome.surfaceBorderColor
                                border.width: chrome.surfaceBorderWidth
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: standaloneChrome

        Item {
            id: chrome

            readonly property alias contentWrapper: contentWrapper
            readonly property alias blur: popoutBlur
            readonly property rect fluidBody: root._fluidMotionActive ? FluidGeometry.limitOvershoot(FluidGeometry.interpolate(root.fluidCollapsedRect, root.fluidTarget, morph.value), root.fluidTarget, Theme.fluidOvershootLimit) : root.fluidTarget
            readonly property real clampedAnimX: Math.max(-width, Math.min(contentContainer.animX, width))
            readonly property real clampedAnimY: Math.max(-height, Math.min(contentContainer.animY, height))
            readonly property real revealWidth: {
                if (!root.directionalRevealActive)
                    return width;
                if (contentContainer.barLeft)
                    return Theme.snap(Math.max(0, width + clampedAnimX), root.dpr);
                if (contentContainer.barRight)
                    return Theme.snap(Math.max(0, width - clampedAnimX), root.dpr);
                return width;
            }
            readonly property real revealHeight: {
                if (!root.directionalRevealActive)
                    return height;
                if (contentContainer.barTop)
                    return Theme.snap(Math.max(0, height + clampedAnimY), root.dpr);
                if (contentContainer.barBottom)
                    return Theme.snap(Math.max(0, height - clampedAnimY), root.dpr);
                return height;
            }
            readonly property real revealX: root.directionalRevealActive && contentContainer.barRight ? Theme.snap(width - revealWidth, root.dpr) : 0
            readonly property real revealY: root.directionalRevealActive && contentContainer.barBottom ? Theme.snap(height - revealHeight, root.dpr) : 0

            // WindowBlur property updates don't dirty the scene graph, so render a frame to ship the new region.
            function kickBlurCommit() {
                if (typeof contentWindow.update === "function")
                    contentWindow.update();
            }

            readonly property real morphValue: morph.value
            readonly property real rootAlignedX: root.alignedX
            readonly property real rootAlignedY: root.alignedY
            readonly property real rootAlignedWidth: root.alignedWidth
            readonly property real rootAlignedHeight: root.alignedHeight
            readonly property bool rootShouldBeVisible: root.shouldBeVisible

            onMorphValueChanged: kickBlurCommit()
            onRootAlignedXChanged: kickBlurCommit()
            onRootAlignedYChanged: kickBlurCommit()
            onRootAlignedWidthChanged: kickBlurCommit()
            onRootAlignedHeightChanged: kickBlurCommit()
            onRootShouldBeVisibleChanged: kickBlurCommit()

            WindowBlur {
                id: popoutBlur
                targetWindow: contentWindow
                surfaceColor: Theme.readableSurface
                readonly property real s: Math.min(1, contentContainer.scaleValue)
                readonly property real op: Math.max(0, Math.min(1, (morph.value - 0.08) * 1.6))
                readonly property real visibleScale: s * op
                readonly property bool revealClipActive: root.directionalRevealActive || root._fluidMotionActive

                blurX: revealClipActive ? contentContainer.x : contentContainer.x + contentContainer.width * (1 - visibleScale) * 0.5 + Theme.snap(contentContainer.animX, root.dpr)
                blurY: (revealClipActive ? contentContainer.y : contentContainer.y + contentContainer.height * (1 - visibleScale) * 0.5 + Theme.snap(contentContainer.animY, root.dpr)) - root.topOverflow
                blurWidth: root.shouldBeVisible ? (revealClipActive ? contentContainer.width : contentContainer.width * visibleScale) : 0
                blurHeight: root.shouldBeVisible ? (revealClipActive ? contentContainer.height : contentContainer.height * visibleScale) + root.topOverflow + root.bottomOverflow : 0
                blurRadius: Theme.windowRadius
                clipEnabled: revealClipActive
                clipX: contentContainer.x + (root._fluidMotionActive ? chrome.fluidBody.x : chrome.revealX)
                clipY: contentContainer.y + (root._fluidMotionActive ? chrome.fluidBody.y : chrome.revealY) - root.topOverflow
                clipWidth: root.shouldBeVisible ? (root._fluidMotionActive ? chrome.fluidBody.width : chrome.revealWidth) : 0
                clipHeight: root.shouldBeVisible ? (root._fluidMotionActive ? chrome.fluidBody.height : chrome.revealHeight) + root.topOverflow + root.bottomOverflow : 0
            }

            SurfaceContentClip {
                id: contentClip

                active: root._fluidMotionActive
                revealActive: root.directionalRevealActive
                body: chrome.fluidBody
                targetRect: root.fluidTarget
                revealX: chrome.revealX
                revealY: chrome.revealY
                revealWidth: chrome.revealWidth
                revealHeight: chrome.revealHeight
                topOverflow: root.topOverflow
                bottomOverflow: root.bottomOverflow

                // Covers overflow chrome so the shadow and border don't cross the seam.
                ElevationShadow {
                    parent: root._fluidMotionActive ? chrome : contentClip.contentItem
                    z: root._fluidMotionActive ? -1 : 0
                    width: root._fluidMotionActive ? chrome.fluidBody.width : chrome.width
                    height: (root._fluidMotionActive ? chrome.fluidBody.height : chrome.height) + root.topOverflow + root.bottomOverflow
                    opacity: root._fluidMotionActive ? FluidGeometry.chromeOpacity(morph.value) : contentWrapper.publishedOpacity
                    scale: root.directionalRevealActive ? 1 : contentWrapper.scale
                    x: root._fluidMotionActive ? chrome.fluidBody.x : (root.directionalRevealActive ? 0 : contentWrapper.x)
                    y: (root._fluidMotionActive ? chrome.fluidBody.y : (root.directionalRevealActive ? 0 : contentWrapper.y)) - root.topOverflow
                    level: root.shadowLevel
                    direction: root.effectiveShadowDirection
                    fallbackOffset: root.shadowFallbackOffset
                    targetRadius: Theme.windowRadius
                    targetColor: root._fluidMotionActive ? Theme.readableSurface : "transparent"
                    shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1" && !(root.suspendShadowWhileResizing && root._resizeActive)
                }

                DLayer {
                    id: contentWrapper
                    width: chrome.width
                    height: chrome.height

                    property real publishedOpacity: Theme.isDirectionalEffect || root._fluidMotionActive ? 1 : (root.shouldBeVisible ? 1 : 0)
                    readonly property real settledOpacity: publishedOpacity >= 1 - Theme.morphSettleEpsilon ? 1 : Math.max(0, publishedOpacity)

                    opacity: root._fluidMotionActive || Theme.isDirectionalEffect ? 1 : settledOpacity
                    visible: root._contentRenderActive
                    scale: contentContainer.scaleValue
                    transformOrigin: Item.Center
                    x: root._fluidMotionActive ? 0 : contentContainer.animX + (chrome.width - width) * (1 - contentContainer.scaleValue) * 0.5
                    y: root._fluidMotionActive ? 0 : contentContainer.animY + (chrome.height - height) * (1 - contentContainer.scaleValue) * 0.5

                    layer.enabled: !Theme.isDirectionalEffect && !root._fluidMotionActive && root._contentRenderActive && (!contentContainer.morphSettled || opacity < 1)
                    layer.smooth: true
                    fallbackDevicePixelRatio: root.dpr

                    Behavior on publishedOpacity {
                        enabled: !Theme.isDirectionalEffect && !root._fluidMotionActive
                        NumberAnimation {
                            duration: Math.round(Theme.variantDuration(root.animationDuration, root.shouldBeVisible) * Theme.variantOpacityDurationScale)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root.shouldBeVisible ? root.animationEnterCurve : root.animationExitCurve
                            onRunningChanged: {
                                if (!running && !root.shouldBeVisible)
                                    root._contentRenderActive = false;
                            }
                        }
                    }

                    Rectangle {
                        y: -root.topOverflow
                        width: parent.width
                        height: parent.height + root.topOverflow + root.bottomOverflow
                        visible: !root._fluidMotionActive
                        radius: Theme.windowRadius
                        color: Theme.readableSurface
                    }
                }

                Rectangle {
                    parent: root._fluidMotionActive ? chrome : contentClip.contentItem
                    width: root._fluidMotionActive ? chrome.fluidBody.width : chrome.width
                    height: (root._fluidMotionActive ? chrome.fluidBody.height : chrome.height) + root.topOverflow + root.bottomOverflow
                    x: root._fluidMotionActive ? chrome.fluidBody.x : (root.directionalRevealActive ? 0 : contentWrapper.x)
                    y: (root._fluidMotionActive ? chrome.fluidBody.y : (root.directionalRevealActive ? 0 : contentWrapper.y)) - root.topOverflow
                    opacity: root._fluidMotionActive ? FluidGeometry.chromeOpacity(morph.value) : contentWrapper.publishedOpacity
                    scale: root.directionalRevealActive ? 1 : contentWrapper.scale
                    visible: contentWrapper.visible
                    radius: Theme.windowRadius
                    color: "transparent"
                    border.color: BlurService.borderColor
                    border.width: BlurService.borderWidth
                    z: 100
                }
            }
        }
    }
}
