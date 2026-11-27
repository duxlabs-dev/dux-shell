pragma Singleton

import QtQuick
import Quickshell
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("SurfaceRecovery")
    property var _windows: []
    property int _nudge: 0

    function track(window) {
        if (!window || _windows.includes(window))
            return;
        _windows = _windows.concat([window]);
    }

    function untrack(window) {
        if (!_windows.includes(window))
            return;
        _windows = _windows.filter(w => w !== window);
    }

    // wlr-layer-shell set_margin: "Setting this value for edges you are not anchored to has no effect"
    function marginNudge(anchored) {
        return anchored ? 0 : _nudge;
    }

    function refreshAll() {
        _nudge = _nudge ? 0 : 1;
        log.info("Refreshed", _windows.length, "layer surfaces");
    }

    function fitsScreen(window) {
        if (!window?.screen || !window.visible)
            return true;
        if (window.width <= 0 || window.height <= 0)
            return false;
        const a = window.anchors;
        if (a.left && a.right && window.width > window.screen.width)
            return false;
        if (a.top && a.bottom && window.height > window.screen.height)
            return false;
        return true;
    }

    function staleWindows() {
        return _windows.filter(w => !fitsScreen(w));
    }
}
