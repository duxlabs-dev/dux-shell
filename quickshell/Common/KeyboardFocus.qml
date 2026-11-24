pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

// Manages keyboard focus policy for popouts, modals, and Hyprland focus grabs
Singleton {
    id: root

    function keyboardFocus(active, customFocus) {
        if (PopoutManager.screenshotActive)
            return WlrKeyboardFocus.None;
        if (customFocus !== null && customFocus !== undefined)
            return customFocus;
        if (!active)
            return WlrKeyboardFocus.None;
        if (CompositorService.useHyprlandFocusGrab)
            return WlrKeyboardFocus.OnDemand;
        return WlrKeyboardFocus.Exclusive;
    }

    function wantsGrab(active, customFocus) {
        return CompositorService.useHyprlandFocusGrab && keyboardFocus(active, customFocus) === WlrKeyboardFocus.OnDemand;
    }

    function captureActiveToplevel() {
        return ToplevelManager.activeToplevel;
    }

    function restoreToplevel(toplevel) {
        if (toplevel)
            Qt.callLater(() => toplevel.activate());
        return null;
    }

    property list<var> barWindows: []

    function registerBarWindow(window) {
        if (!window || barWindows.indexOf(window) !== -1)
            return;
        barWindows = barWindows.concat([window]);
    }

    function unregisterBarWindow(window) {
        const idx = barWindows.indexOf(window);
        if (idx === -1)
            return;
        const next = barWindows.slice();
        next.splice(idx, 1);
        barWindows = next;
    }

    // Popout and island focus grabs admit these, so clicking one doesn't dismiss them.
    property list<var> grabPeerWindows: []

    function registerGrabPeerWindow(window) {
        if (window && grabPeerWindows.indexOf(window) === -1)
            grabPeerWindows = grabPeerWindows.concat([window]);
    }

    function unregisterGrabPeerWindow(window) {
        grabPeerWindows = grabPeerWindows.filter(w => w !== window);
    }
}
