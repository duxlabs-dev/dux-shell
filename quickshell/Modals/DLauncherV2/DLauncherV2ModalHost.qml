pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Modals.DLauncherV2.Components
import qs.Services
import qs.Widgets
import "../../Common/FluidGeometry.js" as FluidGeometry

Item {
    id: root
    property bool connected: true
    property bool spotlight: false
    readonly property bool isFloatingWindowSurface: connected ? !connectedSurfaceOverride : !frameConnected
    readonly property var log: Log.scoped("DLauncherV2ModalHost")

    property bool _fluidMotionActive: false
    readonly property bool connectedFluidMotion: _fluidMotionActive && frameOwnsConnectedChrome
    readonly property rect fluidTarget: Qt.rect(0, 0, alignedWidth, contentSurfaceHeight)
    readonly property string fluidSide: frameOwnsConnectedChrome ? resolvedConnectedBarSide : ""
    readonly property rect fluidCollapsedRect: !_fluidMotionActive ? fluidTarget : FluidGeometry.collapsed(fluidTarget, fluidSide, fluidSide === "left" || fluidSide === "right" ? fluidTarget.height / 2 : fluidTarget.width / 2, Theme.barHeight)
    readonly property rect fluidBody: _fluidMotionActive && !connectedFluidMotion ? FluidGeometry.limitOvershoot(FluidGeometry.interpolate(fluidCollapsedRect, fluidTarget, morph.value), fluidTarget, Theme.fluidOvershootLimit) : fluidTarget

    readonly property Item contentContainer: surfaceChrome.item?.contentContainer ?? null
    readonly property rect fluidTravelTarget: Qt.rect(0, 0, alignedWidth, contentSurfaceHeight)
    readonly property rect fluidTravelCollapsedRect: Qt.rect(contentContainer?.collapsedMotionX ?? 0, contentContainer?.collapsedMotionY ?? 0, alignedWidth, contentSurfaceHeight)
    readonly property real connectedFluidX: connectedFluidMotion ? fluidMotion.value.x : 0
    readonly property real connectedFluidY: connectedFluidMotion ? fluidMotion.value.y : 0

    RectSpringMotion {
        id: fluidMotion
        enabled: root.connectedFluidMotion && root.animationsEnabled && contentWindow.visible
        reducedMotion: root.launcherAnimationDuration <= 0 || SettingsData.reduceMotion
        positionEpsilon: 0.25 / root.dpr
        velocityEpsilon: positionEpsilon * damping / Math.max(0.001, 2 * mass)
        stiffness: Theme.springPreset("default", root.launcherAnimationDuration).stiffness
        damping: Theme.springPreset("default", root.launcherAnimationDuration).damping
        onRunningChanged: root._finishFluidClose()
    }

    SpringMotion {
        id: morph
        enabled: root.spotlight ? root._fluidMotionActive : (root.animationsEnabled && !root.connectedFluidMotion)
        reducedMotion: root.launcherAnimationDuration <= 0
        positionEpsilon: 0.001
        velocityEpsilon: 0.001
        stiffness: Theme.springPreset("default", root.launcherAnimationDuration).stiffness
        damping: Theme.springPreset("default", root.launcherAnimationDuration).damping

        Component.onCompleted: snapTo(0)
    }

    property var modalHandle: root
    property bool triggerUsesOverlayLayer: false

    visible: false

    property bool spotlightOpen: false
    readonly property bool shouldBeVisible: spotlightOpen
    readonly property string layerNamespace: spotlight ? "dms:spotlight" : "dms:launcher"
    property bool keyboardActive: false
    property bool contentVisible: false
    property bool _surfaceFrameReady: false
    readonly property bool floatingMotionVisible: contentVisible && _surfaceFrameReady
    readonly property bool launcherMotionVisible: frameOwnsConnectedChrome ? _motionActive : (Theme.isDirectionalEffect ? spotlightOpen : _motionActive)
    property var spotlightContent: launcherContentLoader.item
    property bool openedFromOverview: false
    property bool isClosing: false
    property bool _pendingInitialize: false
    property string _pendingQuery: ""
    property string _pendingMode: ""
    readonly property bool unloadContentOnClose: !spotlight && SettingsData.dankLauncherV2UnloadOnClose

    property bool animationsEnabled: true
    property bool _motionActive: false
    property bool _renderActive: connected ? ((Theme.isDirectionalEffect && !Theme.isConnectedEffect) || launcherMotionVisible) : contentVisible
    property real _frozenMotionX: 0
    property real _frozenMotionY: 0

    TransientSurfaceTracker {
        id: transientSurfaces
    }

    readonly property bool useHyprlandFocusGrab: CompositorService.useHyprlandFocusGrab
    readonly property var effectiveScreen: contentWindow.screen
    readonly property real screenWidth: effectiveScreen?.width ?? Theme.mediumBreakpoint * 2
    readonly property real screenHeight: effectiveScreen?.height ?? Theme.mediumBreakpoint
    readonly property real dpr: effectiveScreen ? CompositorService.getScreenScale(effectiveScreen) : 1
    readonly property bool useBackgroundDarken: !connected && !FrameTransitionState.effectiveFrameEnabled && SettingsData.modalDarkenBackground
    readonly property bool useSingleWindow: connected || CompositorService.isHyprland || useBackgroundDarken
    readonly property bool usesOverlayLayer: useBackgroundDarken || SettingsData.launcherUseOverlayLayer || triggerUsesOverlayLayer
    readonly property var effectiveLauncherLayer: LayerShell.fromEnv("DMS_MODAL_LAYER", root.usesOverlayLayer ? WlrLayer.Overlay : WlrLayer.Top, {
        "allow": ["top", "overlay"],
        "invalidLayer": WlrLayer.Top,
        "label": "modals",
        "error": true
    })

    readonly property bool _dmenuActive: spotlightContent?.controller?.searchMode === "dmenu"
    readonly property string _dmenuSizeOverride: _dmenuActive ? (spotlightContent.controller.dmenuSize || "") : ""

    readonly property int baseWidth: LauncherMetrics.sizeWidth(_dmenuSizeOverride || SettingsData.dankLauncherV2Size)
    readonly property int baseHeight: LauncherMetrics.sizeHeight(_dmenuSizeOverride || SettingsData.dankLauncherV2Size, paintedBorderWidth, !_dmenuActive && LauncherMetrics.footerShown(SettingsData.dankLauncherV2Size))
    readonly property real _contentImplicitH: launcherContentLoader.item?.implicitHeight ?? LauncherMetrics.pillHeight
    readonly property int modalWidth: Math.min(spotlight ? (_dmenuSizeOverride ? LauncherMetrics.sizeWidth(_dmenuSizeOverride) : LauncherMetrics.spotlightWidth) : baseWidth, screenWidth - LauncherMetrics.screenMargin)
    readonly property int modalHeight: spotlight ? _contentImplicitH : Math.min(baseHeight, screenHeight - LauncherMetrics.screenMargin)

    readonly property string preferredConnectedBarSide: SettingsData.frameLauncherEmergeSide

    readonly property bool frameConnectedMode: connected && FrameTransitionState.effectiveFrameEnabled && Theme.isConnectedEffect && !!effectiveScreen && SettingsData.isScreenInPreferences(effectiveScreen, SettingsData.frameScreenPreferences)
    readonly property bool frameConnected: CompositorService.usesConnectedFrameChromeForScreen(effectiveScreen)

    readonly property string resolvedConnectedBarSide: frameConnectedMode ? preferredConnectedBarSide : ""

    property bool _overStackedModal: false
    readonly property bool frameOwnsConnectedChrome: frameConnectedMode && resolvedConnectedBarSide !== "" && !_overStackedModal && effectiveLauncherLayer === WlrLayer.Top && CompositorService.canShareConnectedFrameChromeForScreen(effectiveScreen)
    readonly property bool launcherArcExtenderActive: frameOwnsConnectedChrome && SettingsData.frameLauncherArcExtender && (resolvedConnectedBarSide === "top" || resolvedConnectedBarSide === "bottom")

    function _dockOccupiesSide(side) {
        return SettingsData.dockOccupiesSide(root.effectiveScreen, side);
    }

    readonly property bool _dockBlocksEmergence: frameOwnsConnectedChrome && _dockOccupiesSide(resolvedConnectedBarSide)

    function _frameEdgeInset(side) {
        if (!effectiveScreen || !frameConnected)
            return 0;
        return SettingsData.frameEdgeInsetForSide(effectiveScreen, side);
    }

    readonly property var _connectedModalPos: {
        const fallback = {
            "x": (screenWidth - modalWidth) / 2,
            "y": (screenHeight - modalHeight) / 2
        };
        switch (resolvedConnectedBarSide) {
        case "top":
        case "bottom":
            {
                const insetL = SettingsData.frameEdgeInsetForSide(effectiveScreen, "left");
                const insetR = SettingsData.frameEdgeInsetForSide(effectiveScreen, "right");
                const insetT = SettingsData.frameEdgeInsetForSide(effectiveScreen, "top");
                const insetB = SettingsData.frameEdgeInsetForSide(effectiveScreen, "bottom");
                const usable = Math.max(0, screenWidth - insetL - insetR);
                const usableH = Math.max(0, screenHeight - insetT - insetB);
                return {
                    "x": insetL + Math.max(0, (usable - modalWidth) / 2),
                    "y": launcherArcExtenderActive ? insetT + Math.max(0, (usableH - modalHeight) / 2) : (resolvedConnectedBarSide === "top" ? insetT : screenHeight - modalHeight - insetB)
                };
            }
        case "left":
        case "right":
            {
                const insetT = SettingsData.frameEdgeInsetForSide(effectiveScreen, "top");
                const insetB = SettingsData.frameEdgeInsetForSide(effectiveScreen, "bottom");
                const usable = Math.max(0, screenHeight - insetT - insetB);
                return {
                    "x": resolvedConnectedBarSide === "left" ? SettingsData.frameEdgeInsetForSide(effectiveScreen, "left") : screenWidth - modalWidth - SettingsData.frameEdgeInsetForSide(effectiveScreen, "right"),
                    "y": insetT + Math.max(0, (usable - modalHeight) / 2)
                };
            }
        }
        return fallback;
    }

    readonly property real modalX: {
        if (frameOwnsConnectedChrome)
            return _connectedModalPos.x;
        if (!spotlight)
            return (screenWidth - modalWidth) / 2;
        const insetL = _frameEdgeInset("left");
        const insetR = _frameEdgeInset("right");
        const usable = Math.max(0, screenWidth - insetL - insetR);
        return insetL + Math.max(0, (usable - modalWidth) / 2);
    }
    readonly property real modalY: {
        if (frameOwnsConnectedChrome)
            return _connectedModalPos.y;
        if (!spotlight)
            return (screenHeight - modalHeight) / 2;
        return LauncherMetrics.spotlightY(screenHeight, _frameEdgeInset("top"), _frameEdgeInset("bottom"));
    }

    readonly property bool connectedSurfaceOverride: frameOwnsConnectedChrome
    readonly property int launcherAnimationDuration: frameOwnsConnectedChrome ? Theme.popoutAnimationDuration : Theme.modalAnimationDuration
    readonly property list<real> launcherEnterCurve: frameOwnsConnectedChrome ? Theme.variantPopoutEnterCurve : Theme.variantModalEnterCurve
    readonly property list<real> launcherExitCurve: frameOwnsConnectedChrome ? Theme.variantPopoutExitCurve : Theme.variantModalExitCurve
    readonly property color backgroundColor: connectedSurfaceOverride ? Theme.connectedSurfaceColor : Theme.floatingWindowSurface
    readonly property real cornerRadius: connectedSurfaceOverride ? Theme.connectedSurfaceRadius : spotlight ? LauncherMetrics.spotlightRadius(modalWidth) : Theme.windowRadius
    readonly property real frameBottomRadius: spotlight && !connectedSurfaceOverride ? LauncherMetrics.spotlightBottomRadius(modalWidth, _contentImplicitH) : cornerRadius
    readonly property color borderColor: {
        if (!SettingsData.dankLauncherV2BorderEnabled)
            return Theme.outlineMedium;
        switch (SettingsData.dankLauncherV2BorderColor) {
        case "primary":
            return Theme.primary;
        case "secondary":
            return Theme.secondary;
        case "outline":
            return Theme.outline;
        case "surfaceText":
            return Theme.onSurface;
        default:
            return Theme.primary;
        }
    }
    readonly property int borderWidth: SettingsData.dankLauncherV2BorderEnabled && !spotlight ? SettingsData.dankLauncherV2BorderThickness : 0
    readonly property color effectiveBorderColor: connectedSurfaceOverride ? Theme.withAlpha(borderColor, 0) : borderColor
    readonly property int effectiveBorderWidth: connectedSurfaceOverride ? 0 : borderWidth
    readonly property int paintedBorderWidth: connected ? (frameOwnsConnectedChrome ? 0 : effectiveBorderWidth) : Math.max(borderWidth, BlurService.borderWidth)

    readonly property var shadowLevel: Theme.elevationLevel3
    readonly property real shadowFallbackOffset: Theme.spacingS
    readonly property real shadowRenderPadding: (!frameOwnsConnectedChrome && Theme.elevationEnabled && SettingsData.modalElevationEnabled) ? Theme.elevationRenderPadding(shadowLevel, Theme.elevationLightDirection, shadowFallbackOffset, Theme.spacingS, Theme.spacingL) : 0
    readonly property real shadowPad: Theme.snap(shadowRenderPadding, dpr)
    readonly property real alignedWidth: Theme.px(modalWidth, dpr)
    readonly property real alignedHeight: Theme.px(spotlight ? _contentImplicitH : modalHeight, dpr)
    readonly property real alignedX: Theme.snap(modalX, dpr)
    readonly property real alignedY: Theme.snap(modalY, dpr)
    readonly property real _animHeadroom: spotlight ? Theme.spacingL : 0
    readonly property real windowX: Math.max(0, Theme.snap(alignedX - shadowPad, dpr))
    readonly property real windowY: Math.max(0, Theme.snap(alignedY - shadowPad - _animHeadroom, dpr))
    readonly property real contentX: Theme.snap(alignedX - windowX, dpr)
    readonly property real contentY: Theme.snap(alignedY - windowY, dpr)
    readonly property real windowWidth: alignedWidth + contentX + shadowPad
    readonly property real windowHeight: alignedHeight + contentY + shadowPad + _animHeadroom
    readonly property real _connectedChromeX: alignedX
    readonly property real _connectedChromeY: {
        if (!launcherArcExtenderActive)
            return alignedY;
        return resolvedConnectedBarSide === "top" ? Theme.snap(SettingsData.frameEdgeInsetForSide(effectiveScreen, "top"), dpr) : alignedY;
    }
    readonly property real _connectedChromeHeight: {
        if (!launcherArcExtenderActive)
            return alignedHeight;
        if (resolvedConnectedBarSide === "top")
            return Theme.snap(Math.max(alignedHeight, alignedY + alignedHeight - SettingsData.frameEdgeInsetForSide(effectiveScreen, "top")), dpr);
        if (resolvedConnectedBarSide === "bottom")
            return Theme.snap(Math.max(alignedHeight, screenHeight - SettingsData.frameEdgeInsetForSide(effectiveScreen, "bottom") - alignedY), dpr);
        return alignedHeight;
    }
    readonly property real contentSurfaceHeight: launcherArcExtenderActive ? _connectedChromeHeight : alignedHeight

    readonly property real _ccX: _connectedChromeX
    readonly property real _ccY: _connectedChromeY

    readonly property int _openDuration: 50
    readonly property int _closeDuration: 40
    readonly property int _motionDuration: 60

    signal dialogClosed

    Timer {
        id: _syncTimer
        interval: 0
        onTriggered: root._flushSync()
    }

    property bool _fullSyncPending: false

    function _currentScreenName() {
        return effectiveScreen ? effectiveScreen.name : "";
    }

    Loader {
        id: modalChrome
        active: root.connected
        sourceComponent: ConnectedModalChrome {
            modalHandle: root.modalHandle
            claimPrefix: "dms:launcher-v2"
            surfaceKind: "launcher"
            screenName: root._currentScreenName()
            enabled: root.frameOwnsConnectedChrome
            active: root.spotlightOpen
            presented: root.spotlightOpen || contentWindow.visible
            dockBlocked: root._dockBlocksEmergence
            dockSide: root.resolvedConnectedBarSide
            onRecoveryRequested: root._queueFullSync()
        }
    }

    function _publishModalChromeState() {
        const chrome = modalChrome.item;
        if (!chrome)
            return false;
        const presented = spotlightOpen || contentWindow.visible;
        const phase = !presented ? "hidden" : (isClosing ? "closing" : (!contentWindow.visible ? "opening" : "open"));
        const bodyRect = {
            "x": _connectedChromeX + fluidBody.x,
            "y": _connectedChromeY + fluidBody.y,
            "width": fluidBody.width,
            "height": fluidBody.height
        };
        const animationOffset = {
            "x": contentContainer ? contentContainer.animX : 0,
            "y": contentContainer ? contentContainer.animY : 0
        };
        const state = {
            "kind": "launcher",
            "screenName": root._currentScreenName(),
            "phase": phase,
            "visible": presented,
            "presented": presented,
            "layer": root.effectiveLauncherLayer === WlrLayer.Overlay ? "overlay" : "top",
            "barSide": resolvedConnectedBarSide,
            "bodyRect": bodyRect,
            "animationOffset": animationOffset,
            "scale": 1,
            "opacity": Theme.connectedSurfaceColor.a,
            "bodyX": bodyRect.x,
            "bodyY": bodyRect.y,
            "bodyW": bodyRect.width,
            "bodyH": bodyRect.height,
            "animX": animationOffset.x,
            "animY": animationOffset.y,
            "omitStartConnector": false,
            "omitEndConnector": false,
            "dockRetractSide": root._dockBlocksEmergence ? resolvedConnectedBarSide : ""
        };
        return chrome.publish(state);
    }

    function _syncModalChromeState() {
        _publishModalChromeState();
    }

    property bool _animSyncQueued: false
    property bool _bodySyncQueued: false

    function _queueFullSync() {
        if (!connected)
            return;
        _fullSyncPending = true;
        if (!_syncTimer.running)
            _syncTimer.restart();
    }
    function _queueAnimSync() {
        _animSyncQueued = true;
        if (!_syncTimer.running)
            _syncTimer.restart();
    }
    function _queueBodySync() {
        _bodySyncQueued = true;
        if (!_syncTimer.running)
            _syncTimer.restart();
    }
    function _flushSync() {
        const fullDirty = _fullSyncPending;
        const animDirty = _animSyncQueued;
        const bodyDirty = _bodySyncQueued;
        _fullSyncPending = false;
        _animSyncQueued = false;
        _bodySyncQueued = false;
        if (fullDirty)
            _syncModalChromeState();
        if (animDirty)
            _syncModalAnim();
        if (bodyDirty)
            _syncModalBody();
    }

    function _syncModalAnim() {
        if (!frameOwnsConnectedChrome)
            return;
        if (!contentContainer)
            return;
        modalChrome.item?.updateAnim(contentContainer.animX, contentContainer.animY);
    }

    function _syncModalBody() {
        if (!frameOwnsConnectedChrome)
            return;
        modalChrome.item?.updateBody(_connectedChromeX + fluidBody.x, _connectedChromeY + fluidBody.y, fluidBody.width, fluidBody.height);
    }

    function _releaseModalChrome() {
        modalChrome.item?.release();
    }

    function _queueFullSyncWhenConnected() {
        if (!connected)
            return;
        _queueFullSync();
    }

    function _queueBodySyncWhenConnected() {
        if (!connected)
            return;
        _queueBodySync();
    }

    onFrameOwnsConnectedChromeChanged: {
        if (!connected)
            return;
        _syncModalChromeState();
    }
    onLauncherArcExtenderActiveChanged: _queueFullSyncWhenConnected()
    onResolvedConnectedBarSideChanged: _queueFullSyncWhenConnected()
    onSpotlightOpenChanged: _queueFullSyncWhenConnected()
    onAlignedXChanged: _queueBodySyncWhenConnected()
    onAlignedYChanged: _queueBodySyncWhenConnected()
    onAlignedWidthChanged: _queueBodySyncWhenConnected()
    onAlignedHeightChanged: _queueBodySyncWhenConnected()
    onFluidBodyChanged: {
        if (!connected)
            return;
        if (_fluidMotionActive && !connectedFluidMotion)
            _syncModalBody();
    }
    onFluidTravelTargetChanged: {
        if (!connected)
            return;
        if (connectedFluidMotion && contentWindow.visible)
            fluidMotion.retarget(_motionActive ? fluidTravelTarget : fluidTravelCollapsedRect);
    }
    on_MotionActiveChanged: {
        if (!connected)
            return;
        if (connectedFluidMotion)
            fluidMotion.retarget(_motionActive ? fluidTravelTarget : fluidTravelCollapsedRect);
        morph.retarget(_motionActive ? 1 : 0);
    }
    on_EdgeRetractEnabledChanged: {
        if (!connected)
            return;
        if (!_edgeRetractEnabled) {
            _edgeRetractGrace.stop();
        } else if (_edgeArmed && !_edgeBodyHover) {
            _edgeRetractGrace.restart();
        }
    }

    onContentVisibleChanged: {
        if (connected || !contentVisible)
            return;
        _renderActive = true;
    }
    onFloatingMotionVisibleChanged: {
        if (connected)
            return;
        morph.retarget(floatingMotionVisible ? 1 : 0);
    }

    function _ensureContentLoadedAndInitialize(query, mode) {
        _pendingQuery = query || "";
        _pendingMode = mode || "";
        _pendingInitialize = true;
        contentVisible = true;
        launcherContentLoader.active = true;

        if (spotlightContent && _pendingInitialize) {
            _initializeAndShow(_pendingQuery, _pendingMode);
            _pendingInitialize = false;
        }
    }

    function _initializeAndShow(query, mode) {
        if (!spotlightContent)
            return;
        contentVisible = true;
        spotlightContent.closeTransientUi?.();

        const targetQuery = query || (SettingsData.rememberLastQuery ? (SessionData.launcherLastQuery || "") : "");

        if (spotlightContent.searchField) {
            spotlightContent.searchField.text = targetQuery;
            if (!connected)
                _focusSearchField(query);
        }
        if (spotlightContent.controller)
            spotlightContent.controller.openSession(targetQuery, !!query, mode || SessionData.getLauncherRestoreMode(), !spotlight || spotlightContent.showResultsWithoutQuery === true);
        if (spotlightContent.resetScroll) {
            spotlightContent.resetScroll();
        }
        if (spotlightContent.actionPanel) {
            spotlightContent.actionPanel.hide();
        }
    }

    function _focusSearchField(query) {
        const field = spotlightContent?.searchField;
        if (!field)
            return;
        field.forceActiveFocus();
        if (query) {
            field.cursorPosition = field.text.length;
            return;
        }
        field.selectAll();
    }

    function _openCommon(query, mode) {
        if (!spotlightOpen && !isClosing)
            _fluidMotionActive = Theme.isFluidEffect;
        closeCleanupTimer.stop();
        if (connected) {
            _openConnected(query, mode);
            return;
        }
        _openFloating(query, mode);
    }

    function _openConnected(query, mode) {
        const preserveFluid = _fluidMotionActive && contentWindow.visible;
        isClosing = false;
        openedFromOverview = false;
        _edgeArmed = false;
        _edgeBodyHover = false;

        if (!preserveFluid)
            animationsEnabled = false;

        var focusedScreen = CompositorService.getFocusedScreen();
        if (!contentWindow.visible)
            _overStackedModal = ModalManager.hasStackedModal((focusedScreen ?? effectiveScreen)?.name ?? "");

        _frozenMotionX = contentContainer ? contentContainer.collapsedMotionX : 0;
        _frozenMotionY = contentContainer ? contentContainer.collapsedMotionY : (Theme.isDirectionalEffect ? Math.max(root.screenHeight - root._ccY + root.shadowPad, Theme.effectAnimOffset * 1.1) : -Theme.effectAnimOffset);

        if (focusedScreen) {
            contentWindow.screen = focusedScreen;
        }

        if (!preserveFluid)
            _motionActive = false;

        if (connectedFluidMotion && !preserveFluid)
            fluidMotion.snapTo(fluidTravelCollapsedRect);

        spotlightOpen = true;
        contentWindow.visible = true;
        ModalManager.openModal(modalHandle);

        _ensureContentLoadedAndInitialize(query || "", mode || "");

        Qt.callLater(() => {
            if (!root.spotlightOpen)
                return;
            root.animationsEnabled = true;
            root._motionActive = true;

            Qt.callLater(() => {
                if (!root.spotlightOpen)
                    return;
                root.keyboardActive = true;
                root._focusSearchField(query);
            });
        });
    }

    function _openFloating(query, mode) {
        const focusedScreen = CompositorService.getFocusedScreen();
        if (focusedScreen && contentWindow.screen !== focusedScreen) {
            spotlightOpen = false;
            isClosing = false;
            contentWindow.visible = false;
            contentWindow.screen = focusedScreen;
            Qt.callLater(() => root._finishShow(query, mode));
            return;
        }
        _finishShow(query, mode);
    }

    function _finishShow(query, mode) {
        spotlightOpen = true;
        isClosing = false;
        contentWindow.visible = true;
        openedFromOverview = false;

        keyboardActive = true;
        ModalManager.openModal(modalHandle);

        _ensureContentLoadedAndInitialize(query || "", mode || "");
    }

    function show() {
        _openCommon("", "");
    }

    function showWithQuery(query) {
        _openCommon(query, "");
    }

    function attemptUserCancel() {
        const controller = spotlightContent?.controller;
        if (controller && controller.searchMode === "dmenu" && controller.dmenuOnlyMatch)
            return;
        hide();
    }

    function hide() {
        if (!spotlightOpen)
            return;
        spotlightContent?.closeTransientUi?.();
        openedFromOverview = false;
        isClosing = true;
        if (!connected || !Theme.isDirectionalEffect)
            contentVisible = false;

        keyboardActive = false;
        spotlightOpen = false;
        _motionActive = false;
        _edgeRetractGrace.stop();
        _edgeArmed = false;
        _edgeBodyHover = false;
        ModalManager.closeModal(modalHandle);
        if (!isClosing)
            return;
        closeCleanupTimer.start();
        _finishFluidClose();
    }

    function toggle() {
        spotlightOpen ? hide() : show();
    }

    function showWithMode(mode) {
        _openCommon("", mode);
    }

    function toggleWithMode(mode) {
        if (spotlightOpen) {
            hide();
        } else {
            showWithMode(mode);
        }
    }

    function toggleWithQuery(query) {
        if (spotlightOpen) {
            hide();
        } else {
            showWithQuery(query);
        }
    }

    function _finishFluidClose() {
        if (!connectedFluidMotion || fluidMotion.running)
            return;
        if (!fluidMotion.isSettled(fluidMotion.value, fluidMotion.velocity))
            return;
        _finishClose();
    }

    function _finishClose() {
        if (!isClosing || spotlightOpen)
            return;
        closeCleanupTimer.stop();
        isClosing = false;
        contentVisible = false;
        contentWindow.visible = false;
        _fluidMotionActive = false;
        _renderActive = false;
        if (unloadContentOnClose)
            launcherContentLoader.active = false;
        dialogClosed();
    }

    Timer {
        id: closeCleanupTimer
        interval: {
            if (root.connected)
                return Math.max(Theme.variantCloseInterval(root.launcherAnimationDuration), (root.connectedFluidMotion ? fluidMotion.settleDurationMs * 2 : morph.settleDurationMs) + 32);
            if (root.spotlight)
                return root._fluidMotionActive ? Math.max(Theme.modalAnimationDuration, morph.settleDurationMs) + 32 : root._motionDuration + 30;
            return Math.max(Theme.modalAnimationDuration + 50, Math.round(morph.settleDurationMs) + 32);
        }
        repeat: false
        onTriggered: root._finishClose()
    }

    readonly property bool _edgeRetractEnabled: connected && (modalHandle && modalHandle.edgeHoverManaged === true) && spotlightOpen && !isClosing && !transientSurfaces.active
    property bool _edgeBodyHover: false
    property bool _edgeArmed: false

    Timer {
        id: _edgeRetractGrace
        interval: 150
        repeat: false
        onTriggered: {
            if (root._edgeRetractEnabled && root._edgeArmed && !root._edgeBodyHover)
                root.hide();
        }
    }

    function _onEdgeBodyHoverChanged(over) {
        root._edgeBodyHover = over;
        if (over) {
            root._edgeArmed = true;
            _edgeRetractGrace.stop();
        } else if (root._edgeRetractEnabled) {
            _edgeRetractGrace.restart();
        }
    }

    Connections {
        target: spotlightContent?.controller ?? null
        enabled: !root.spotlight
        function onModeChanged(mode, userInitiated) {
            if (!userInitiated || !SettingsData.rememberLastMode)
                return;
            SessionData.setLauncherLastMode(mode);
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        windows: [contentWindow].concat(transientSurfaces.focusWindows)
        active: root.useHyprlandFocusGrab && !PopoutManager.screenshotActive && (root.connected ? root.spotlightOpen : root.keyboardActive)

        onCleared: {
            if (root.spotlightOpen && !PopoutManager.screenshotActive) {
                root.hide();
            }
        }
    }

    Connections {
        target: ModalManager
        function onCloseAllModalsExcept(excludedModal) {
            if (excludedModal !== root.modalHandle && root.spotlightOpen) {
                root.hide();
            }
        }
    }

    readonly property var quickshellScreens: Quickshell.screens

    onQuickshellScreensChanged: {
        if (Quickshell.screens.length === 0)
            return;

        const screenName = contentWindow.screen?.name;
        if (screenName && Quickshell.screens.some(screen => screen.name === screenName)) {
            if (spotlightOpen)
                _queueFullSync();
            return;
        }

        if (!connected && spotlightOpen)
            hide();

        const newScreen = CompositorService.getFocusedScreen() ?? Quickshell.screens[0];
        if (!newScreen)
            return;

        _releaseModalChrome();
        contentWindow.screen = newScreen;
    }

    Loader {
        id: clickCatcher
        active: !root.connected
        sourceComponent: Item {
            PanelWindow {
                screen: contentWindow.screen
                visible: (root.spotlightOpen || root.isClosing) && !root.useSingleWindow
                color: "transparent"
                updatesEnabled: false

                WlrLayershell.namespace: "dms:spotlight:clickcatcher"
                WlrLayershell.layer: root.effectiveLauncherLayer
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                mask: Region {
                    item: outsideClickMask

                    Region {
                        item: outsideClickHole
                        intersection: Intersection.Subtract
                    }
                }

                Item {
                    id: outsideClickMask
                    visible: false
                    anchors.fill: parent
                }

                Rectangle {
                    id: outsideClickHole
                    visible: false
                    color: "transparent"
                    x: root.windowX
                    y: root.windowY
                    width: root.windowWidth
                    height: root.windowHeight
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.spotlightOpen
                    onClicked: root.attemptUserCancel()
                }
            }
        }
    }

    PanelWindow {
        id: contentWindow
        visible: false
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        onVisibleChanged: {
            if (!visible)
                root._surfaceFrameReady = false;
            if (!root.connected)
                return;
            if (visible)
                root._syncModalChromeState();
            else
                root._releaseModalChrome();
        }

        WlrLayershell.namespace: "dms:spotlight"
        WlrLayershell.layer: root.effectiveLauncherLayer
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: KeyboardFocus.keyboardFocus(root.keyboardActive, null)

        anchors {
            left: true
            top: true
            right: root.useSingleWindow
            bottom: root.useSingleWindow || root.spotlight
        }

        WlrLayershell.margins {
            left: root.useSingleWindow ? 0 : root.windowX
            top: root.useSingleWindow ? 0 : root.windowY
            right: 0
            bottom: 0
        }

        implicitWidth: root.useSingleWindow ? 0 : root.windowWidth
        implicitHeight: root.useSingleWindow || root.spotlight ? 0 : root.windowHeight

        mask: surfaceChrome.item ? surfaceChrome.item.inputRegion : null

        Connections {
            target: surfaceChrome.Window.window
            enabled: contentWindow.visible && !root._surfaceFrameReady

            function onFrameSwapped() {
                root._surfaceFrameReady = true;
            }
        }

        Loader {
            id: surfaceChrome
            anchors.fill: parent
            sourceComponent: root.connected ? connectedChrome : floatingChrome
        }

        FocusScope {
            parent: surfaceChrome.item ? surfaceChrome.item.contentSlot : contentWindow.contentItem
            anchors.fill: parent
            focus: root.keyboardActive

            Loader {
                id: launcherContentLoader
                anchors.fill: parent
                active: (!root.spotlight && !root.unloadContentOnClose) || root.spotlightOpen || root.isClosing || root.contentVisible || root._pendingInitialize
                asynchronous: false
                sourceComponent: root.spotlight ? spotlightContentComponent : launcherContentComponent

                onLoaded: {
                    if (root._pendingInitialize) {
                        root._initializeAndShow(root._pendingQuery, root._pendingMode);
                        root._pendingInitialize = false;
                    }
                }
            }

            Keys.onPressed: event => root.spotlightContent?.activeContextMenu?.handleKey(event)

            Keys.onEscapePressed: event => {
                root.spotlightContent?.activeContextMenu?.handleKey(event);
                if (!event.accepted)
                    root.hide();
                event.accepted = true;
            }
        }
    }

    Component {
        id: launcherContentComponent
        LauncherContent {
            focus: true
            parentModal: root
            transientSurfaceTracker: transientSurfaces
        }
    }

    Component {
        id: spotlightContentComponent
        SpotlightLauncherContent {
            focus: true
            parentModal: root
            transientSurfaceTracker: transientSurfaces
        }
    }

    Component {
        id: connectedChrome

        Item {
            readonly property alias contentContainer: contentContainer
            readonly property alias inputRegion: launcherMask
            readonly property Item contentSlot: contentClip.contentItem

            WindowBlur {
                targetWindow: contentWindow
                blurEnabled: !root.frameOwnsConnectedChrome
                surfaceColor: root.backgroundColor
                readonly property real s: Math.min(1, contentContainer.scaleValue)
                readonly property bool clipDriven: root._fluidMotionActive && !root.connectedFluidMotion
                blurX: clipDriven ? (root._ccX + root.fluidBody.x) : root._ccX + root.alignedWidth * (1 - s) * 0.5 + Theme.snap(contentContainer.animX, root.dpr)
                blurY: clipDriven ? (root._ccY + root.fluidBody.y) : root._ccY + root.alignedHeight * (1 - s) * 0.5 + Theme.snap(contentContainer.animY, root.dpr)
                blurWidth: clipDriven ? (root.contentVisible ? root.fluidBody.width : 0) : (root.spotlightOpen || root.isClosing) && !root.frameOwnsConnectedChrome ? root.alignedWidth * s : 0
                blurHeight: clipDriven ? (root.contentVisible ? root.fluidBody.height : 0) : (root.spotlightOpen || root.isClosing) && !root.frameOwnsConnectedChrome ? root.alignedHeight * s : 0
                blurRadius: root.cornerRadius
                blurBottomRadius: root.frameBottomRadius
            }

            Region {
                id: launcherMask
                item: (root.spotlightOpen || root.isClosing) ? dismissArea : contentInputMask

                Region {
                    item: (root.spotlightOpen || root.isClosing) ? contentInputMask : null
                }
            }

            Item {
                id: dismissArea
                visible: false
                anchors.fill: parent
                anchors.topMargin: contentContainer.dockTop ? contentContainer.dockThicknessForEdge("top") : (typeof SettingsData !== "undefined" && SettingsData.barPosition === 0 ? Theme.px(Theme.barHeight, root.dpr) : 0)
                anchors.bottomMargin: contentContainer.dockBottom ? contentContainer.dockThicknessForEdge("bottom") : (typeof SettingsData !== "undefined" && SettingsData.barPosition === 1 ? Theme.px(Theme.barHeight, root.dpr) : 0)
                anchors.leftMargin: contentContainer.dockLeft ? contentContainer.dockThicknessForEdge("left") : (typeof SettingsData !== "undefined" && SettingsData.barPosition === 2 ? Theme.px(Theme.barHeight, root.dpr) : 0)
                anchors.rightMargin: contentContainer.dockRight ? contentContainer.dockThicknessForEdge("right") : (typeof SettingsData !== "undefined" && SettingsData.barPosition === 3 ? Theme.px(Theme.barHeight, root.dpr) : 0)
            }

            Item {
                id: contentInputMask
                visible: false
                x: contentContainer.x
                y: contentContainer.y
                width: root.alignedWidth
                height: root.contentSurfaceHeight
            }

            MouseArea {
                anchors.fill: dismissArea
                enabled: root.spotlightOpen
                z: -2
                onClicked: root.attemptUserCancel()
            }

            Item {
                id: contentContainer

                x: root._ccX
                y: root._ccY
                width: root.alignedWidth
                height: root.contentSurfaceHeight

                HoverHandler {
                    id: edgeBodyHoverHandler
                    enabled: root._edgeRetractEnabled
                    onHoveredChanged: root._onEdgeBodyHoverChanged(hovered)
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.spotlightOpen
                    hoverEnabled: false
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                    onClicked: mouse => mouse.accepted = true
                    z: -1
                }

                readonly property bool dockTop: SettingsData.dockOccupiesSide(root.effectiveScreen, "top")
                readonly property bool dockBottom: SettingsData.dockOccupiesSide(root.effectiveScreen, "bottom")
                readonly property bool dockLeft: SettingsData.dockOccupiesSide(root.effectiveScreen, "left")
                readonly property bool dockRight: SettingsData.dockOccupiesSide(root.effectiveScreen, "right")

                function dockThicknessForEdge(side) {
                    return Theme.px(SettingsData.dockReservationForEdge(root.effectiveScreen, side), root.dpr);
                }

                readonly property bool directionalEffect: Theme.isDirectionalEffect
                readonly property bool depthEffect: Theme.isDepthEffect
                readonly property real _connectedTravelX: Math.max(Theme.effectAnimOffset, root.alignedWidth + Theme.spacingL)
                readonly property real _connectedTravelY: root.launcherArcExtenderActive ? root._connectedChromeHeight : Math.max(Theme.effectAnimOffset, root.alignedHeight + Theme.spacingL)
                readonly property real collapsedMotionX: {
                    if (root.frameOwnsConnectedChrome) {
                        switch (root.resolvedConnectedBarSide) {
                        case "left":
                            return -_connectedTravelX;
                        case "right":
                            return _connectedTravelX;
                        }
                        return 0;
                    }
                    if (directionalEffect) {
                        if (dockLeft)
                            return -(root._ccX + root.alignedWidth + Theme.effectAnimOffset);
                        if (dockRight)
                            return root.screenWidth - root._ccX + Theme.effectAnimOffset;
                    }
                    if (depthEffect)
                        return Theme.effectAnimOffset * 0.25;
                    return 0;
                }
                readonly property real collapsedMotionY: {
                    if (root.frameOwnsConnectedChrome) {
                        switch (root.resolvedConnectedBarSide) {
                        case "top":
                            return -_connectedTravelY;
                        case "bottom":
                            return _connectedTravelY;
                        }
                        return 0;
                    }
                    if (directionalEffect) {
                        if (dockTop)
                            return -(root._ccY + root.alignedHeight + Theme.effectAnimOffset);
                        if (dockBottom)
                            return root.screenHeight - root._ccY + root.shadowPad + Theme.effectAnimOffset;
                        return 0;
                    }
                    if (depthEffect)
                        return -Math.max(Theme.effectAnimOffset * 0.85, Theme.avatarSize);
                    return -Math.max((root.shadowPad || 0) + Theme.effectAnimOffset, Theme.buttonHeightS);
                }

                readonly property real animX: root.connectedFluidMotion ? root.connectedFluidX : (root._fluidMotionActive ? 0 : root._frozenMotionX * (1 - morph.value))
                readonly property real animY: root.connectedFluidMotion ? root.connectedFluidY : (root._fluidMotionActive ? 0 : root._frozenMotionY * (1 - morph.value))
                readonly property real scaleValue: root._fluidMotionActive ? 1 : Theme.effectScaleCollapsed + (1.0 - Theme.effectScaleCollapsed) * morph.value

                onAnimXChanged: if (root.frameOwnsConnectedChrome)
                    root._queueAnimSync()
                onAnimYChanged: if (root.frameOwnsConnectedChrome)
                    root._queueAnimSync()

                Item {
                    id: directionalClipMask
                    readonly property bool shouldClip: Theme.isDirectionalEffect && (!root._fluidMotionActive || root.connectedFluidMotion)
                    readonly property real clipOversize: Math.max(root.screenWidth, root.screenHeight)
                    readonly property bool connectedClip: root.frameOwnsConnectedChrome
                    readonly property bool clipLeft: connectedClip ? root.resolvedConnectedBarSide === "left" : contentContainer.dockLeft
                    readonly property bool clipRight: connectedClip ? root.resolvedConnectedBarSide === "right" : contentContainer.dockRight
                    readonly property bool clipTop: connectedClip ? root.resolvedConnectedBarSide === "top" : contentContainer.dockTop
                    readonly property bool clipBottom: connectedClip ? root.resolvedConnectedBarSide === "bottom" : contentContainer.dockBottom

                    clip: shouldClip

                    x: shouldClip ? (clipLeft ? (connectedClip ? 0 : contentContainer.dockThicknessForEdge("left") - root._ccX) : -clipOversize) : 0
                    y: shouldClip ? (clipTop ? (connectedClip ? 0 : contentContainer.dockThicknessForEdge("top") - root._ccY) : -clipOversize) : 0

                    width: {
                        if (!shouldClip)
                            return parent.width;
                        if (connectedClip && (clipLeft || clipRight))
                            return parent.width + clipOversize;
                        return parent.width + clipOversize + (clipRight ? (root.screenWidth - contentContainer.dockThicknessForEdge("right") - root._ccX - parent.width) : clipOversize);
                    }
                    height: {
                        if (!shouldClip)
                            return parent.height;
                        if (connectedClip && (clipTop || clipBottom))
                            return parent.height + clipOversize;
                        return parent.height + clipOversize + (clipBottom ? (root.screenHeight - contentContainer.dockThicknessForEdge("bottom") - root._ccY - parent.height) : clipOversize);
                    }

                    Item {
                        id: aligner
                        x: directionalClipMask.x !== 0 ? -directionalClipMask.x : 0
                        y: directionalClipMask.y !== 0 ? -directionalClipMask.y : 0
                        width: contentContainer.width
                        height: contentContainer.height

                        ElevationShadow {
                            id: launcherShadowLayer
                            readonly property bool clipDriven: root._fluidMotionActive && !root.connectedFluidMotion
                            width: clipDriven ? root.fluidBody.width : parent.width
                            height: clipDriven ? root.fluidBody.height : parent.height
                            opacity: contentWrapper.publishedOpacity
                            scale: contentWrapper.scale
                            x: clipDriven ? root.fluidBody.x : contentWrapper.x
                            y: clipDriven ? root.fluidBody.y : contentWrapper.y
                            level: root.shadowLevel
                            fallbackOffset: root.shadowFallbackOffset
                            targetColor: root.frameOwnsConnectedChrome ? Theme.withAlpha(root.backgroundColor, 0) : root.backgroundColor
                            borderColor: root.frameOwnsConnectedChrome ? Theme.withAlpha(root.effectiveBorderColor, 0) : root.effectiveBorderColor
                            borderWidth: root.frameOwnsConnectedChrome ? 0 : root.effectiveBorderWidth
                            targetRadius: root.cornerRadius
                            bottomLeftRadius: root.frameBottomRadius
                            bottomRightRadius: root.frameBottomRadius
                            shadowEnabled: !root.frameOwnsConnectedChrome && Theme.elevationEnabled && SettingsData.modalElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1"
                        }

                        Item {
                            id: contentWrapper
                            width: parent.width
                            height: parent.height

                            readonly property real publishedOpacity: opacity

                            opacity: root.connectedFluidMotion ? 1 : (root._fluidMotionActive ? FluidGeometry.chromeOpacity(morph.value) : ((Theme.isDirectionalEffect && !Theme.isConnectedEffect) ? 1 : (root.launcherMotionVisible ? 1 : 0)))
                            visible: root._renderActive
                            scale: contentContainer.scaleValue
                            x: Theme.snap(contentContainer.animX + (parent.width - width) * (1 - contentContainer.scaleValue) * 0.5, root.dpr)
                            y: Theme.snap(contentContainer.animY + (parent.height - height) * (1 - contentContainer.scaleValue) * 0.5, root.dpr)

                            Behavior on opacity {
                                enabled: root.animationsEnabled && !root._fluidMotionActive && (!Theme.isDirectionalEffect || Theme.isConnectedEffect)
                                NumberAnimation {
                                    easing.type: Easing.BezierSpline
                                    duration: Math.round(Theme.variantDuration(root.launcherAnimationDuration, root.launcherMotionVisible) * Theme.variantOpacityDurationScale)
                                    easing.bezierCurve: root.launcherMotionVisible ? root.launcherEnterCurve : root.launcherExitCurve
                                    onRunningChanged: if (!running && !root.launcherMotionVisible)
                                        root._renderActive = false
                                }
                            }

                            readonly property bool rootLauncherMotionVisible: root.launcherMotionVisible

                            onRootLauncherMotionVisibleChanged: {
                                if (rootLauncherMotionVisible)
                                    root._renderActive = true;
                            }

                            MouseArea {
                                anchors.fill: parent
                                onPressed: mouse => mouse.accepted = true
                            }

                            SurfaceContentClip {
                                id: contentClip
                                readonly property bool isFloatingWindowSurface: root.isFloatingWindowSurface
                                active: root._fluidMotionActive && !root.connectedFluidMotion
                                body: root.fluidBody
                                targetRect: root.fluidTarget
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: floatingChrome

        Item {
            id: chrome

            readonly property alias inputRegion: launcherMask
            readonly property Item contentSlot: contentClip.contentItem
            readonly property int openDuration: root.spotlight ? root._openDuration : Theme.modalAnimationDuration
            readonly property int closeDuration: root.spotlight ? root._closeDuration : Theme.modalAnimationDuration
            readonly property list<real> enterCurve: root.spotlight ? [0.0, 0.0, 0.2, 1.0, 1.0, 1.0] : Theme.expressiveCurves.expressiveDefaultSpatial
            readonly property list<real> exitCurve: root.spotlight ? [0.4, 0.0, 1.0, 1.0, 1.0, 1.0] : Theme.expressiveCurves.emphasized

            function kickBlurCommit() {
                if (typeof contentWindow.update === "function")
                    contentWindow.update();
            }

            readonly property real rootAlignedX: root.alignedX
            readonly property real rootAlignedY: root.alignedY
            readonly property real rootAlignedWidth: root.alignedWidth
            readonly property real rootAlignedHeight: root.alignedHeight
            readonly property bool rootContentVisible: root.contentVisible

            function kickBlurCommitUnlessSpotlight() {
                if (root.spotlight)
                    return;
                kickBlurCommit();
            }

            onRootAlignedXChanged: kickBlurCommitUnlessSpotlight()
            onRootAlignedYChanged: kickBlurCommitUnlessSpotlight()
            onRootAlignedWidthChanged: kickBlurCommitUnlessSpotlight()
            onRootAlignedHeightChanged: kickBlurCommitUnlessSpotlight()
            onRootContentVisibleChanged: kickBlurCommitUnlessSpotlight()

            WindowBlur {
                targetWindow: contentWindow
                surfaceColor: root.backgroundColor
                readonly property real s: Math.min(1, modalContainer.publishedScale)
                readonly property real op: Math.max(0, Math.min(1, (modalContainer.opacity - 0.06) * 2))
                readonly property real visibleScale: s * op
                blurX: root._fluidMotionActive ? (modalContainer.x + root.fluidBody.x) : (root.spotlight ? modalContainer.x : modalContainer.x + modalContainer.width * (1 - visibleScale) * 0.5)
                blurY: root._fluidMotionActive ? (modalContainer.y + root.fluidBody.y) : (root.spotlight ? modalContainer.y + modalContainer.slideOffset : modalContainer.y + modalContainer.height * (1 - visibleScale) * 0.5)
                blurWidth: root._fluidMotionActive ? (root.contentVisible ? root.fluidBody.width : 0) : root.contentVisible ? modalContainer.width * visibleScale : 0
                blurHeight: root._fluidMotionActive ? (root.contentVisible ? root.fluidBody.height : 0) : root.contentVisible ? (root.spotlight ? root._contentImplicitH * op : modalContainer.height * visibleScale) : 0
                blurRadius: root.cornerRadius
                blurBottomRadius: root.frameBottomRadius
            }

            Region {
                id: launcherMask
                item: launcherInputMask
            }

            Rectangle {
                id: launcherInputMask
                visible: false
                color: "transparent"
                x: root.useSingleWindow ? 0 : modalContainer.x
                y: root.useSingleWindow ? 0 : modalContainer.y + modalContainer.slideOffset
                width: root.useSingleWindow ? contentWindow.width : modalContainer.width
                height: root.useSingleWindow ? contentWindow.height : (root.spotlight ? root._contentImplicitH : modalContainer.height)
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.useSingleWindow && root.spotlightOpen
                z: -2
                onClicked: root.attemptUserCancel()
            }

            Rectangle {
                id: backgroundDarken
                anchors.fill: parent
                color: Theme.backdropColor
                opacity: root.floatingMotionVisible && root.useBackgroundDarken ? Theme.scrimAlpha : 0
                visible: (root.spotlightOpen || root.isClosing) && (root.useBackgroundDarken || opacity > 0)
                z: -3

                Behavior on opacity {
                    NumberAnimation {
                        easing.type: Easing.BezierSpline
                        duration: root.contentVisible ? chrome.openDuration : chrome.closeDuration
                        easing.bezierCurve: root.contentVisible ? chrome.enterCurve : chrome.exitCurve
                    }
                }
            }

            Item {
                id: modalContainer
                x: root.useSingleWindow ? root.alignedX : root.contentX
                y: root.useSingleWindow ? root.alignedY : root.contentY
                width: root.alignedWidth
                height: root.alignedHeight
                visible: root._renderActive
                z: 0
                onOpacityChanged: chrome.kickBlurCommitUnlessSpotlight()
                onPublishedScaleChanged: chrome.kickBlurCommitUnlessSpotlight()

                MouseArea {
                    anchors.fill: parent
                    enabled: root.spotlightOpen
                    hoverEnabled: false
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                    onClicked: mouse => mouse.accepted = true
                    z: -1
                }

                property real slideOffset: root._fluidMotionActive ? 0 : (root.floatingMotionVisible ? 0 : -root._animHeadroom)
                property real publishedScale: root._fluidMotionActive || root.spotlight ? 1 : 0.96 + 0.04 * morph.value
                scale: publishedScale
                opacity: root._fluidMotionActive ? FluidGeometry.chromeOpacity(morph.value) : (root.floatingMotionVisible ? 1 : 0)

                transformOrigin: Item.Center

                Behavior on opacity {
                    enabled: !root._fluidMotionActive
                    NumberAnimation {
                        easing.type: Easing.BezierSpline
                        duration: root.contentVisible ? chrome.openDuration : chrome.closeDuration
                        easing.bezierCurve: root.contentVisible ? chrome.enterCurve : chrome.exitCurve
                        onRunningChanged: if (!running && !root.contentVisible)
                            root._renderActive = false
                    }
                }

                Behavior on slideOffset {
                    enabled: !root._fluidMotionActive
                    NumberAnimation {
                        duration: root._motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: root.contentVisible ? [0.2, 0.0, 0.0, 1.0, 1.0, 1.0] : [0.4, 0.0, 1.0, 1.0, 1.0, 1.0]
                    }
                }

                ElevationShadow {
                    anchors.fill: root._fluidMotionActive ? undefined : contentWrapper
                    x: root.fluidBody.x
                    y: root.fluidBody.y
                    width: root.fluidBody.width
                    height: root.fluidBody.height
                    level: root.shadowLevel
                    fallbackOffset: root.shadowFallbackOffset
                    targetColor: root.backgroundColor
                    borderColor: root.borderColor
                    borderWidth: root.borderWidth
                    targetRadius: root.cornerRadius
                    bottomLeftRadius: root.frameBottomRadius
                    bottomRightRadius: root.frameBottomRadius
                    shadowEnabled: Theme.elevationEnabled && SettingsData.modalElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1"
                }

                Item {
                    id: contentWrapper
                    y: modalContainer.slideOffset
                    width: parent.width
                    height: root.alignedHeight

                    MouseArea {
                        anchors.fill: parent
                        onPressed: mouse => mouse.accepted = true
                    }

                    SurfaceContentClip {
                        id: contentClip
                        readonly property bool isFloatingWindowSurface: root.isFloatingWindowSurface
                        active: root._fluidMotionActive
                        body: root.fluidBody
                        targetRect: root.fluidTarget
                    }
                }

                Rectangle {
                    visible: !root.spotlight
                    anchors.fill: root._fluidMotionActive ? undefined : parent
                    x: root.fluidBody.x
                    y: root.fluidBody.y
                    width: root.fluidBody.width
                    height: root.fluidBody.height
                    radius: root.cornerRadius
                    color: "transparent"
                    border.color: BlurService.borderColor
                    border.width: BlurService.borderWidth
                }
            }
        }
    }
}
