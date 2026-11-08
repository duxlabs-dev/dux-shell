pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Notifications
import qs.Services

QtObject {
    id: manager

    property var modelData
    property int topMargin: 0
    readonly property bool notificationConnectedMode: CompositorService.usesConnectedFrameChromeForScreen(manager.modelData)
    readonly property bool closeGapNotifications: notificationConnectedMode && SettingsData.frameCloseGaps
    readonly property string notifBarSide: {
        const pos = SettingsData.notificationPopupPosition;
        if (pos === -1)
            return "top";
        switch (pos) {
        case SettingsData.Position.Top:
            return "right";
        case SettingsData.Position.Left:
            return "left";
        case SettingsData.Position.BottomCenter:
            return "bottom";
        case SettingsData.Position.Right:
            return "right";
        case SettingsData.Position.Bottom:
            return "left";
        default:
            return "top";
        }
    }
    readonly property real popupSpacing: notificationConnectedMode ? 0 : Theme.groupedListGap
    readonly property int motionStagger: NotificationMetrics.animationsEnabled ? Theme.notificationStackStaggerDuration : 0
    property var popupWindows: []
    property var destroyingWindows: new Set()
    property var pendingDestroys: []
    property int destroyDelayMs: 100
    property bool _chromeSyncPending: false
    property bool _syncingVisibleNotifications: false
    property var _enterQueue: []
    property var _exitQueue: []
    property real _lastEnterMs: 0
    property real _lastExitMs: 0
    readonly property real chromeReleaseTailStart: 0.90
    property Component popupComponent

    popupComponent: Component {
        NotificationPopup {
            onExitFinished: manager._onPopupExitFinished(this)
            onExitRequested: manager._onPopupExitRequested(this)
            onSurfaceMapped: manager._pumpMotion()
            onPopupHeightChanged: manager._onPopupHeightChanged(this)
            onPopupChromeGeometryChanged: manager._onPopupChromeGeometryChanged(this)
        }
    }

    property Connections notificationConnections

    notificationConnections: Connections {
        function onVisibleNotificationsChanged() {
            manager._sync(NotificationService.visibleNotifications);
        }

        target: NotificationService
    }

    property Timer sweeper

    property Timer motionTimer: Timer {
        running: false
        repeat: false
        onTriggered: manager._pumpMotion()
    }

    property Timer destroyTimer: Timer {
        interval: destroyDelayMs
        running: false
        repeat: false
        onTriggered: manager._processDestroyQueue()
    }

    function _processDestroyQueue() {
        if (pendingDestroys.length === 0)
            return;
        const p = pendingDestroys.shift();
        if (p && p.destroy) {
            try {
                p.destroy();
            } catch (e) {}
        }
        if (pendingDestroys.length > 0)
            destroyTimer.restart();
    }

    function _scheduleDestroy(p) {
        if (!p)
            return;
        pendingDestroys.push(p);
        if (!destroyTimer.running)
            destroyTimer.restart();
    }

    sweeper: Timer {
        interval: 500
        running: false
        repeat: true
        onTriggered: {
            const toRemove = [];
            for (const p of popupWindows) {
                if (!p) {
                    toRemove.push(p);
                    continue;
                }
                const neverMapped = !p._entryStarted && !p.surfaceReady && ++p.unmappedSweeps > 1;
                const isZombie = p.status === Component.Null || (!p.visible && !p.exiting) || (!p.notificationData && !p._isDestroying) || (!p.hasValidData && !p._isDestroying) || neverMapped;
                if (isZombie) {
                    toRemove.push(p);
                    if (p.forceExit) {
                        p.forceExit();
                    } else if (p.destroy) {
                        try {
                            p.destroy();
                        } catch (e) {}
                    }
                }
            }
            if (toRemove.length) {
                popupWindows = popupWindows.filter(p => toRemove.indexOf(p) === -1);
                _forgetQueued(toRemove);
                _repositionAll();
            }
            if (popupWindows.length === 0)
                sweeper.stop();
        }
    }

    function _hasWindowFor(w) {
        return popupWindows.some(p => p && p.notificationData === w && !p._isDestroying && p.status !== Component.Null);
    }

    function _isValidWindow(p) {
        return p && p.status !== Component.Null && !p._isDestroying && p.hasValidData;
    }

    function _isLayoutWindow(p) {
        return _isValidWindow(p) && p._entryStarted && !p.exitStarted;
    }

    function _layoutWindows() {
        return popupWindows.filter(_isLayoutWindow);
    }

    function _chromeWindows() {
        return popupWindows.filter(p => _isValidWindow(p) && p.visible && p.presenting);
    }

    function _sync(newWrappers) {
        _syncingVisibleNotifications = true;
        for (const p of popupWindows.slice()) {
            if (!_isValidWindow(p) || p.exiting)
                continue;
            if (p.notificationData && newWrappers.indexOf(p.notificationData) === -1) {
                p.notificationData.removedByLimit = true;
                p.notificationData.popup = false;
            }
        }
        for (const w of newWrappers) {
            if (w && !_hasWindowFor(w) && NotificationService.isFocusedScreen(manager.modelData))
                _insertAtTop(w);
        }
        _syncingVisibleNotifications = false;
        _pumpMotion();
    }

    function _popupHeight(p) {
        return p.layoutHeight + popupSpacing;
    }

    function _insertAtTop(wrapper) {
        if (!wrapper)
            return;
        const notificationId = wrapper?.notification ? wrapper.notification.id : "";
        const win = popupComponent.createObject(null, {
            "notificationData": wrapper,
            "notificationId": notificationId,
            "screen": manager.modelData
        });
        if (!win)
            return;
        if (!win.hasValidData) {
            win.destroy();
            return;
        }
        let insertIndex = 0;
        for (let i = 0; i < popupWindows.length; i++) {
            if (popupWindows[i]?.layoutPinned)
                insertIndex = i + 1;
        }
        popupWindows.splice(insertIndex, 0, win);
        win.setStackPosition(_stackPositionFor(win));
        _enterQueue.push(win);
        if (!sweeper.running)
            sweeper.start();
    }

    function _pumpMotion() {
        const now = Date.now();
        let wait = Infinity;
        while (_enterQueue.length > 0) {
            if (!_enterQueue[0].surfaceReady)
                break;
            const due = _lastEnterMs + motionStagger - now;
            if (due > 0) {
                wait = Math.min(wait, due);
                break;
            }
            _lastEnterMs = now;
            _startEntry(_enterQueue.shift());
        }
        while (_exitQueue.length > 0) {
            const due = _lastExitMs + motionStagger - now;
            if (due > 0) {
                wait = Math.min(wait, due);
                break;
            }
            _lastExitMs = now;
            _startExit(_exitQueue.shift());
        }
        if (wait === Infinity)
            return;
        motionTimer.interval = Math.max(1, Math.round(wait));
        motionTimer.restart();
    }

    function _startEntry(win) {
        if (!_isValidWindow(win) || popupWindows.indexOf(win) === -1)
            return;
        win.beginEntry();
        _repositionAll();
    }

    function _startExit(win) {
        if (!_isValidWindow(win) || popupWindows.indexOf(win) === -1)
            return;
        const collapseChrome = notificationConnectedMode && _chromeWindows().length > 1;
        win.beginExit(collapseChrome);
        _repositionAll();
    }

    function _forgetQueued(windows) {
        _enterQueue = _enterQueue.filter(w => windows.indexOf(w) === -1);
        _exitQueue = _exitQueue.filter(w => windows.indexOf(w) === -1);
    }

    function _stackPositionFor(target) {
        let currentY = topMargin;
        for (const p of popupWindows) {
            if (p === target)
                return currentY;
            if (!_isLayoutWindow(p))
                continue;
            const gap = p.layoutPinned ? Math.max(0, p.stackTarget - currentY) : 0;
            currentY += gap + _popupHeight(p);
        }
        return currentY;
    }

    function _repositionAll() {
        let currentY = topMargin;
        for (const win of _layoutWindows()) {
            const gap = win.layoutPinned ? Math.max(0, win.stackTarget - currentY) : 0;
            const position = currentY + gap;
            win.setStackPosition(position);
            currentY = position + _popupHeight(win);
        }
        _scheduleNotificationChromeSync();
    }

    function _scheduleNotificationChromeSync() {
        if (_chromeSyncPending)
            return;
        _chromeSyncPending = true;
        Qt.callLater(() => {
            _chromeSyncPending = false;
            _syncNotificationChromeState();
        });
    }

    function _clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function _clipRectFromBarSide(rect, visibleFraction) {
        const fraction = _clamp01(visibleFraction);
        const w = Math.max(0, rect.right - rect.x);
        const h = Math.max(0, rect.bottom - rect.y);

        if (notifBarSide === "right") {
            rect.x = rect.right - w * fraction;
        } else if (notifBarSide === "left") {
            rect.right = rect.x + w * fraction;
        } else if (notifBarSide === "bottom") {
            rect.y = rect.bottom - h * fraction;
        } else {
            rect.bottom = rect.y + h * fraction;
        }
        return rect;
    }

    function _popupChromeVisibleFraction(p) {
        const swipe = p.swipeReleaseProgress();
        let swipeVisible = 1;
        if (swipe > 0)
            swipeVisible = p.swipeDismissTowardEdge ? 1 - swipe : 1 - _chromeReleaseTailProgress(swipe);
        return _clamp01(Math.min(p.presentationProgress, swipeVisible));
    }

    function _popupChromeRect(p, useMotionOffset) {
        if (!p || !p.screen)
            return null;
        const x = p.getContentX();
        const y = p.getContentY();
        const w = p.alignedWidth || 0;
        const h = p.alignedHeight || 0;
        if (w <= 0 || h <= 0)
            return null;
        const rect = {
            x: x,
            y: y,
            right: x + w,
            bottom: y + h
        };

        if (p.exiting && p.chromeRelease > 0) {
            const shrink = h * _clamp01(p.chromeRelease);
            if (_stackAnchorsTop())
                rect.bottom = Math.max(rect.y, rect.bottom - shrink);
            else
                rect.y = Math.min(rect.bottom, rect.y + shrink);
        }

        if (!useMotionOffset || p.isCenterPosition)
            return rect;
        return _clipRectFromBarSide(rect, _popupChromeVisibleFraction(p));
    }

    function _chromeReleaseTailProgress(rawProgress) {
        const progress = _clamp01(rawProgress);
        if (progress <= chromeReleaseTailStart)
            return 0;
        return _clamp01((progress - chromeReleaseTailStart) / Math.max(0.001, 1 - chromeReleaseTailStart));
    }

    function _stackAnchorsTop() {
        const pos = SettingsData.notificationPopupPosition;
        return pos === -1 || pos === SettingsData.Position.Top || pos === SettingsData.Position.Left;
    }

    function _frameEdgeInset(side) {
        if (!manager.modelData)
            return 0;
        const raw = SettingsData.frameEdgeReservation(manager.modelData, side);
        const dpr = CompositorService.getScreenScale(manager.modelData);
        return Math.max(0, Math.round(Theme.px(raw, dpr)));
    }

    function _closeGapChromeAnchorEdge(anchorsTop) {
        if (!closeGapNotifications || !manager.modelData)
            return null;
        if (anchorsTop)
            return _frameEdgeInset("top") + topMargin;
        return manager.modelData.height - _frameEdgeInset("bottom") - topMargin;
    }

    function _stackAnchoredChromeEdge(candidates) {
        const anchorsTop = _stackAnchorsTop();
        let edge = anchorsTop ? Infinity : -Infinity;
        for (const p of candidates) {
            const rect = _popupChromeRect(p, false);
            if (!rect)
                continue;
            if (anchorsTop && rect.y < edge)
                edge = rect.y;
            if (!anchorsTop && rect.bottom > edge)
                edge = rect.bottom;
        }
        if (edge === Infinity || edge === -Infinity)
            return null;
        return {
            anchorsTop: anchorsTop,
            edge: edge
        };
    }

    function _syncNotificationChromeState() {
        const screenName = manager.modelData?.name || "";
        if (!screenName)
            return;
        const ownerId = "notification:" + screenName;
        if (!notificationConnectedMode) {
            ConnectedModeState.releaseSurface(screenName, "notification", ownerId);
            return;
        }
        const active = _chromeWindows();
        if (active.length === 0) {
            ConnectedModeState.releaseSurface(screenName, "notification", ownerId);
            return;
        }

        let minX = Infinity;
        let minY = Infinity;
        let maxXEnd = -Infinity;
        let maxYEnd = -Infinity;
        const useMotionOffset = active.length === 1 && active[0].popupChromeMotionActive();
        for (const p of active) {
            const rect = _popupChromeRect(p, useMotionOffset);
            if (!rect)
                continue;
            if (rect.x < minX)
                minX = rect.x;
            if (rect.y < minY)
                minY = rect.y;
            if (rect.right > maxXEnd)
                maxXEnd = rect.right;
            if (rect.bottom > maxYEnd)
                maxYEnd = rect.bottom;
        }
        const stackEdge = _stackAnchoredChromeEdge(active);
        if (stackEdge !== null) {
            if (stackEdge.anchorsTop && stackEdge.edge < minY)
                minY = stackEdge.edge;
            if (!stackEdge.anchorsTop && stackEdge.edge > maxYEnd)
                maxYEnd = stackEdge.edge;
        }
        const anchorsTop = stackEdge !== null ? stackEdge.anchorsTop : _stackAnchorsTop();
        const closeGapAnchorEdge = _closeGapChromeAnchorEdge(anchorsTop);
        if (closeGapAnchorEdge !== null) {
            if (anchorsTop)
                minY = closeGapAnchorEdge;
            else
                maxYEnd = closeGapAnchorEdge;
        }
        if (minX === Infinity || minY === Infinity || maxXEnd <= minX || maxYEnd <= minY) {
            ConnectedModeState.releaseSurface(screenName, "notification", ownerId);
            return;
        }
        const bodyRect = {
            x: minX,
            y: minY,
            width: maxXEnd - minX,
            height: maxYEnd - minY
        };
        ConnectedModeState.claimSurface(screenName, "notification", {
            kind: "notification",
            screenName: screenName,
            phase: "open",
            visible: true,
            presented: true,
            barSide: notifBarSide,
            bodyRect: bodyRect,
            animationOffset: {
                x: 0,
                y: 0
            },
            scale: 1,
            opacity: Theme.connectedSurfaceColor.a,
            bodyX: minX,
            bodyY: minY,
            bodyW: bodyRect.width,
            bodyH: bodyRect.height,
            omitStartConnector: _notificationOmitStartConnector(),
            omitEndConnector: _notificationOmitEndConnector()
        }, ownerId);
    }

    function _notificationOmitStartConnector() {
        return closeGapNotifications && (SettingsData.notificationPopupPosition === SettingsData.Position.Top || SettingsData.notificationPopupPosition === SettingsData.Position.Left);
    }

    function _notificationOmitEndConnector() {
        return closeGapNotifications && (SettingsData.notificationPopupPosition === SettingsData.Position.Right || SettingsData.notificationPopupPosition === SettingsData.Position.Bottom);
    }

    function _onPopupChromeGeometryChanged(p) {
        if (!p || popupWindows.indexOf(p) === -1)
            return;
        _scheduleNotificationChromeSync();
    }

    function _onPopupHeightChanged(p) {
        if (!p || p._isDestroying || popupWindows.indexOf(p) === -1)
            return;
        if (!_syncingVisibleNotifications)
            _repositionAll();
    }

    function _onPopupExitRequested(p) {
        if (!p || popupWindows.indexOf(p) === -1)
            return;
        if (p.notificationData?.removedByLimit) {
            const now = Date.now();
            _lastExitMs = now;
            _lastEnterMs = now;
            _startExit(p);
            _pumpMotion();
            return;
        }
        _exitQueue.push(p);
        _pumpMotion();
    }

    function _onPopupExitFinished(p) {
        if (!p)
            return;
        const windowId = p.toString();
        if (destroyingWindows.has(windowId))
            return;
        destroyingWindows.add(windowId);
        const i = popupWindows.indexOf(p);
        if (i !== -1) {
            popupWindows.splice(i, 1);
            popupWindows = popupWindows.slice();
        }
        _forgetQueued([p]);
        if (NotificationService.releaseWrapper && p.notificationData)
            NotificationService.releaseWrapper(p.notificationData);
        _scheduleDestroy(p);
        Qt.callLater(() => destroyingWindows.delete(windowId));
        _repositionAll();
        _pumpMotion();
    }

    function cleanupAllWindows() {
        sweeper.stop();
        destroyTimer.stop();
        motionTimer.stop();
        pendingDestroys = [];
        _enterQueue = [];
        _exitQueue = [];
        for (const p of popupWindows.slice()) {
            if (p) {
                try {
                    if (p.forceExit) {
                        p.forceExit();
                    } else if (p.destroy) {
                        p.destroy();
                    }
                } catch (e) {}
            }
        }
        popupWindows = [];
        destroyingWindows.clear();
        _chromeSyncPending = false;
        _syncNotificationChromeState();
    }

    Component.onCompleted: _sync(NotificationService.visibleNotifications)
    Component.onDestruction: {
        for (const p of popupWindows)
            p?.destroy();
        const screenName = manager.modelData?.name || "";
        if (screenName)
            ConnectedModeState.releaseSurface(screenName, "notification", "notification:" + screenName);
    }
    onPopupSpacingChanged: _repositionAll()
    onNotificationConnectedModeChanged: _scheduleNotificationChromeSync()
    onCloseGapNotificationsChanged: _scheduleNotificationChromeSync()
    onNotifBarSideChanged: _scheduleNotificationChromeSync()
    onModelDataChanged: _scheduleNotificationChromeSync()
    onTopMarginChanged: _repositionAll()

    onPopupWindowsChanged: {
        if (popupWindows.length > 0 && !sweeper.running) {
            sweeper.start();
        } else if (popupWindows.length === 0 && sweeper.running) {
            sweeper.stop();
        }
    }
}
