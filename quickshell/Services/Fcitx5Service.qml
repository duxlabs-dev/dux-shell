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
