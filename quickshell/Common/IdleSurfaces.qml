pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property var surfaces: ({})

    function key(kind, screenName) {
        return kind + "|" + (screenName ?? "");
    }

    function register(kind, screenName, surface) {
        const k = key(kind, screenName);
        if (surfaces[k] === surface)
            return;
        const next = Object.assign({}, surfaces);
        next[k] = surface;
        surfaces = next;
    }

    function unregister(kind, screenName, surface) {
        const k = key(kind, screenName);
        if (surfaces[k] !== surface)
            return;
        const next = Object.assign({}, surfaces);
        delete next[k];
        surfaces = next;
    }

    function surfaceFor(kind, screenName) {
        return surfaces[key(kind, screenName)] ?? null;
    }
}
