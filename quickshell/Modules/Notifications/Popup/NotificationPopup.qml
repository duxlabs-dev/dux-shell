import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.Common
import qs.Modules.Notifications
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.DCommon.Common as DCommon

PanelWindow {
    id: win

    readonly property bool connectedFrameMode: CompositorService.usesConnectedFrameChromeForScreen(win.screen)
    readonly property bool inlineHeightAnimating: heightMotion.running

    WindowBlur {
        targetWindow: win
        surfaceColor: Theme.notificationFloatingSurface
        readonly property real s: Math.min(1, content.scale) * Math.max(0, content.opacity)
        readonly property real innerW: Math.max(0, content.width - content.cardInset * 2)
        readonly property real innerH: Math.max(0, content.height - content.cardInset * 2)
        blurX: content.x + content.cardInset + swipeTx.x + tx.x + innerW * (1 - s) * 0.5
        blurY: win.contentTop + content.cardInset + swipeTx.y + tx.y + innerH * (1 - s) * 0.5
        blurWidth: win.cardShown && !win.connectedFrameMode ? innerW * s : 0
        blurHeight: win.cardShown && !win.connectedFrameMode ? innerH * s : 0
        blurRadius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : NotificationMetrics.popupRadius
        clipEnabled: true
        clipX: content.x + content.cardInset
        clipY: win.contentTop + content.cardInset
        clipWidth: innerW
        clipHeight: innerH
    }

    WlrLayershell.namespace: "dms:notification-popup"

    required property var notificationData
    required property string notificationId
    readonly property bool hasValidData: notificationData && notificationData.notification
    readonly property alias hovered: cardHoverHandler.hovered
    readonly property alias swipeActive: content.swipeActive
    readonly property alias swipeDismissing: content.swipeDismissing
    readonly property bool swipeDismissTowardEdge: {
        if (content.swipeDismissing)
            return _swipeDismissesTowardFrameEdge();
        if (content.swipeActive)
            return content.swipeOffset * _frameEdgeSwipeDirection() > 0;
        return false;
    }
    readonly property real screenY: stackMotion.value
    readonly property real stackTarget: stackMotion.target
    readonly property bool stackMoving: stackMotion.running
    property real presentationProgress: 0
    property real chromeRelease: 0
    property real layoutHeight: targetAlignedHeight
    property bool _entryStarted: false
    property bool _positioned: false
    readonly property bool presenting: _entryStarted && !_finalized
    readonly property bool cardShown: presenting && (presentationProgress > 0 || !exiting)
    readonly property bool layoutPinned: !exiting && (hovered || contextMenuActive || swipeActive)
    property bool exiting: false
    property var exitSnapshot: null
    property bool exitStarted: false
    property bool collapseChromeOnExit: false
    property bool _isDestroying: false
    property bool _finalized: false
    property bool _inlineGeometryReady: false
    readonly property bool contextMenuActive: transientSurfaces.active
    property bool surfaceReady: false
    property int unmappedSweeps: 0
    onSurfaceReadyChanged: {
        if (surfaceReady && !_isDestroying)
            surfaceMapped();
    }

    TransientSurfaceTracker {
        id: transientSurfaces
    }
    readonly property bool directionalEffect: Theme.isDirectionalEffect
    readonly property bool slideVertical: isCenterPosition
    readonly property real slideTravel: Math.ceil(slideVertical ? content.height : content.width)
    readonly property int slideSideDirection: (SettingsData.notificationPopupPosition === SettingsData.Position.Left || SettingsData.notificationPopupPosition === SettingsData.Position.Bottom) ? -1 : 1
    readonly property int slideEdgeDirection: contentAnchorsTop ? -1 : 1
    property bool descriptionExpanded: false
    readonly property bool bodyClickInvokesAction: SettingsData.notificationPopupBodyInvokesAction && (notificationData?.actions?.length ?? 0) > 0
    onDescriptionExpandedChanged: {
        if (connectedFrameMode)
            popupChromeGeometryChanged();
    }

    signal entered
    signal surfaceMapped
    signal exitRequested
    signal exitFinished
    signal popupHeightChanged
    signal popupChromeGeometryChanged

    function beginEntry() {
        if (_entryStarted || exiting || _isDestroying)
            return;
        _entryStarted = true;
        enterAnimation.restart();
    }

    function setStackPosition(position) {
        if (_isDestroying)
            return;
        if (!_positioned) {
            stackMotion.snapTo(position);
            _positioned = _entryStarted;
            return;
        }
        stackMotion.retarget(position);
    }

    function startExit() {
        if (exiting || _isDestroying)
            return;
        closeTransientUi();
        if (!_entryStarted) {
            forceExit();
            return;
        }
        enterAnimation.stop();
        enterDelay.stop();
        exitSnapshot = snapshotNotification(notificationData);
        exiting = true;
        if (NotificationService.removeFromVisibleNotifications)
            NotificationService.removeFromVisibleNotifications(win.notificationData);
        exitRequested();
    }

    function beginExit(collapseChrome) {
        if (exitStarted || _isDestroying)
            return;
        exiting = true;
        exitStarted = true;
        collapseChromeOnExit = collapseChrome;
        exitWatchdog.restart();
        exitAnim.restart();
        popupChromeGeometryChanged();
    }

    function forceExit() {
        if (_isDestroying) {
            return;
        }
        closeTransientUi();
        _isDestroying = true;
        exiting = true;
        exitStarted = true;
        visible = false;
        exitWatchdog.stop();
        finalizeExit("forced");
    }

    function finalizeExit(reason) {
        if (_finalized) {
            return;
        }

        closeTransientUi();
        _finalized = true;
        _isDestroying = true;
        enterAnimation.stop();
        exitAnim.stop();
        swipeDismissAnim.stop();
        enterDelay.stop();
        exitWatchdog.stop();
        wrapperConn.enabled = false;
        wrapperConn.target = null;
        win.exitFinished();
    }

    // The wrapper is destroyed as soon as its notification closes, which would blank the card mid-exit.
    function snapshotNotification(data) {
        if (!data)
            return null;
        return {
            "appName": data.appName,
            "appIcon": data.appIcon,
            "desktopEntry": data.desktopEntry,
            "summary": data.summary,
            "body": data.body,
            "htmlBody": data.htmlBody,
            "image": data.image,
            "hasDisplayImage": data.hasDisplayImage,
            "displayImage": data.displayImage,
            "persistedImagePath": data.persistedImagePath,
            "timeStr": data.timeStr,
            "urgency": data.urgency,
            "actions": Array.from(data.actions || [], action => ({
                        "text": action.text
                    }))
        };
    }

    function closeTransientUi() {
        transientSurfaces.closeAll();
        popupContextMenuLoader.active = false;
    }

    NotificationActions {
        id: popupActions
    }

    function invokeDefaultAction() {
        const action = popupActions.defaultAction(notificationData);
        if (!action?.invoke)
            return;
        action.invoke();
        NotificationService.dismissNotification(notificationData);
    }

    function dismissPopupReliably() {
        if (!notificationData || win.exiting || win._isDestroying)
            return;
        if (notificationData.timer)
            notificationData.timer.stop();
        notificationData.popup = false;
        startExit();
    }

    visible: !_finalized
    WlrLayershell.layer: {
        const shouldUseOverlay = CompositorService.framePeerSurfacesUseOverlayForScreen(win.screen) || (notificationData && (SettingsData.notificationOverlayEnabled || notificationData.urgency === NotificationUrgency.Critical));
        const fallback = shouldUseOverlay ? WlrLayer.Overlay : WlrLayer.Top;
        return LayerShell.fromEnv("DMS_NOTIFICATION_LAYER", fallback);
    }
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    readonly property real contentImplicitWidth: screen ? Math.min(NotificationMetrics.popupWidth, Math.max(NotificationMetrics.popupMinWidth, screen.width * NotificationMetrics.popupScreenRatio)) : NotificationMetrics.popupWidth
    readonly property real timeoutRailClearance: SettingsData.notificationShowTimeoutBar && notificationData?.timer?.interval > 0 ? Theme.spacingS : 0
    readonly property real contentImplicitHeight: Math.min(notificationCard.targetHeight + content.cardInset * 2 + timeoutRailClearance, (screen?.height ?? NotificationMetrics.centerMaxHeight) * NotificationMetrics.screenHeightRatio)
    readonly property real targetAlignedHeight: Theme.px(Math.max(0, contentImplicitHeight), dpr)
    readonly property real renderedAlignedHeight: heightMotion.value
    property real allocatedAlignedHeight: targetAlignedHeight
    readonly property bool contentAnchorsTop: isTopCenter || SettingsData.notificationPopupPosition === SettingsData.Position.Top || SettingsData.notificationPopupPosition === SettingsData.Position.Left
    readonly property real renderedContentOffsetY: contentAnchorsTop ? 0 : Math.max(0, allocatedAlignedHeight - renderedAlignedHeight)
    readonly property real contentTop: Theme.snap(windowShadowPad + renderedContentOffsetY, dpr)
    implicitWidth: contentImplicitWidth + (windowShadowPad * 2) + edgeBleed
    implicitHeight: allocatedAlignedHeight + (windowShadowPad * 2)

    function syncInlineTargetHeight() {
        if (_isDestroying)
            return;
        const target = Math.max(0, Number(targetAlignedHeight));
        if (isNaN(target))
            return;

        if (!_inlineGeometryReady) {
            heightMotion.snapTo(target);
            allocatedAlignedHeight = target;
            layoutHeight = target;
            return;
        }

        if (target > allocatedAlignedHeight)
            allocatedAlignedHeight = target;
        layoutHeight = target;
        heightMotion.retarget(target);
        if (!heightMotion.running)
            finishInlineHeightAnimation();
    }

    function finishInlineHeightAnimation() {
        const target = Math.max(0, Number(targetAlignedHeight));
        if (isNaN(target))
            return;
        heightMotion.snapTo(target);
        if (Math.abs(allocatedAlignedHeight - target) >= 0.5)
            allocatedAlignedHeight = target;
        layoutHeight = target;
        if (connectedFrameMode)
            popupChromeGeometryChanged();
    }

    onTargetAlignedHeightChanged: syncInlineTargetHeight()
    onRenderedAlignedHeightChanged: {
        if (renderedAlignedHeight > allocatedAlignedHeight + 0.5)
            allocatedAlignedHeight = Math.ceil(renderedAlignedHeight);
        if (connectedFrameMode)
            popupChromeGeometryChanged();
    }
    onAllocatedAlignedHeightChanged: {
        if (connectedFrameMode)
            popupChromeGeometryChanged();
    }

    SpringMotion {
        id: heightMotion
        reducedMotion: !NotificationMetrics.animationsEnabled
        stiffness: NotificationMetrics.stackSpring.stiffness
        damping: NotificationMetrics.stackSpring.damping
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        onRunningChanged: {
            if (!running && win._inlineGeometryReady)
                win.finishInlineHeightAnimation();
        }
    }

    SpringMotion {
        id: stackMotion
        reducedMotion: !NotificationMetrics.animationsEnabled
        stiffness: NotificationMetrics.stackSpring.stiffness
        damping: NotificationMetrics.stackSpring.damping
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
    }

    onHasValidDataChanged: {
        if (!hasValidData && !exiting && !_isDestroying) {
            forceExit();
        }
    }
    Component.onCompleted: {
        heightMotion.snapTo(targetAlignedHeight);
        allocatedAlignedHeight = targetAlignedHeight;
        layoutHeight = targetAlignedHeight;
        _inlineGeometryReady = true;
        if (SettingsData.notificationPopupPrivacyMode)
            descriptionExpanded = false;
        if (!hasValidData)
            forceExit();
    }
    onNotificationDataChanged: {
        if (!_isDestroying) {
            closeTransientUi();
            if (SettingsData.notificationPopupPrivacyMode)
                descriptionExpanded = false;
            wrapperConn.target = win.notificationData || null;
            notificationConn.target = (win.notificationData && win.notificationData.notification && win.notificationData.notification.Retainable) || null;
        }
    }
    onEntered: {
        if (!_isDestroying) {
            enterDelay.start();
        }
    }
    Component.onDestruction: {
        closeTransientUi();
        _isDestroying = true;
        exitWatchdog.stop();
        if (notificationData && notificationData.timer) {
            notificationData.timer.stop();
        }
    }

    property bool isTopCenter: SettingsData.notificationPopupPosition === -1
    property bool isBottomCenter: SettingsData.notificationPopupPosition === SettingsData.Position.BottomCenter
    property bool isCenterPosition: isTopCenter || isBottomCenter
    readonly property real maxPopupShadowBlurPx: Math.max((Theme.elevationLevel3 && Theme.elevationLevel3.blurPx !== undefined) ? Theme.elevationLevel3.blurPx : 12, (Theme.elevationLevel4 && Theme.elevationLevel4.blurPx !== undefined) ? Theme.elevationLevel4.blurPx : 16)
    readonly property real maxPopupShadowOffsetXPx: Math.max(Math.abs(Theme.elevationOffsetX(Theme.elevationLevel3)), Math.abs(Theme.elevationOffsetX(Theme.elevationLevel4)))
    readonly property real maxPopupShadowOffsetYPx: Math.max(Math.abs(Theme.elevationOffsetY(Theme.elevationLevel3, 6)), Math.abs(Theme.elevationOffsetY(Theme.elevationLevel4, 8)))
    readonly property bool popupWindowShadowActive: Theme.elevationEnabled && SettingsData.notificationPopupShadowEnabled && !connectedFrameMode
    readonly property real windowShadowPad: popupWindowShadowActive ? Theme.snap(Math.max(16, maxPopupShadowBlurPx + Math.max(maxPopupShadowOffsetXPx, maxPopupShadowOffsetYPx) + 8), dpr) : 0
    readonly property bool bleedsLeft: _frameEdgeSwipeDirection() < 0
    readonly property real edgeBleed: {
        if (isCenterPosition || !CompositorService.frameWindowVisibleForScreen(screen))
            return 0;
        const sideMargin = bleedsLeft ? getLeftMargin() : getRightMargin();
        return Math.max(0, Theme.snap(sideMargin, dpr) - windowShadowPad);
    }
    readonly property real contentWindowX: Theme.snap(windowShadowPad + (bleedsLeft ? edgeBleed : 0), dpr)

    anchors.top: true
    anchors.left: true
    anchors.bottom: false
    anchors.right: false

    mask: contentInputMask

    Region {
        id: contentInputMask
        item: contentMaskRect
    }

    Item {
        id: contentMaskRect
        visible: false
        x: content.x
        y: win.contentTop
        width: alignedWidth
        height: win.cardShown && !win.exiting && !content.chromeOnlyExit ? alignedHeight : 0
    }

    margins {
        top: getWindowTopMargin()
        bottom: 0
        left: getWindowLeftMargin()
        right: 0
    }

    function getBarInfo() {
        if (!screen)
            return {
                topBar: 0,
                bottomBar: 0,
                leftBar: 0,
                rightBar: 0
            };
        return SettingsData.getAdjacentBarInfo(screen, SettingsData.notificationPopupPosition, {
            id: "notification-popup",
            screenPreferences: [screen.name],
            autoHide: false
        }, true);
    }

    function _frameEdgeInset(side) {
        if (!screen)
            return 0;
        const raw = SettingsData.frameEdgeInsetForSide(screen, side);
        return Math.max(0, Math.round(Theme.px(raw, dpr)));
    }

    readonly property bool frameVisibleWithoutConnectedChrome: CompositorService.frameWindowVisibleForScreen(screen) && !connectedFrameMode

    function _frameGapMargin(side) {
        return _frameEdgeInset(side) + Theme.popupDistance;
    }

    function _connectedCornerClear() {
        if (isCenterPosition || SettingsData.frameCloseGaps)
            return 0;
        return Theme.px(SettingsData.frameRounding, dpr) + Theme.px(Theme.connectedCornerRadius, dpr);
    }

    function getTopMargin() {
        const popupPos = SettingsData.notificationPopupPosition;
        const isTop = isTopCenter || popupPos === SettingsData.Position.Top || popupPos === SettingsData.Position.Left;
        if (!isTop)
            return 0;

        if (connectedFrameMode)
            return _frameEdgeInset("top") + _connectedCornerClear() + screenY;
        if (frameVisibleWithoutConnectedChrome)
            return _frameGapMargin("top") + screenY;
        const barInfo = getBarInfo();
        const base = barInfo.topBar > 0 ? barInfo.topBar : Theme.popupDistance;
        return base + screenY;
    }

    function getBottomMargin() {
        const popupPos = SettingsData.notificationPopupPosition;
        const isBottom = isBottomCenter || popupPos === SettingsData.Position.Bottom || popupPos === SettingsData.Position.Right;
        if (!isBottom)
            return 0;

        if (connectedFrameMode)
            return _frameEdgeInset("bottom") + _connectedCornerClear() + screenY;
        if (frameVisibleWithoutConnectedChrome)
            return _frameGapMargin("bottom") + screenY;
        const barInfo = getBarInfo();
        const base = barInfo.bottomBar > 0 ? barInfo.bottomBar : Theme.popupDistance;
        return base + screenY;
    }

    function getLeftMargin() {
        if (isCenterPosition)
            return screen ? (screen.width - alignedWidth) / 2 : 0;

        const popupPos = SettingsData.notificationPopupPosition;
        const isLeft = popupPos === SettingsData.Position.Left || popupPos === SettingsData.Position.Bottom;
        if (!isLeft)
            return 0;

        if (connectedFrameMode)
            return _frameEdgeInset("left");
        if (frameVisibleWithoutConnectedChrome)
            return _frameGapMargin("left");
        const barInfo = getBarInfo();
        return barInfo.leftBar > 0 ? barInfo.leftBar : Theme.popupDistance;
    }

    function getRightMargin() {
        if (isCenterPosition)
            return 0;

        const popupPos = SettingsData.notificationPopupPosition;
        const isRight = popupPos === SettingsData.Position.Top || popupPos === SettingsData.Position.Right;
        if (!isRight)
            return 0;

        if (connectedFrameMode)
            return _frameEdgeInset("right");
        if (frameVisibleWithoutConnectedChrome)
            return _frameGapMargin("right");
        const barInfo = getBarInfo();
        return barInfo.rightBar > 0 ? barInfo.rightBar : Theme.popupDistance;
    }

    function getContentX() {
        if (!screen)
            return 0;

        const popupPos = SettingsData.notificationPopupPosition;
        const barLeft = getLeftMargin();
        const barRight = getRightMargin();

        if (isCenterPosition)
            return Theme.snap((screen.width - alignedWidth) / 2, dpr);
        if (popupPos === SettingsData.Position.Left || popupPos === SettingsData.Position.Bottom)
            return Theme.snap(barLeft, dpr);
        return Theme.snap(screen.width - alignedWidth - barRight, dpr);
    }

    function getAllocatedContentY() {
        if (!screen)
            return 0;

        const popupPos = SettingsData.notificationPopupPosition;
        const barTop = getTopMargin();
        const barBottom = getBottomMargin();
        const isTop = isTopCenter || popupPos === SettingsData.Position.Top || popupPos === SettingsData.Position.Left;
        if (isTop)
            return Theme.snap(barTop, dpr);
        return Theme.snap(screen.height - allocatedAlignedHeight - barBottom, dpr);
    }

    function getContentY() {
        return Theme.snap(getAllocatedContentY() + renderedContentOffsetY, dpr);
    }

    function getWindowLeftMargin() {
        if (!screen)
            return 0;
        return Theme.snap(getContentX() - contentWindowX, dpr);
    }

    function getWindowTopMargin() {
        if (!screen)
            return 0;
        return Theme.snap(getAllocatedContentY() - windowShadowPad, dpr);
    }

    function _swipeDismissTarget() {
        return (content.swipeDismissDirection < 0 ? -1 : 1) * content.width;
    }

    function _frameEdgeSwipeDirection() {
        const popupPos = SettingsData.notificationPopupPosition;
        return (popupPos === SettingsData.Position.Left || popupPos === SettingsData.Position.Bottom) ? -1 : 1;
    }

    function _swipeDismissesTowardFrameEdge() {
        return content.swipeDismissDirection === _frameEdgeSwipeDirection();
    }

    function popupChromeMotionActive() {
        return presentationProgress < 1 || exiting || content.swipeActive || content.swipeDismissing || Math.abs(content.swipeOffset) > 0.5;
    }

    function swipeReleaseProgress() {
        if (content.swipeDismissing || (content.swipeActive && content.swipeOffset * _frameEdgeSwipeDirection() > 0))
            return Math.max(0, Math.min(1, Math.abs(content.swipeOffset) / Math.max(1, content.swipeTravelDistance)));
        return 0;
    }

    readonly property bool screenValid: win.screen && !_isDestroying
    readonly property real dpr: screenValid ? CompositorService.getScreenScale(win.screen) : 1
    readonly property real alignedWidth: Theme.px(Math.max(0, implicitWidth - (windowShadowPad * 2) - edgeBleed), dpr)
    readonly property real alignedHeight: renderedAlignedHeight
    onScreenYChanged: if (connectedFrameMode)
        popupChromeGeometryChanged()
    onScreenChanged: if (connectedFrameMode)
        popupChromeGeometryChanged()
    onConnectedFrameModeChanged: popupChromeGeometryChanged()
    onAlignedWidthChanged: if (connectedFrameMode)
        popupChromeGeometryChanged()
    onChromeReleaseChanged: if (connectedFrameMode)
        popupChromeGeometryChanged()
    onLayoutHeightChanged: {
        if (_inlineGeometryReady)
            popupHeightChanged();
    }
    onLayoutPinnedChanged: popupHeightChanged()

    Item {
        id: slideClip
        y: win.contentAnchorsTop ? win.contentTop : 0
        width: win.width
        height: win.contentAnchorsTop ? win.height - win.contentTop : win.contentTop + alignedHeight
        clip: win.slideVertical && win.presentationProgress < 1

        Connections {
            target: slideClip.Window.window
            enabled: !win.surfaceReady

            function onFrameSwapped() {
                win.surfaceReady = true;
            }
        }
    }

    Item {
        id: content
        parent: slideClip

        x: win.contentWindowX
        y: win.contentTop - slideClip.y
        width: alignedWidth
        height: alignedHeight
        visible: win.cardShown && !chromeOnlyExit
        transformOrigin: Item.Center

        property real swipeOffset: 0
        property real swipeDismissDirection: 1
        property bool chromeOnlyExit: false
        readonly property real dismissThreshold: width * NotificationMetrics.swipeThreshold
        readonly property real swipeFadeStartRatio: NotificationMetrics.swipeFadeStart
        readonly property real swipeTravelDistance: width
        readonly property real swipeFadeStartOffset: swipeTravelDistance * swipeFadeStartRatio
        readonly property real swipeFadeDistance: Math.max(1, swipeTravelDistance - swipeFadeStartOffset)
        property bool swipeWheelActive: false
        readonly property bool swipeActive: swipeDragHandler.active || swipeWheelActive
        property bool swipeDismissing: false
        onSwipeDismissingChanged: {
            if (!win.connectedFrameMode)
                return;
            win.popupHeightChanged();
            win.popupChromeGeometryChanged();
        }
        onSwipeOffsetChanged: {
            if (win.connectedFrameMode)
                win.popupChromeGeometryChanged();
        }

        function releaseSwipe(velocity = 0) {
            if (win.exiting || swipeDismissing)
                return;
            const projected = swipeOffset + velocity * NotificationMetrics.swipeFlingProjectionMs / 1000;
            if (Math.abs(projected) <= dismissThreshold) {
                swipeOffset = 0;
                return;
            }
            swipeDismissDirection = projected < 0 ? -1 : 1;
            swipeDismissing = true;
            swipeDismissAnim.start();
        }

        readonly property bool shadowsAllowed: win.popupWindowShadowActive
        readonly property var elevLevel: Theme.elevationLevel2
        readonly property real cardInset: Theme.snap(Theme.spacingXS, win.dpr)
        readonly property real shadowRenderPadding: shadowsAllowed ? Theme.snap(Math.max(Theme.spacingL, shadowBlurPx + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)) + Theme.spacingS), win.dpr) : 0
        property real shadowBlurPx: shadowsAllowed ? elevLevel.blurPx : 0
        property real shadowOffsetX: shadowsAllowed ? Theme.elevationOffsetX(elevLevel) : 0
        property real shadowOffsetY: shadowsAllowed ? Theme.elevationOffsetY(elevLevel) : 0
        readonly property int shadowMotionDuration: win.inlineHeightAnimating ? Theme.notificationStackShiftDuration : Theme.shortDuration

        Behavior on shadowBlurPx {
            NumberAnimation {
                duration: content.shadowMotionDuration
                easing.type: Theme.standardEasing
            }
        }

        Behavior on shadowOffsetX {
            NumberAnimation {
                duration: content.shadowMotionDuration
                easing.type: Theme.standardEasing
            }
        }

        Behavior on shadowOffsetY {
            NumberAnimation {
                duration: content.shadowMotionDuration
                easing.type: Theme.standardEasing
            }
        }

        ElevationShadow {
            id: bgShadowLayer
            anchors.fill: parent
            anchors.margins: -content.shadowRenderPadding
            level: content.elevLevel
            fallbackOffset: Theme.elevationOffsetY(content.elevLevel)
            shadowBlurPx: content.shadowBlurPx
            shadowOffsetX: content.shadowOffsetX
            shadowOffsetY: content.shadowOffsetY
            shadowColor: content.shadowsAllowed && content.elevLevel ? Theme.elevationShadowColor(content.elevLevel) : Theme.withAlpha(Theme.elevationShadowColor(content.elevLevel), 0)
            shadowEnabled: !win._isDestroying && win.screenValid && content.shadowsAllowed && !win.connectedFrameMode

            sourceX: content.shadowRenderPadding + content.cardInset
            sourceY: content.shadowRenderPadding + content.cardInset
            sourceWidth: Math.max(0, content.width - (content.cardInset * 2))
            sourceHeight: Math.max(0, content.height - (content.cardInset * 2))
            targetRadius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : NotificationMetrics.popupRadius
            targetColor: Theme.notificationFloatingSurface
            borderColor: win.notificationData && win.notificationData.urgency === NotificationUrgency.Critical ? Theme.withAlpha(Theme.primary, Theme.stateLayerPressed) : Theme.outlineVariant
            borderWidth: win.notificationData && win.notificationData.urgency === NotificationUrgency.Critical ? Theme.outlineWidthFocused : 0
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: content.cardInset
            radius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : NotificationMetrics.popupRadius
            color: "transparent"
            border.color: win.connectedFrameMode ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor
            border.width: win.connectedFrameMode ? 0 : BlurService.borderWidth
            z: 100
        }

        Rectangle {
            id: cardSurface
            anchors.fill: parent
            anchors.margins: content.cardInset
            radius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : NotificationMetrics.popupRadius
            color: "transparent"

            HoverHandler {
                id: cardHoverHandler

                onHoveredChanged: {
                    if (!notificationData || win.exiting || win._isDestroying)
                        return;
                    if (hovered) {
                        if (notificationData.timer)
                            notificationData.timer.stop();
                    } else if (!win.contextMenuActive && notificationData.popup && notificationData.timer) {
                        notificationData.timer.restart();
                    }
                }
            }

            ClippingRectangle {
                width: parent.width
                height: Math.max(0, win.targetAlignedHeight - content.cardInset * 2)
                radius: cardSurface.radius
                color: "transparent"

                DFlickable {
                    anchors.fill: parent
                    anchors.bottomMargin: win.timeoutRailClearance
                    contentHeight: notificationCard.targetHeight
                    clip: true

                    NotificationCard {
                        id: notificationCard
                        surfaceColor: Theme.notificationFloatingSurface
                        chipColor: Theme.notificationChipSurface
                        width: parent.width
                        height: win.inlineHeightAnimating ? Math.min(targetHeight, cardSurface.height - win.timeoutRailClearance) : targetHeight
                        notificationData: win.exitSnapshot ?? win.notificationData
                        descriptionExpanded: win.descriptionExpanded
                        privacyMode: SettingsData.notificationPopupPrivacyMode
                        bodyInvokesAction: win.bodyClickInvokesAction
                        persistImage: true
                        showClose: true
                        revealControls: win.hovered || win.contextMenuActive
                        dismissText: I18n.tr("Clear")
                        animateHeight: false
                        outerRadius: win.connectedFrameMode ? Theme.connectedSurfaceRadius : NotificationMetrics.popupRadius
                        color: "transparent"
                        onExpandRequested: win.descriptionExpanded = !win.descriptionExpanded
                        onCloseRequested: win.dismissPopupReliably()
                        onDismissRequested: {
                            if (win.notificationData && !win.exiting)
                                NotificationService.permanentlyDismissNotification(win.notificationData);
                        }
                        onActionRequested: action => {
                            if (!action?.invoke || win.exiting)
                                return;
                            action.invoke();
                            win.dismissPopupReliably();
                        }
                        onBodyClicked: {
                            if (!win.notificationData || win.exiting)
                                return;
                            if (win.bodyClickInvokesAction) {
                                win.invokeDefaultAction();
                                return;
                            }
                            if (canExpand) {
                                win.descriptionExpanded = !win.descriptionExpanded;
                                return;
                            }
                            if (win.notificationData.actions?.length > 0) {
                                win.notificationData.actions[0].invoke();
                                NotificationService.dismissNotification(win.notificationData);
                                return;
                            }
                            win.dismissPopupReliably();
                        }
                        onContextMenuRequested: (x, y) => {
                            popupContextMenuLoader.active = true;
                            const menu = popupContextMenuLoader.item;
                            if (!menu)
                                return;
                            const point = mapToItem(null, x, y);
                            menu.showAt(win.margins.left + point.x, win.margins.top + point.y, win.screen);
                        }
                    }
                }
            }

            Rectangle {
                id: timeoutBar
                readonly property bool active: SettingsData.notificationShowTimeoutBar && win.notificationData?.timer?.interval > 0
                property real progress: 1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: NotificationMetrics.popupRadius
                anchors.bottomMargin: Theme.spacingXS
                height: NotificationMetrics.railHeight
                radius: Theme.fullRadius(width, height)
                visible: active && progress > 0
                color: Theme.secondaryContainer

                Rectangle {
                    width: parent.width * timeoutBar.progress
                    height: parent.height
                    radius: Theme.fullRadius(width, height)
                    color: Theme.primary
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: NotificationMetrics.railStopSize
                    height: width
                    radius: Theme.fullRadius(width, height)
                    color: Theme.primary
                }

                NumberAnimation {
                    id: progressAnim
                    target: timeoutBar
                    property: "progress"
                    from: 1
                    to: 0
                    duration: win.notificationData?.timer?.interval ?? 0
                    running: timeoutBar.active && win.notificationData?.timer?.running && !win.exiting
                    easing.type: Easing.Linear
                }

                Connections {
                    target: timeoutBar.active ? win.notificationData?.timer : null
                    function onRunningChanged() {
                        if (!win.notificationData?.timer?.running || win.exiting)
                            return;
                        timeoutBar.progress = 1;
                        progressAnim.restart();
                    }
                }
            }
        }

        DragHandler {
            id: swipeDragHandler
            target: null
            xAxis.enabled: true
            yAxis.enabled: false

            onActiveChanged: {
                if (active)
                    return;
                content.releaseSwipe();
            }

            onTranslationChanged: {
                if (win.exiting || content.swipeDismissing)
                    return;

                content.swipeOffset = translation.x;
            }
        }

        opacity: {
            const swipeAmount = Math.abs(content.swipeOffset);
            const revealOpacity = win.directionalEffect ? 1 : win.presentationProgress;
            if (swipeAmount <= content.swipeFadeStartOffset)
                return revealOpacity;
            const fadeProgress = (swipeAmount - content.swipeFadeStartOffset) / content.swipeFadeDistance;
            return Math.max(0, 1 - fadeProgress) * revealOpacity;
        }

        scale: win.directionalEffect ? 1 : Theme.effectScaleCollapsed + (1 - Theme.effectScaleCollapsed) * win.presentationProgress

        Behavior on swipeOffset {
            enabled: !content.swipeActive && !content.swipeDismissing
            NumberAnimation {
                duration: NotificationMetrics.animationsEnabled ? Theme.notificationExitDuration : 0
                easing.type: Theme.standardEasing
            }
        }

        NumberAnimation {
            id: swipeDismissAnim
            target: content
            property: "swipeOffset"
            to: win._swipeDismissTarget()
            duration: NotificationMetrics.animationsEnabled ? Theme.notificationExitDuration : 0
            easing.type: Easing.BezierSpline
            easing.bezierCurve: NotificationMetrics.dismissCurve
            onFinished: {
                content.chromeOnlyExit = true;
                win.startExit();
                NotificationService.dismissNotification(notificationData);
            }
        }

        transform: [
            Translate {
                id: swipeTx
                x: content.swipeOffset
                y: 0
            },
            Translate {
                id: tx
                x: win.slideVertical ? 0 : win.slideSideDirection * win.slideTravel * (1 - win.presentationProgress)
                y: win.slideVertical ? win.slideEdgeDirection * win.slideTravel * (1 - win.presentationProgress) : 0
                onXChanged: {
                    if (win.connectedFrameMode)
                        win.popupChromeGeometryChanged();
                }
                onYChanged: {
                    if (win.connectedFrameMode)
                        win.popupChromeGeometryChanged();
                }
            }
        ]
    }

    // Sits on the untranslated card footprint: inside content the handler would lose the pointer once the card slides past it,
    // and above content so it sees the gesture before DFlickable's blocking vertical handler
    Item {
        parent: slideClip
        x: content.x
        y: content.y
        width: content.width
        height: content.height
        visible: content.visible

        NotificationSwipeWheel {
            enabled: !win.exiting && !content.swipeDismissing
            onBegan: content.swipeWheelActive = true
            onMoved: travel => content.swipeOffset = travel
            onEnded: velocity => {
                content.swipeWheelActive = false;
                content.releaseSwipe(velocity);
            }
        }
    }

    DCommon.DAnim {
        id: enterAnimation
        target: win
        property: "presentationProgress"
        to: 1
        duration: NotificationMetrics.animationsEnabled ? Theme.notificationEnterDuration : 0
        easing.bezierCurve: NotificationMetrics.enterCurve
        onFinished: {
            if (!win.exiting && !win._isDestroying)
                win.entered();
        }
    }

    SequentialAnimation {
        id: exitAnim

        DCommon.DAnim {
            target: win
            property: "presentationProgress"
            to: 0
            duration: NotificationMetrics.animationsEnabled && !content.chromeOnlyExit ? Theme.notificationExitDuration : 0
            easing.bezierCurve: NotificationMetrics.exitCurve
        }

        DCommon.DAnim {
            target: win
            property: "chromeRelease"
            to: 1
            duration: NotificationMetrics.animationsEnabled && win.collapseChromeOnExit ? Theme.notificationStackShiftDuration : 0
            easing.bezierCurve: NotificationMetrics.heightCurve
        }

        onFinished: win.finalizeExit("animation")
    }

    Connections {
        id: wrapperConn

        function onPopupChanged() {
            if (!win.notificationData || win._isDestroying)
                return;
            if (!win.notificationData.popup && !win.exiting)
                startExit();
        }

        target: win.notificationData || null
        ignoreUnknownSignals: true
        enabled: !win._isDestroying
    }

    Connections {
        id: notificationConn

        function onDropped() {
            if (!win._isDestroying && !win.exiting)
                forceExit();
        }

        target: (win.notificationData && win.notificationData.notification && win.notificationData.notification.Retainable) || null
        ignoreUnknownSignals: true
        enabled: !win._isDestroying
    }

    Timer {
        id: enterDelay

        interval: Theme.shortDuration
        repeat: false
        onTriggered: {
            if (notificationData && notificationData.timer && !contextMenuActive && !hovered && !exiting && !_isDestroying)
                notificationData.timer.start();
        }
    }

    Connections {
        target: popupContextMenuLoader.item
        ignoreUnknownSignals: true

        function onVisibleChanged() {
            if (!notificationData?.timer || exiting || _isDestroying)
                return;
            if (win.contextMenuActive) {
                notificationData.timer.stop();
            } else if (!cardHoverHandler.hovered && notificationData.popup) {
                notificationData.timer.restart();
            }
        }
    }

    Timer {
        id: exitWatchdog

        interval: Math.max(600, Theme.notificationExitDuration + Theme.notificationStackShiftDuration + Theme.shortDuration)
        repeat: false
        onTriggered: finalizeExit("watchdog")
    }

    Loader {
        id: popupContextMenuLoader
        active: false

        sourceComponent: NotificationContextMenu {
            transientSurfaceTracker: transientSurfaces
            appName: notificationData?.appName ?? ""
            desktopEntry: notificationData?.desktopEntry ?? ""
            dismissText: notificationCard.dismissText
            notification: notificationData
            onAppMuted: {
                if (notificationData && !win.exiting)
                    NotificationService.dismissNotification(notificationData);
            }
            onDismissRequested: {
                if (notificationData && !win.exiting)
                    NotificationService.permanentlyDismissNotification(notificationData);
            }
        }
    }
}
