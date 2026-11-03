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
    property bool configtoolFound: false
    property bool configtoolProbed: false
    readonly property string currentIMLabel: displayName(fcitxItem ? fcitxItem.tooltipTitle : "", currentIM)
    readonly property string trayIdentity: trayIdentityOf(fcitxItem)
    // Older cores lack the fcitx5.* methods
    readonly property bool editable: available && DMSService.isConnected && DMSService.capabilities.includes("fcitx5")

    onTrayIdentityChanged: {
        if (active && available)
            resolveTimer.restart();
    }

    onActiveChanged: {
        if (active && available)
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

    function request(method, params, callback) {
        DMSService.sendRequest("fcitx5." + method, params, response => {
            if (callback)
                callback(response?.result ?? null, response?.error ?? "");
        });
    }

    function getConfig(uri, callback) {
        request("getConfig", {
            "uri": uri
        }, (result, error) => {
            if (error) {
                ToastService.showError(error);
                return;
            }
            callback(result);
        });
    }

    // Reloads after any outcome, so a rejected value is replaced by the stored one.
    function setConfig(uri, tree, reload) {
        request("setConfig", {
            "uri": uri,
            "value": tree
        }, (result, error) => {
            if (error)
                ToastService.showError(error);
            reload();
        });
    }

    function probeConfigtool() {
        if (configtoolProbed)
            return;
        configtoolProbed = true;
        Proc.runCommand("fcitx5-configtool-check", ["sh", "-c", "command -v fcitx5-configtool"], (output, exitCode) => {
            root.configtoolFound = exitCode === 0;
        });
    }

    function resolve() {
        if (!active || !available)
            return;
        Proc.runCommand("fcitx5-current-im", ["fcitx5-remote", "-n"], (output, exitCode) => {
            if (exitCode !== 0 || !root.active)
                return;
            const name = String(output ?? "").trim();
            if (name !== "")
                root.currentIM = name;
        });
    }
}
