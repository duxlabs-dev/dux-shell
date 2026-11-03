pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import "../../Common/FluidGeometry.js" as FluidGeometry

Item {
    id: root
    readonly property bool isFloatingWindowSurface: !frameOwnsConnectedChrome
    readonly property var log: Log.scoped("DModalHost")

    required property var modalHandle
    property bool connected: true
    property bool _fluidMotionActive: false
    readonly property rect fluidTarget: Qt.rect(0, 0, alignedWidth, alignedHeight)
    readonly property string fluidSide: frameOwnsConnectedChrome ? resolvedConnectedBarSide : ""
    readonly property rect fluidCollapsedRect: !_fluidMotionActive ? fluidTarget : FluidGeometry.collapsed(fluidTarget, fluidSide, fluidSide === "left" || fluidSide === "right" ? alignedHeight / 2 : alignedWidth / 2, Theme.barHeight)
    readonly property rect fluidBody: _fluidMotionActive ? FluidGeometry.limitOvershoot(FluidGeometry.interpolate(fluidCollapsedRect, fluidTarget, morph.value), fluidTarget, Theme.fluidOvershootLimit) : fluidTarget

    property string layerNamespace: modalHandle.layerNamespace
    property alias content: contentLoader.sourceComponent
    property alias contentLoader: contentLoader
    property Item directContent: modalHandle.directContent
    property real modalWidth: modalHandle.modalWidth
    property real modalHeight: modalHandle.modalHeight
    property var targetScreen: modalHandle.targetScreen
    readonly property var effectiveScreen: contentWindow.screen ?? targetScreen
    readonly property real screenWidth: effectiveScreen?.width ?? 1920
    readonly property real screenHeight: effectiveScreen?.height ?? 1080
    readonly property real dpr: effectiveScreen ? CompositorService.getScreenScale(effectiveScreen) : 1
    property bool showBackground: modalHandle.showBackground
    property real backgroundOpacity: modalHandle.backgroundOpacity
    property string positioning: modalHandle.positioning
    property point customPosition: modalHandle.customPosition
    property bool closeOnEscapeKey: modalHandle.closeOnEscapeKey
    property bool closeOnBackgroundClick: modalHandle.closeOnBackgroundClick
    property string animationType: modalHandle.animationType

    property string preferredConnectedBarSide: SettingsData.frameModalEmergeSide

    readonly property bool frameConnectedMode: connected && FrameTransitionState.effectiveFrameEnabled && Theme.isConnectedEffect && !!effectiveScreen && SettingsData.isScreenInPreferences(effectiveScreen, SettingsData.frameScreenPreferences)

    readonly property string resolvedConnectedBarSide: frameConnectedMode ? preferredConnectedBarSide : ""

    property bool _overStackedModal: false
    readonly property bool frameOwnsConnectedChrome: frameConnectedMode && resolvedConnectedBarSide !== "" && !allowStacking && !_overStackedModal && effectiveModalLayer === WlrLayer.Top && CompositorService.canShareConnectedFrameChromeForScreen(effectiveScreen)

    function _dockOccupiesSide(side) {
        return SettingsData.dockOccupiesSide(root.effectiveScreen, side);
    }

    readonly property bool _dockBlocksEmergence: frameOwnsConnectedChrome && _dockOccupiesSide(resolvedConnectedBarSide)

    property int animationDuration: modalHandle.animationDuration
    property real animationScaleCollapsed: modalHandle.animationScaleCollapsed
    property real animationOffset: modalHandle.animationOffset
    property list<real> animationEnterCurve: modalHandle.animationEnterCurve
    property list<real> animationExitCurve: modalHandle.animationExitCurve
    property color backgroundColor: modalHandle.backgroundColor
    property color borderColor: modalHandle.borderColor
    property real borderWidth: modalHandle.borderWidth
    property real cornerRadius: modalHandle.cornerRadius
    readonly property color effectiveBackgroundColor: frameOwnsConnectedChrome ? Theme.connectedSurfaceColor : backgroundColor
    readonly property color effectiveBorderColor: frameOwnsConnectedChrome ? Theme.withAlpha(borderColor, 0) : borderColor
    readonly property real effectiveBorderWidth: frameOwnsConnectedChrome ? 0 : borderWidth
    readonly property real effectiveCornerRadius: frameOwnsConnectedChrome ? Theme.connectedSurfaceRadius : cornerRadius
    property bool enableShadow: modalHandle.enableShadow
    property alias modalFocusScope: focusScope
    property Item handleFocusScope: null
    property bool shouldBeVisible: false
    property bool isClosing: false
    property bool shouldHaveFocus: shouldBeVisible
    property bool allowFocusOverride: modalHandle.allowFocusOverride
    property bool allowStacking: modalHandle.allowStacking
    property bool keepContentLoaded: modalHandle.keepContentLoaded
    property bool keepPopoutsOpen: modalHandle.keepPopoutsOpen
    property var customKeyboardFocus: modalHandle.customKeyboardFocus
    property bool useOverlayLayer: modalHandle.useOverlayLayer
    readonly property var effectiveModalLayer: root.useOverlayLayer ? WlrLayer.Overlay : LayerShell.fromEnv("DMS_MODAL_LAYER", WlrLayer.Top, {
        "allow": ["top", "overlay"],
        "invalidLayer": WlrLayer.Top,
        "label": "modals",
        "error": true
    })
    property real frozenMotionOffsetX: 0
    property real frozenMotionOffsetY: 0
    readonly property alias contentWindow: contentWindow
    readonly property bool useHyprlandFocusGrab: CompositorService.useHyprlandFocusGrab
    readonly property bool useBackground: !connected && showBackground && !FrameTransitionState.effectiveFrameEnabled && SettingsData.modalDarkenBackground
    readonly property bool useSingleWindow: connected || CompositorService.isHyprland || useBackground

    signal opened
    signal dialogClosed
    signal backgroundClicked

    Timer {
        id: _syncTimer
        interval: 0
        onTriggered: root._flushSync()
    }

    property bool animationsEnabled: true
    property bool _presentPending: false
    property bool _surfaceFrameReady: false

    property bool _fullSyncPending: false

    function _currentScreenName() {
        return effectiveScreen ? effectiveScreen.name : "";
    }

    Loader {
        id: modalChrome
        active: root.connected
        sourceComponent: ConnectedModalChrome {
            modalHandle: root.modalHandle
            claimPrefix: root.layerNamespace + ":modal"
            surfaceKind: "modal"
            screenName: root._currentScreenName()
            enabled: root.frameOwnsConnectedChrome
            active: root.shouldBeVisible
            presented: root.shouldBeVisible || contentWindow.visible
            dockBlocked: root._dockBlocksEmergence
            dockSide: root.resolvedConnectedBarSide
            onRecoveryRequested: root._queueFullSync()
        }
    }

    function _publishModalChromeState() {
        if (!connected)
            return false;
        const presented = shouldBeVisible || contentWindow.visible;
        const phase = !presented ? "hidden" : (!shouldBeVisible && contentWindow.visible ? "closing" : (!contentWindow.visible ? "opening" : "open"));
        const bodyRect = {
            "x": alignedX + fluidBody.x,
            "y": alignedY + fluidBody.y,
            "width": fluidBody.width,
            "height": fluidBody.height
        };
        const animationOffset = {
            "x": modalContainer.animX,
            "y": modalContainer.animY
        };
        const state = {
            "kind": "modal",
            "screenName": root._currentScreenName(),
            "phase": phase,
            "visible": presented,
            "presented": presented,
            "layer": root.effectiveModalLayer === WlrLayer.Overlay ? "overlay" : "top",
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
        return modalChrome.item?.publish(state) ?? false;
    }

    function _queueFullSync() {
        if (!connected)
            return;
        _fullSyncPending = true;
        if (!_syncTimer.running)
            _syncTimer.restart();
    }
    function _flushSync() {
        if (!_fullSyncPending)
            return;
        _fullSyncPending = false;
        _publishModalChromeState();
    }

    function _syncModalAnim() {
        if (!frameOwnsConnectedChrome)
            return;
        modalChrome.item?.updateAnim(modalContainer.animX, modalContainer.animY);
    }

    function _syncModalBody() {
        if (!frameOwnsConnectedChrome)
            return;
        modalChrome.item?.updateBody(alignedX + fluidBody.x, alignedY + fluidBody.y, fluidBody.width, fluidBody.height);
    }

    function _releaseModalChrome() {
        if (!connected)
            return;
        modalChrome.item?.release();
    }

    function _kickBlurCommit() {
        if (typeof contentWindow.update === "function")
            contentWindow.update();
    }

    function _kickBlurCommitUnlessConnected() {
        if (connected)
            return;
        _kickBlurCommit();
    }

    // Low resource scalar writes: publish synchronously to stay in the same frame
    function _syncAlignedGeometry() {
        if (connected) {
            _syncModalBody();
            return;
        }
        _kickBlurCommit();
    }

    onShouldBeVisibleChanged: {
        morph.retarget(shouldBeVisible ? 1 : 0);
        if (connected) {
            _queueFullSync();
            return;
        }
        _kickBlurCommit();
    }
    onFrameOwnsConnectedChromeChanged: {
        if (!connected)
            return;
        _publishModalChromeState();
    }
    onResolvedConnectedBarSideChanged: {
        if (!connected)
            return;
        _queueFullSync();
    }
    onFluidBodyChanged: {
        if (!connected || !_fluidMotionActive)
            return;
        _syncModalBody();
    }
    onAlignedXChanged: _syncAlignedGeometry()
    onAlignedYChanged: _syncAlignedGeometry()
    onAlignedWidthChanged: _syncAlignedGeometry()
    onAlignedHeightChanged: _syncAlignedGeometry()

    function open() {
        if (!contentWindow.visible)
            _fluidMotionActive = Theme.isFluidEffect;
        closeTimer.stop();
        isClosing = false;
        if (connected) {
            _openConnected();
            return;
        }
        _openStandalone();
    }

    function _openConnected() {
        if (!_fluidMotionActive || !contentWindow.visible)
            animationsEnabled = false;
        const focusedScreen = root.targetScreen ?? CompositorService.getFocusedScreen();
        if (!contentWindow.visible)
            _overStackedModal = ModalManager.hasStackedModal((focusedScreen ?? effectiveScreen)?.name ?? "");
        frozenMotionOffsetX = modalContainer.offsetX;
        frozenMotionOffsetY = modalContainer.offsetY;

        if (focusedScreen)
            contentWindow.screen = focusedScreen;

        ModalManager.openModal(modalHandle);
        if (Theme.isDirectionalEffect)
            contentWindow.visible = true;

        Qt.callLater(() => {
            root.animationsEnabled = true;
            root._present();
        });
    }

    function _openStandalone() {
        const focusedScreen = root.targetScreen ?? CompositorService.getFocusedScreen();
        const screenChanged = focusedScreen && contentWindow.screen !== focusedScreen;
        if (focusedScreen) {
            if (screenChanged)
                contentWindow.visible = false;
            contentWindow.screen = focusedScreen;
        }
        if (screenChanged) {
            Qt.callLater(() => root._finishStandaloneOpen());
            return;
        }
        _finishStandaloneOpen();
    }

    function _finishStandaloneOpen() {
        ModalManager.openModal(modalHandle);
        _present();
    }

    function _present() {
        if (connected) {
            _reveal();
            return;
        }
        if (clickCatcher.item)
            clickCatcher.item.present();
        contentWindow.visible = true;
        if (!_surfaceFrameReady) {
            _presentPending = true;
            return;
        }
        _reveal();
    }

    function _reveal() {
        _presentPending = false;
        shouldBeVisible = true;
        if (clickCatcher.item)
            clickCatcher.item.present();
        contentWindow.visible = true;
        opened();
        shouldHaveFocus = Qt.binding(() => shouldBeVisible);
    }

    on_SurfaceFrameReadyChanged: {
        if (_surfaceFrameReady && _presentPending)
            _reveal();
    }

    function close() {
        if (_presentPending || (_fluidMotionActive && (SettingsData.reduceMotion || animationDuration <= 0))) {
            instantClose();
            return;
        }
        frozenMotionOffsetX = modalContainer.offsetX;
        frozenMotionOffsetY = modalContainer.offsetY;
        isClosing = !connected;
        shouldBeVisible = false;
        shouldHaveFocus = false;
        ModalManager.closeModal(modalHandle);
        closeTimer.restart();
    }

    function instantClose() {
        _presentPending = false;
        animationsEnabled = false;
        isClosing = false;
        shouldBeVisible = false;
        shouldHaveFocus = false;
        ModalManager.closeModal(modalHandle);
        closeTimer.stop();
        contentWindow.visible = false;
        _fluidMotionActive = false;
        dialogClosed();
        Qt.callLater(() => animationsEnabled = true);
    }

    function toggle() {
        shouldBeVisible ? close() : open();
    }

    Connections {
        target: ModalManager
        function onCloseAllModalsExcept(excludedModal) {
            if (excludedModal !== modalHandle && !allowStacking && shouldBeVisible)
                close();
        }
    }

    readonly property var quickshellScreens: Quickshell.screens

    onQuickshellScreensChanged: {
        if (!contentWindow.screen)
            return;
        const currentScreenName = contentWindow.screen.name;
        let screenStillExists = false;
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === currentScreenName) {
                screenStillExists = true;
                break;
            }
        }
        if (screenStillExists) {
            if (shouldBeVisible)
                _queueFullSync();
            return;
        }
        _releaseModalChrome();
        const newScreen = CompositorService.getFocusedScreen();
        if (newScreen) {
            contentWindow.screen = newScreen;
        }
    }

    Timer {
        id: closeTimer
        interval: root.connected ? Math.max(Theme.variantCloseInterval(root.animationDuration), morph.settleDurationMs + 32) : Math.max(root.animationDuration + 50, morph.settleDurationMs + 50)
        onTriggered: {
            if (root.shouldBeVisible)
                return;
            root.isClosing = false;
            contentWindow.visible = false;
            morph.snapTo(0);
            root._fluidMotionActive = false;
            root.dialogClosed();
        }
    }

    readonly property var shadowLevel: Theme.elevationLevel3
    readonly property real shadowFallbackOffset: Theme.spacingS
    readonly property real shadowRenderPadding: (root.enableShadow && Theme.elevationEnabled && SettingsData.modalElevationEnabled) ? Theme.elevationRenderPadding(shadowLevel, Theme.elevationLightDirection, shadowFallbackOffset, 8, 16) : 0
    readonly property real shadowMotionPadding: animationType === "slide" ? 30 : Math.max(0, animationOffset)
    readonly property real shadowBuffer: Theme.snap(shadowRenderPadding + shadowMotionPadding, dpr)
    readonly property real alignedWidth: Theme.px(modalWidth, dpr)
    readonly property real alignedHeight: Theme.px(modalHeight, dpr)

    readonly property real _connectedAlignedX: {
        switch (resolvedConnectedBarSide) {
        case "top":
        case "bottom":
            {
                const insetL = SettingsData.frameEdgeInsetForSide(effectiveScreen, "left");
                const insetR = SettingsData.frameEdgeInsetForSide(effectiveScreen, "right");
                const usable = Math.max(0, screenWidth - insetL - insetR);
                return insetL + Math.max(0, (usable - alignedWidth) / 2);
            }
        case "left":
            return SettingsData.frameEdgeInsetForSide(effectiveScreen, "left");
        case "right":
            return screenWidth - alignedWidth - SettingsData.frameEdgeInsetForSide(effectiveScreen, "right");
        }
        return 0;
    }

    readonly property real _connectedAlignedY: {
        switch (resolvedConnectedBarSide) {
        case "top":
            return SettingsData.frameEdgeInsetForSide(effectiveScreen, "top");
        case "bottom":
            return screenHeight - alignedHeight - SettingsData.frameEdgeInsetForSide(effectiveScreen, "bottom");
        case "left":
        case "right":
            {
                const insetT = SettingsData.frameEdgeInsetForSide(effectiveScreen, "top");
                const insetB = SettingsData.frameEdgeInsetForSide(effectiveScreen, "bottom");
                const usable = Math.max(0, screenHeight - insetT - insetB);
                return insetT + Math.max(0, (usable - alignedHeight) / 2);
            }
        }
        return 0;
    }

    readonly property real alignedX: Theme.snap(frameOwnsConnectedChrome ? _connectedAlignedX : (() => {
            switch (positioning) {
            case "center":
                return (screenWidth - alignedWidth) / 2;
            case "top-right":
                return Math.max(Theme.spacingL, screenWidth - alignedWidth - Theme.spacingL);
            case "custom":
                return customPosition.x;
            default:
                return 0;
            }
        })(), dpr)

    readonly property real alignedY: Theme.snap(frameOwnsConnectedChrome ? _connectedAlignedY : (() => {
            switch (positioning) {
            case "center":
                return (screenHeight - alignedHeight) / 2;
            case "top-right":
                return Theme.barHeight + Theme.spacingXS;
            case "custom":
                return customPosition.y;
            default:
                return 0;
            }
        })(), dpr)

    Loader {
        id: clickCatcher
        active: !root.connected
        sourceComponent: Item {
            id: catcher

            function present() {
                if (!root.useSingleWindow)
                    catcherWindow.visible = true;
            }

            readonly property bool contentWindowVisible: contentWindow.visible

            onContentWindowVisibleChanged: {
                if (!contentWindowVisible && !root.useSingleWindow)
                    catcherWindow.visible = false;
            }

            PanelWindow {
                id: catcherWindow
                screen: contentWindow.screen
                visible: false
                color: "transparent"
                updatesEnabled: false

                WlrLayershell.namespace: root.layerNamespace + ":clickcatcher"
                WlrLayershell.layer: WlrLayershell.Top
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                mask: Region {
                    item: Rectangle {
                        x: root.alignedX
                        y: root.alignedY
                        width: root.alignedWidth
                        height: root.alignedHeight
                    }
                    intersection: Intersection.Xor
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.closeOnBackgroundClick && root.shouldBeVisible
                    onClicked: root.backgroundClicked()
                }
            }
        }
    }

    PanelWindow {
        id: contentWindow
        visible: false
        color: "transparent"

        WindowBlur {
            targetWindow: contentWindow
            blurEnabled: !root.frameOwnsConnectedChrome
            surfaceColor: root.effectiveBackgroundColor
            readonly property real s: Math.min(1, modalContainer.scaleValue)
            readonly property real op: Math.max(0, Math.min(1, (morph.value - 0.06) * 2))
            readonly property real visibleScale: root.connected ? s : s * op
            blurX: root._fluidMotionActive ? (modalReveal.x + modalContainer.x + root.fluidBody.x) : modalReveal.x + modalContainer.x + modalContainer.width * (1 - visibleScale) * 0.5 + Theme.snap(modalContainer.animX, root.dpr)
            blurY: root._fluidMotionActive ? (modalReveal.y + modalContainer.y + root.fluidBody.y) : modalReveal.y + modalContainer.y + modalContainer.height * (1 - visibleScale) * 0.5 + Theme.snap(modalContainer.animY, root.dpr)
            blurWidth: root._fluidMotionActive ? (root.shouldBeVisible ? root.fluidBody.width : 0) : (root.shouldBeVisible && !root.frameOwnsConnectedChrome) ? modalContainer.width * visibleScale : 0
            blurHeight: root._fluidMotionActive ? (root.shouldBeVisible ? root.fluidBody.height : 0) : (root.shouldBeVisible && !root.frameOwnsConnectedChrome) ? modalContainer.height * visibleScale : 0
            blurRadius: root.effectiveCornerRadius
        }

        WlrLayershell.namespace: root.layerNamespace
        WlrLayershell.layer: root.effectiveModalLayer
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: KeyboardFocus.keyboardFocus(root.shouldHaveFocus, root.customKeyboardFocus)

        anchors {
            left: true
            top: true
            right: root.useSingleWindow
            bottom: root.useSingleWindow
        }

        WlrLayershell.margins {
            left: root.useSingleWindow ? 0 : Math.max(0, Theme.snap(root.alignedX - root.shadowBuffer, root.dpr))
            top: root.useSingleWindow ? 0 : Math.max(0, Theme.snap(root.alignedY - root.shadowBuffer, root.dpr))
            right: 0
            bottom: 0
        }

        implicitWidth: root.useSingleWindow ? 0 : root.alignedWidth + (root.shadowBuffer * 2)
        implicitHeight: root.useSingleWindow ? 0 : root.alignedHeight + (root.shadowBuffer * 2)

        onVisibleChanged: {
            if (!visible)
                root._surfaceFrameReady = false;
            if (!visible && Qt.inputMethod) {
                Qt.inputMethod.hide();
                Qt.inputMethod.reset();
            }
            if (!root.connected)
                return;
            if (visible)
                root._publishModalChromeState();
            else
                root._releaseModalChrome();
        }

        Connections {
            target: modalContainer.Window.window
            enabled: contentWindow.visible && !root._surfaceFrameReady

            function onFrameSwapped() {
                root._surfaceFrameReady = true;
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.useSingleWindow && root.closeOnBackgroundClick && root.shouldBeVisible
            z: -2
            onClicked: root.backgroundClicked()
        }

        Rectangle {
            anchors.fill: parent
            z: -1
            color: Theme.backdropColor
            opacity: root.useBackground ? (root.shouldBeVisible ? root.backgroundOpacity : 0) : 0
            visible: root.useBackground

            Behavior on opacity {
                enabled: root.animationsEnabled
                NumberAnimation {
                    easing.type: Easing.BezierSpline
                    duration: root.animationDuration
                    easing.bezierCurve: root.shouldBeVisible ? root.animationEnterCurve : root.animationExitCurve
                }
            }
        }

        Item {
            id: modalReveal
            // Clip to final footprint while frame-owned chrome grows from the bar edge.
            x: root.useSingleWindow ? root.alignedX : root.shadowBuffer
            y: root.useSingleWindow ? root.alignedY : root.shadowBuffer
            width: root.alignedWidth
            height: root.alignedHeight
            clip: root.frameOwnsConnectedChrome

            Item {
                id: modalContainer
                readonly property bool isFloatingWindowSurface: root.isFloatingWindowSurface
                x: root.connected ? Theme.snap(animX, root.dpr) : 0
                y: root.connected ? Theme.snap(animY, root.dpr) : 0

                width: root.alignedWidth
                height: root.alignedHeight

                MouseArea {
                    anchors.fill: parent
                    enabled: root.useSingleWindow && root.shouldBeVisible
                    hoverEnabled: false
                    acceptedButtons: Qt.AllButtons
                    onPressed: mouse => mouse.accepted = true
                    onClicked: mouse => mouse.accepted = true
                    z: -1
                }

                readonly property bool slide: root.animationType === "slide"
                readonly property bool directionalEffect: Theme.isDirectionalEffect
                readonly property bool depthEffect: Theme.isDepthEffect
                readonly property real directionalTravel: Math.max(root.animationOffset, Math.max(root.alignedWidth, root.alignedHeight) * 0.8)
                readonly property real depthTravel: Math.max(root.animationOffset * 0.8, 36)
                readonly property real customAnchorX: root.alignedX + root.alignedWidth * 0.5
                readonly property real customAnchorY: root.alignedY + root.alignedHeight * 0.5
                readonly property real customDistLeft: customAnchorX
                readonly property real customDistRight: root.screenWidth - customAnchorX
                readonly property real customDistTop: customAnchorY
                readonly property real customDistBottom: root.screenHeight - customAnchorY
                readonly property real connectedEmergenceTravelX: Math.max(root.animationOffset, root.alignedWidth + Theme.spacingL)
                readonly property real connectedEmergenceTravelY: Math.max(root.animationOffset, root.alignedHeight + Theme.spacingL)
                readonly property real offsetX: {
                    if (!root.connected)
                        return slide ? 15 : 0;
                    if (root.frameOwnsConnectedChrome) {
                        switch (root.resolvedConnectedBarSide) {
                        case "left":
                            return -connectedEmergenceTravelX;
                        case "right":
                            return connectedEmergenceTravelX;
                        }
                        return 0;
                    }
                    if (slide && !directionalEffect && !depthEffect)
                        return 15;
                    if (directionalEffect) {
                        switch (root.positioning) {
                        case "top-right":
                            return 0;
                        case "custom":
                            if (customDistLeft <= customDistRight && customDistLeft <= customDistTop && customDistLeft <= customDistBottom)
                                return -directionalTravel;
                            if (customDistRight <= customDistTop && customDistRight <= customDistBottom)
                                return directionalTravel;
                            return 0;
                        default:
                            return 0;
                        }
                    }
                    if (depthEffect) {
                        switch (root.positioning) {
                        case "top-right":
                            return 0;
                        case "custom":
                            if (customDistLeft <= customDistRight && customDistLeft <= customDistTop && customDistLeft <= customDistBottom)
                                return -depthTravel;
                            if (customDistRight <= customDistTop && customDistRight <= customDistBottom)
                                return depthTravel;
                            return 0;
                        default:
                            return 0;
                        }
                    }
                    return 0;
                }
                readonly property real offsetY: {
                    if (!root.connected)
                        return slide ? -30 : root.animationOffset;
                    if (root.frameOwnsConnectedChrome) {
                        switch (root.resolvedConnectedBarSide) {
                        case "top":
                            return -connectedEmergenceTravelY;
                        case "bottom":
                            return connectedEmergenceTravelY;
                        }
                        return 0;
                    }
                    if (slide && !directionalEffect && !depthEffect)
                        return -30;
                    if (directionalEffect) {
                        switch (root.positioning) {
                        case "top-right":
                            return -Math.max(directionalTravel * 0.65, 96);
                        case "custom":
                            if (customDistTop <= customDistBottom && customDistTop <= customDistLeft && customDistTop <= customDistRight)
                                return -directionalTravel;
                            if (customDistBottom <= customDistLeft && customDistBottom <= customDistRight)
                                return directionalTravel;
                            return 0;
                        default:
                            return -Math.max(directionalTravel, root.screenHeight * 0.24);
                        }
                    }
                    if (depthEffect) {
                        switch (root.positioning) {
                        case "top-right":
                            return -depthTravel * 0.75;
                        case "custom":
                            if (customDistTop <= customDistBottom && customDistTop <= customDistLeft && customDistTop <= customDistRight)
                                return -depthTravel;
                            if (customDistBottom <= customDistLeft && customDistBottom <= customDistRight)
                                return depthTravel;
                            return depthTravel * 0.45;
                        default:
                            return -depthTravel;
                        }
                    }
                    return root.animationOffset;
                }

                // openProgress spring: 0 = collapsed, 1 = open.
                SpringMotion {
                    id: morph
                    enabled: root.animationsEnabled
                    onValueChanged: root._kickBlurCommitUnlessConnected()
                    reducedMotion: root.animationDuration <= 0
                    positionEpsilon: Math.max(0.001, 0.25 / root.dpr / modalContainer.morphTravelPx)
                    velocityEpsilon: positionEpsilon * damping / Math.max(0.001, 2 * mass)
                    stiffness: Theme.springPreset("default", root.animationDuration).stiffness
                    damping: Theme.springPreset("default", root.animationDuration).damping

                    Component.onCompleted: snapTo(root.shouldBeVisible ? 1 : 0)
                }

                readonly property real animX: root._fluidMotionActive ? 0 : (root.connected ? root.frozenMotionOffsetX : offsetX) * (1 - morph.value)
                readonly property real animY: root._fluidMotionActive ? 0 : (root.connected ? root.frozenMotionOffsetY : offsetY) * (1 - morph.value)
                onAnimXChanged: {
                    if (!root.connected)
                        return;
                    root._syncModalAnim();
                }
                onAnimYChanged: {
                    if (!root.connected)
                        return;
                    root._syncModalAnim();
                }
                readonly property real scaleValue: root._fluidMotionActive ? 1 : root.animationScaleCollapsed + (1.0 - root.animationScaleCollapsed) * morph.value
                readonly property real morphTravelPx: Math.max(1, Math.abs(offsetX), Math.abs(root.frozenMotionOffsetX), Math.abs(offsetY), Math.abs(root.frozenMotionOffsetY), (1 - root.animationScaleCollapsed) * Math.max(root.alignedWidth, root.alignedHeight), root._fluidMotionActive ? Math.max(root.alignedWidth, root.alignedHeight) : 0)

                SurfaceContentClip {
                    id: contentClip

                    active: root._fluidMotionActive
                    body: root.fluidBody
                    targetRect: root.fluidTarget

                    Item {
                        id: animatedContent
                        width: root.alignedWidth
                        height: root.alignedHeight
                        x: root.connected ? 0 : Theme.snap(modalContainer.animX, root.dpr)
                        y: root.connected ? 0 : Theme.snap(modalContainer.animY, root.dpr)
                        clip: false

                        opacity: root._fluidMotionActive || (root.connected && Theme.isDirectionalEffect && !Theme.isConnectedEffect) ? 1 : (root.shouldBeVisible ? 1 : 0)
                        scale: modalContainer.scaleValue

                        Behavior on opacity {
                            enabled: root.animationsEnabled && !root._fluidMotionActive && (!root.connected || !Theme.isDirectionalEffect || Theme.isConnectedEffect)
                            NumberAnimation {
                                duration: root.connected ? Math.round(Theme.variantDuration(root.animationDuration, root.shouldBeVisible) * Theme.variantOpacityDurationScale) : root.animationDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: root.shouldBeVisible ? root.animationEnterCurve : root.animationExitCurve
                            }
                        }

                        ElevationShadow {
                            parent: root._fluidMotionActive ? modalContainer : animatedContent
                            anchors.fill: root._fluidMotionActive ? undefined : parent
                            x: root._fluidMotionActive ? root.fluidBody.x : 0
                            y: root._fluidMotionActive ? root.fluidBody.y : 0
                            width: root._fluidMotionActive ? root.fluidBody.width : animatedContent.width
                            height: root._fluidMotionActive ? root.fluidBody.height : animatedContent.height
                            z: root._fluidMotionActive ? -1 : 0
                            opacity: root._fluidMotionActive ? FluidGeometry.chromeOpacity(morph.value) : 1
                            level: root.shadowLevel
                            fallbackOffset: root.shadowFallbackOffset
                            targetRadius: root.effectiveCornerRadius
                            targetColor: root.frameOwnsConnectedChrome ? Theme.withAlpha(root.effectiveBackgroundColor, 0) : root.effectiveBackgroundColor
                            borderColor: root.frameOwnsConnectedChrome ? Theme.withAlpha(root.effectiveBorderColor, 0) : root.effectiveBorderColor
                            borderWidth: root.frameOwnsConnectedChrome ? 0 : root.effectiveBorderWidth
                            shadowEnabled: !root.frameOwnsConnectedChrome && root.enableShadow && Theme.elevationEnabled && SettingsData.modalElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1"
                        }

                        Rectangle {
                            parent: root._fluidMotionActive ? modalContainer : animatedContent
                            anchors.fill: root._fluidMotionActive ? undefined : parent
                            x: root._fluidMotionActive ? root.fluidBody.x : 0
                            y: root._fluidMotionActive ? root.fluidBody.y : 0
                            width: root._fluidMotionActive ? root.fluidBody.width : animatedContent.width
                            height: root._fluidMotionActive ? root.fluidBody.height : animatedContent.height
                            opacity: root._fluidMotionActive ? FluidGeometry.chromeOpacity(morph.value) : 1
                            radius: root.effectiveCornerRadius
                            color: "transparent"
                            border.color: root.frameOwnsConnectedChrome ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor
                            border.width: root.frameOwnsConnectedChrome ? 0 : BlurService.borderWidth
                            z: 100
                        }

                        FocusScope {
                            anchors.fill: parent
                            focus: root.shouldBeVisible
                            clip: false
                            Keys.forwardTo: root.handleFocusScope ? [root.handleFocusScope, focusScope] : [focusScope]

                            Item {
                                id: directContentWrapper
                                anchors.fill: parent
                                visible: root.directContent !== null
                                focus: true
                                clip: false

                                Component.onCompleted: {
                                    if (root.directContent) {
                                        root.directContent.parent = directContentWrapper;
                                        root.directContent.anchors.fill = directContentWrapper;
                                        Qt.callLater(() => root.directContent.forceActiveFocus());
                                    }
                                }

                                readonly property Item rootDirectContent: root.directContent

                                onRootDirectContentChanged: {
                                    if (rootDirectContent) {
                                        rootDirectContent.parent = directContentWrapper;
                                        rootDirectContent.anchors.fill = directContentWrapper;
                                        Qt.callLater(() => root.directContent.forceActiveFocus());
                                    }
                                }
                            }

                            Loader {
                                id: contentLoader
                                sourceComponent: root.modalHandle.content
                                anchors.fill: parent
                                active: root.directContent === null && (root.keepContentLoaded || root.shouldBeVisible || contentWindow.visible)
                                asynchronous: false
                                focus: true
                                clip: false
                                visible: root.directContent === null

                                onLoaded: {
                                    if (item) {
                                        Qt.callLater(() => item.forceActiveFocus());
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        FocusScope {
            id: focusScope
            objectName: "modalFocusScope"
            anchors.fill: parent
            visible: root.shouldBeVisible || contentWindow.visible
            focus: root.shouldBeVisible
            Keys.onEscapePressed: event => {
                if (root.closeOnEscapeKey && root.shouldHaveFocus) {
                    root.close();
                    event.accepted = true;
                }
            }
        }
    }
}
