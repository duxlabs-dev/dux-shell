pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.Common

Singleton {
    id: root

    property var currentPopoutsByScreen: ({})
    property var currentPopoutTriggers: ({})

    // Set by the screenshot IPC handshake (dms screenshot region select); cleared by end() or any popout/modal open.
    property bool screenshotActive: false

    signal popoutOpening
    signal popoutChanged
    signal popoutToggledClosed(string screenName)

    property real hoverCursorGlobalX: 0
    property real hoverCursorGlobalY: 0

    function updateHoverCursor(gx, gy) {
        hoverCursorGlobalX = gx;
        hoverCursorGlobalY = gy;
    }

    function cursorOverBar(gx, gy, padding, excludedWindow) {
        const pad = padding !== undefined ? padding : 16;
        const bars = KeyboardFocus.barWindows || [];
        for (let i = 0; i < bars.length; i++) {
            const w = bars[i];
            if (!w?.visible || w === excludedWindow)
                continue;
            if (typeof w.containsGlobalPoint === "function") {
                if (w.containsGlobalPoint(gx, gy, pad))
                    return true;
                continue;
            }
            const item = w.contentItem;
            if (!item || typeof item.mapToItem !== "function")
                continue;
            const topLeft = item.mapToItem(null, 0, 0);
            if (!topLeft)
                continue;
            if (gx >= topLeft.x - pad && gx < topLeft.x + item.width + pad && gy >= topLeft.y - pad && gy < topLeft.y + item.height + pad)
                return true;
        }
        return false;
    }

    function _openPopout(popout) {
        if (popout.dashVisible !== undefined) {
            let flagStayedTrue = popout.dashVisible === true;
            if (popout.dashVisible && !popout.shouldBeVisible && !popout.isClosing) {
                popout.dashVisible = false;
                flagStayedTrue = false;
            }
            popout.dashVisible = true;
            // Flag already true (e.g. retargeting to another monitor) won't re-fire
            // the change handler, so drive the surface open explicitly.
            if (flagStayedTrue)
                _ensureSurfaceOpen(popout);
            return;
        }
        if (popout.notificationHistoryVisible !== undefined) {
            const flagStayedTrue = popout.notificationHistoryVisible === true;
            popout.notificationHistoryVisible = true;
            if (flagStayedTrue)
                _ensureSurfaceOpen(popout);
            return;
        }
        _ensureSurfaceOpen(popout);
    }

    function _ensureSurfaceOpen(popout) {
        if (typeof popout.present === "function") {
            popout.present();
            return;
        }
        if (typeof popout.open === "function")
            popout.open();
    }

    function _closePopout(popout) {
        try {
            if (popout.hoverDismissEnabled !== undefined)
                popout.hoverDismissEnabled = false;
            switch (true) {
            case popout.dashVisible !== undefined:
                popout.dashVisible = false;
                return;
            case popout.notificationHistoryVisible !== undefined:
                popout.notificationHistoryVisible = false;
                return;
            default:
                if (typeof popout.close !== "function")
                    return;
                popout.close();
            }
        } catch (e) {
            return;
        }
    }

    function _dismissPopoutFromHover(popout) {
        try {
            if (!popout || popout.hoverDismissEnabled !== true)
                return;
            if (typeof popout.closeFromHoverDismiss === "function") {
                popout.closeFromHoverDismiss();
                return;
            }
            _closePopout(popout);
        } catch (e) {
            return;
        }
    }

    function _isStale(popout) {
        try {
            if (!popout || !("shouldBeVisible" in popout))
                return true;
            if (!popout.screen)
                return true;
            return false;
        } catch (e) {
            return true;
        }
    }

    function showPopout(popout) {
        if (!popout || !popout.screen)
            return;
        screenshotActive = false;
        popoutOpening();

        const screenName = popout.screen.name;

        for (const otherScreenName in currentPopoutsByScreen) {
            const otherPopout = currentPopoutsByScreen[otherScreenName];
            if (!otherPopout || otherPopout === popout)
                continue;
            if (_isStale(otherPopout)) {
                currentPopoutsByScreen[otherScreenName] = null;
                continue;
            }
            _closePopout(otherPopout);
        }

        currentPopoutsByScreen[screenName] = popout;
        popoutChanged();
        ModalManager.closeAllModalsExcept(null);
    }

    function hidePopout(popout) {
        if (!popout || !popout.screen)
            return;
        const screenName = popout.screen.name;
        if (currentPopoutsByScreen[screenName] === popout) {
            currentPopoutsByScreen[screenName] = null;
            currentPopoutTriggers[screenName] = null;
            popoutChanged();
        }
    }

    function closeAllPopouts() {
        for (const screenName in currentPopoutsByScreen) {
            const popout = currentPopoutsByScreen[screenName];
            if (!popout || _isStale(popout))
                continue;
            _closePopout(popout);
        }
        // Keep map entries until each popout's close animation finishes (hidePopout).
    }

    function dismissAllForScreen(screenName) {
        if (!screenName)
            return;
        if (currentPopoutsByScreen[screenName])
            closeAllPopouts();
        if (ModalManager.currentModalsByScreen[screenName])
            ModalManager.closeAllModalsExcept(null);
        TrayMenuManager.closeAllMenus();
    }

    function closePopoutForScreen(screen) {
        if (!screen)
            return;
        const screenName = screen.name;
        const popout = currentPopoutsByScreen[screenName];
        if (!popout || _isStale(popout)) {
            currentPopoutsByScreen[screenName] = null;
            currentPopoutTriggers[screenName] = null;
            return;
        }
        _closePopout(popout);
    }

    function dismissHoverPopoutForScreen(screen) {
        if (!screen)
            return;
        const screenName = screen.name;
        const popout = currentPopoutsByScreen[screenName];
        if (!popout || _isStale(popout)) {
            currentPopoutsByScreen[screenName] = null;
            currentPopoutTriggers[screenName] = null;
            return;
        }
        _dismissPopoutFromHover(popout);
    }

    function cancelHoverDismiss(screen) {
        const popout = getActivePopout(screen);
        if (popout?.cancelHoverDismiss)
            popout.cancelHoverDismiss();
    }

    function getActivePopout(screen) {
        if (!screen)
            return null;
        return currentPopoutsByScreen[screen.name] || null;
    }

    // Checks if the active popout is pinned for auto-dismissal
    function isActivePopoutPinned(screen) {
        const p = getActivePopout(screen);
        if (!p || !p.shouldBeVisible)
            return false;
        const dismissSuspended = p.effectiveHoverDismissSuspended ?? p.hoverDismissSuspended;
        return p.hoverDismissEnabled === false || dismissSuspended === true;
    }

    function isCurrentPopout(popout, screenName) {
        const name = screenName || popout?.screen?.name || "";
        return !!name && currentPopoutsByScreen[name] === popout;
    }

    function _requestPopout(popout, tabIndex, triggerSource, hoverRequest) {
        if (!popout || !popout.screen)
            return;

        // Clicks pin a popout, while clicking its active trigger toggles it closed below.
        if (!hoverRequest && popout.hoverDismissEnabled !== undefined)
            popout.hoverDismissEnabled = false;

        screenshotActive = false;
        const screenName = popout.screen.name;
        const currentPopout = currentPopoutsByScreen[screenName];
        const triggerId = triggerSource !== undefined ? triggerSource : tabIndex;
        const alreadyPresented = currentPopout === popout && popout.shouldBeVisible;

        const willOpen = !(alreadyPresented && triggerId !== undefined && currentPopoutTriggers[screenName] === triggerId);
        if (willOpen)
            popoutOpening();

        let movedFromOtherScreen = false;
        for (const otherScreenName in currentPopoutsByScreen) {
            if (otherScreenName === screenName)
                continue;
            const otherPopout = currentPopoutsByScreen[otherScreenName];
            if (!otherPopout)
                continue;

            if (_isStale(otherPopout)) {
                currentPopoutsByScreen[otherScreenName] = null;
                currentPopoutTriggers[otherScreenName] = null;
                continue;
            }

            if (otherPopout === popout) {
                movedFromOtherScreen = true;
                currentPopoutsByScreen[otherScreenName] = null;
                currentPopoutTriggers[otherScreenName] = null;
                continue;
            }

            _closePopout(otherPopout);
        }

        if (currentPopout && currentPopout !== popout) {
            if (_isStale(currentPopout)) {
                currentPopoutsByScreen[screenName] = null;
                currentPopoutTriggers[screenName] = null;
            } else {
                if (hoverRequest && typeof currentPopout.beginSupersededClose === "function")
                    currentPopout.beginSupersededClose();
                _closePopout(currentPopout);
            }
        }

        if (alreadyPresented && !movedFromOtherScreen) {
            const sameDefinedTrigger = triggerId !== undefined && currentPopoutTriggers[screenName] === triggerId;
            if (hoverRequest && sameDefinedTrigger)
                return;

            if (!hoverRequest && (triggerId === undefined || sameDefinedTrigger)) {
                _closePopout(popout);
                popoutToggledClosed(screenName);
                return;
            }

            if (tabIndex !== undefined && popout.currentTabIndex !== undefined) {
                popout.currentTabIndex = tabIndex;
            }
            if (popout.updateSurfacePosition)
                popout.updateSurfacePosition();
            currentPopoutTriggers[screenName] = triggerId;
            if (hoverRequest && popout.hoverDismissEnabled !== undefined)
                popout.hoverDismissEnabled = true;
            return;
        }

        currentPopoutTriggers[screenName] = triggerId;
        currentPopoutsByScreen[screenName] = popout;
        popoutChanged();

        if (tabIndex !== undefined && popout.currentTabIndex !== undefined) {
            popout.currentTabIndex = tabIndex;
        }

        if (currentPopout !== popout) {
            ModalManager.closeAllModalsExcept(null);
        }

        if (hoverRequest && popout.hoverDismissEnabled !== undefined)
            popout.hoverDismissEnabled = true;

        _openPopout(popout);
    }

    function requestPopout(popout, tabIndex, triggerSource) {
        _requestPopout(popout, tabIndex, triggerSource, false);
    }

    function requestHoverPopout(popout, tabIndex, triggerSource) {
        _requestPopout(popout, tabIndex, triggerSource, true);
    }

    function _islandBarBand(host, screen) {
        const vertical = host.edge === "left" || host.edge === "right";
        if (host.embedded) {
            const start = vertical ? host.hostOriginX : host.hostOriginY;
            return {
                "start": start,
                "end": start + host.bandThickness
            };
        }
        if (host.freeMode)
            return null;

        const extent = vertical ? screen.width : screen.height;
        const instances = ShellLayout.forScreen(screen)?.instances ?? [];
        let start = Infinity;
        let end = -Infinity;
        for (const instance of instances) {
            if (instance.edge !== host.edge || instance.barId === host.barId || (instance.kind !== "bar" && instance.kind !== "frame") || instance.rowThickness <= 0)
                continue;
            const config = SettingsData.getBarConfig(instance.barId);
            if (!config || config.enabled === false || config.visible === false)
                continue;
            const near = instance.rowOffset ?? 0;
            const far = near + instance.rowThickness;
            const bandStart = host.edge === "top" || host.edge === "left" ? near : extent - far;
            const bandEnd = host.edge === "top" || host.edge === "left" ? far : extent - near;
            start = Math.min(start, bandStart);
            end = Math.max(end, bandEnd);
        }
        return end > start ? {
            "start": start,
            "end": end
        } : null;
    }

    function getActiveSurfaces() {
        const results = [];

        // The host registry covers embedded, standalone, and free Islands with their live visual bounds.
        for (const key of Object.keys(IslandHostRegistry.hosts || {})) {
            const host = IslandHostRegistry.hosts[key];
            const screen = host?.screen;
            const controller = host?.islandController;
            const snapVisible = controller?.expanded || (!host?.embedded && host?.motionRunning);
            if (!screen?.name || !snapVisible || host.surfaceOpacity <= 0)
                continue;
            const rect = host.surfaceBodyRect?.();
            if (!rect || rect.width <= 0 || rect.height <= 0)
                continue;
            let x = rect.x;
            let y = rect.y;
            let width = rect.width;
            let height = rect.height;
            const barBand = _islandBarBand(host, screen);
            if (barBand) {
                switch (host.edge) {
                case "top":
                    if (y < barBand.end && y + height > barBand.start) {
                        const inset = Math.max(0, Math.min(height, barBand.end - y));
                        y += inset;
                        height -= inset;
                    }
                    break;
                case "bottom":
                    if (y + height > barBand.start && y < barBand.end)
                        height = Math.max(0, barBand.start - y);
                    break;
                case "left":
                    if (x < barBand.end && x + width > barBand.start) {
                        const inset = Math.max(0, Math.min(width, barBand.end - x));
                        x += inset;
                        width -= inset;
                    }
                    break;
                case "right":
                    if (x + width > barBand.start && x < barBand.end)
                        width = Math.max(0, barBand.start - x);
                    break;
                }
            }
            const left = Math.max(0, x);
            const top = Math.max(0, y);
            const right = Math.min(screen.width, x + width);
            const bottom = Math.min(screen.height, y + height);
            if (right <= left || bottom <= top)
                continue;
            results.push({
                "name": "dms:dankisland-surface",
                "type": "island",
                "x": Math.round((screen.x ?? 0) + left),
                "y": Math.round((screen.y ?? 0) + top),
                "width": Math.round(right - left),
                "height": Math.round(bottom - top)
            });
        }

        for (const screenName in currentPopoutsByScreen) {
            const popout = currentPopoutsByScreen[screenName];
            if (!popout || !popout.shouldBeVisible)
                continue;

            const host = popout.impl?.item ?? popout;
            if (!host || !host.shouldBeVisible || host.isClosing)
                continue;

            const screen = host.surfaceScreen ?? popout.screen ?? null;
            const sx = screen?.x ?? 0;
            const sy = screen?.y ?? 0;
            const px = host.renderedAlignedX;
            const py = host.renderedAlignedY;
            const pw = host.renderedAlignedWidth ?? popout.popupWidth ?? 0;
            const ph = host.renderedAlignedHeight ?? popout.popupHeight ?? 0;

            // Skip if origin is not yet laid out (undefined/null means not positioned).
            if (px == null || py == null || pw <= 0 || ph <= 0)
                continue;

            results.push({
                "name": popout.layerNamespace || "popout",
                "type": "popout",
                "x": Math.round(sx + px),
                "y": Math.round(sy + py),
                "width": Math.round(pw),
                "height": Math.round(ph)
            });
        }

        const modals = ModalManager.currentModalsByScreen || {};
        for (const screenName in modals) {
            const modal = modals[screenName];
            if (!modal || !modal.shouldBeVisible)
                continue;

            const host = modal.impl?.item ?? modal;
            if (!host || !host.shouldBeVisible || host.isClosing)
                continue;

            const screen = host.effectiveScreen ?? modal.targetScreen ?? null;
            const sx = screen?.x ?? 0;
            const sy = screen?.y ?? 0;
            const mx = host.alignedX;
            const my = host.alignedY;
            const mw = host.alignedWidth ?? modal.modalWidth ?? 0;
            const mh = host.alignedHeight ?? modal.modalHeight ?? 0;

            // Skip if origin is not yet laid out.
            if (mx == null || my == null || mw <= 0 || mh <= 0)
                continue;

            results.push({
                "name": modal.layerNamespace || "modal",
                "type": "modal",
                "x": Math.round(sx + mx),
                "y": Math.round(sy + my),
                "width": Math.round(mw),
                "height": Math.round(mh)
            });
        }

        return results;
    }
}
