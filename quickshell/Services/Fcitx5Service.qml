pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Common

Singleton {
    id: root

    property int consumers: 0
    readonly property bool active: consumers > 0

    // No D-Bus event to check for IME changes, so use the system tray item to check
    readonly property var fcitxItem: findItem(SystemTray.items.values)
    readonly property bool available: fcitxItem !== null
    property string currentIM: ""
    readonly property string currentIMLabel: displayName(fcitxItem ? fcitxItem.tooltipTitle : "", currentIM)
    readonly property string trayIdentity: trayIdentityOf(fcitxItem)
    readonly property bool editable: available && DMSService.isConnected && DMSService.capabilities.includes("fcitx5")

    onTrayIdentityChanged: {
        if (active && editable)
            resolveTimer.restart();
    }

    onEditableChanged: {
        if (active && editable)
            resolveTimer.restart();
    }

    onActiveChanged: {
        if (active && editable)
            resolveTimer.restart();
    }

    Timer {
        id: resolveTimer

        interval: 100
        repeat: false
        onTriggered: root.resolve()
    }

    function findItem(items) {
        return items.find(item => item?.id === "Fcitx") ?? null;
    }

    function trayIdentityOf(item) {
        return item ? item.icon + "\u0000" + item.tooltipTitle : "";
    }

    // Keyboard variants are like "Keyboard - English (US) - English (US, intl.)", only use the part after " - "
    function displayName(tooltipTitle, rawName) {
        const title = String(tooltipTitle ?? "").trim();
        if (title === "" || title === "Input Method")
            return rawName;
        const separator = title.lastIndexOf(" - ");
        return separator > 0 ? title.slice(separator + 3) : title;
    }

    function request(method, params, callback, quiet) {
        DMSService.sendRequest("fcitx5." + method, params, response => {
            const error = response?.error ?? "";
            if (error && !quiet)
                ToastService.showError(error);
            if (callback)
                callback(response?.result ?? null, error);
        });
    }

    function getConfig(uri, callback) {
        request("getConfig", {
            "uri": uri
        }, (result, error) => {
            if (!error)
                callback(result);
        });
    }

    function setConfig(uri, tree, reload) {
        request("setConfig", {
            "uri": uri,
            "value": tree
        }, reload);
    }

    function resolve() {
        if (!active || !editable)
            return;
        request("currentIM", {}, (result, error) => {
            const name = String(result?.name ?? "").trim();
            if (name !== "")
                root.currentIM = name;
        }, true);
    }
}
