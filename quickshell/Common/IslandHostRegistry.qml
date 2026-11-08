pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property var hosts: ({})

    function key(screenName, barId) {
        return JSON.stringify([screenName ?? "", barId ?? ""]);
    }

    function register(key, host) {
        if (hosts[key] === host)
            return;
        const next = Object.assign({}, hosts);
        next[key] = host;
        hosts = next;
    }

    function unregister(key, host) {
        if (!(key in hosts) || (host && hosts[key] !== host))
            return;
        const next = Object.assign({}, hosts);
        delete next[key];
        hosts = next;
    }

    function hostFor(screenName, barId) {
        return hosts[key(screenName, barId)] ?? null;
    }
}
