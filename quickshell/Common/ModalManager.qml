pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

Singleton {
    id: modalManager

    signal closeAllModalsExcept(var excludedModal)
    signal modalChanged

    property var currentModalsByScreen: ({})
    property var _stackedModals: []

    // Frame-painted chrome sits under every Top-layer window, so a surface opened over one must paint its own.
    function hasStackedModal(screenName) {
        return _stackedModals.some(modal => modal.shouldBeVisible && !modal.useOverlayLayer && modal.effectiveScreen?.name === screenName);
    }

    function openModal(modal) {
        PopoutManager.screenshotActive = false;
        if (modal.allowStacking)
            _stackedModals = _stackedModals.filter(other => other !== modal && other.shouldBeVisible).concat([modal]);
        const screenName = modal.effectiveScreen?.name ?? "unknown";
        var next = {};
        for (var k in currentModalsByScreen)
            next[k] = currentModalsByScreen[k];
        next[screenName] = modal;
        currentModalsByScreen = next;
        modalChanged();
        Qt.callLater(() => {
            if (!modal.allowStacking)
                closeAllModalsExcept(modal);
            if (!modal.keepPopoutsOpen)
                PopoutManager.closeAllPopouts();
            TrayMenuManager.closeAllMenus();
        });
    }

    function isCurrentModal(modal, screenName) {
        const name = screenName || modal?.effectiveScreen?.name || "unknown";
        return currentModalsByScreen[name] === modal;
    }

    function closeModal(modal) {
        _stackedModals = _stackedModals.filter(other => other !== modal);
        const screenName = modal.effectiveScreen?.name ?? "unknown";
        if (currentModalsByScreen[screenName] === modal) {
            var next = {};
            for (var k in currentModalsByScreen) {
                if (k !== screenName)
                    next[k] = currentModalsByScreen[k];
            }
            currentModalsByScreen = next;
            modalChanged();
        }
    }
}
