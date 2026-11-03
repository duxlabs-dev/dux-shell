pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("DesktopService")
    property var _cache: ({})

    property bool isSystemd: false
    property bool systemdAutostartTargetActive: false
    property bool systemdAutostartTargetChecked: Qt.platform.os === "unix"
    readonly property bool autostartAvailable: root.systemdAutostartTargetChecked && (!root.isSystemd || root.systemdAutostartTargetActive)
    property bool _probed: false

    Component.onCompleted: Paths.desktopIconResolver = name => resolveIconPath(name)

    function ensureProbed() {
        if (_probed || systemdAutostartTargetChecked)
            return;
        _probed = true;
        initSystemCheckProcess.running = true;
    }

    Process {
        id: initSystemCheckProcess
        command: ["sh", "-c", "cat /proc/1/comm 2>/dev/null | tr -d '\\n'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.isSystemd = (text || "").trim() === "systemd";
                if (!root.isSystemd)
                    root.systemdAutostartTargetChecked = true;
                else
                    systemdAutostartTargetCheck.running = true;
            }
        }
    }

    Process {
        id: systemdAutostartTargetCheck
        command: ["systemctl", "--user", "is-active", "xdg-desktop-autostart.target"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.systemdAutostartTargetActive = (text || "").trim() === "active";
                root.systemdAutostartTargetChecked = true;
            }
        }
    }

    function resolveIconPath(moddedAppId) {
        if (!moddedAppId)
            return "";

        if (_cache[moddedAppId] !== undefined)
            return _cache[moddedAppId];

        const result = (function () {
                const entry = DesktopEntries.heuristicLookup(moddedAppId);
                let icon = Quickshell.iconPath(entry?.icon, true);
                if (icon && icon !== "")
                    return icon;

                icon = Quickshell.iconPath(moddedAppId, true);
                if (icon && icon !== "")
                    return icon;

                const appIds = [moddedAppId.toLowerCase()];
                const lastPart = moddedAppId.split('.').pop();
                if (lastPart && lastPart !== moddedAppId) {
                    appIds.push(lastPart);
                    appIds.push(lastPart.toLowerCase());
                }

                for (const id of appIds) {
                    icon = Quickshell.iconPath(id, true);
                    if (icon && icon !== "")
                        return icon;
                }

                const strippedId = moddedAppId.replace(/-bin$/, "").toLowerCase();
                const allEntries = DesktopEntries.applications.values;
                for (let i = 0; i < allEntries.length; i++) {
                    const e = allEntries[i];
                    const eId = (e.id || "").toLowerCase();
                    const eName = (e.name || "").toLowerCase();
                    const eExec = (e.execString || "").toLowerCase();

                    if (eId.includes(strippedId) || eName.includes(strippedId) || eExec.includes(strippedId)) {
                        icon = Quickshell.iconPath(e.icon, true);
                        if (icon && icon !== "")
                            return icon;
                    }
                }

                for (const appId of appIds) {
                    let execPath = entry?.execString?.replace(/\/bin.*/, "");
                    if (!execPath)
                        continue;

                    if (execPath.startsWith("/nix/store/") || execPath.startsWith("/gnu/store/")) {
                        const basePath = execPath;
                        const sizes = ["256x256", "128x128", "64x64", "48x48", "32x32", "24x24", "16x16"];

                        let iconPath = `${basePath}/share/icons/hicolor/scalable/apps/${appId}.svg`;
                        icon = Quickshell.iconPath(iconPath, true);
                        if (icon && icon !== "")
                            return icon;

                        for (const size of sizes) {
                            iconPath = `${basePath}/share/icons/hicolor/${size}/apps/${appId}.png`;
                            icon = Quickshell.iconPath(iconPath, true);
                            if (icon && icon !== "")
                                return icon;
                        }
                    }
                }

                return "";
            })();

        _cache[moddedAppId] = result;
        return result;
    }

    signal getDefaultAppResult(string mimeType, string desktopFileId, string callbackId)
    signal getAppsForMimeResult(string mimeType, var appIds, string callbackId)
    signal getHandlersForMimeResult(string mimeType, var apps, string callbackId)

    function setDefaultApp(mimeType, desktopFileId, callbackId = "") {
        setDefaultAppForMimes([mimeType], desktopFileId, callbackId);
    }

    function setDefaultAppForMimes(mimeTypes, desktopFileId, callbackId = "") {
        if (!desktopFileId.endsWith(".desktop")) {
            desktopFileId += ".desktop";
        }
        const filtered = (mimeTypes || []).filter(m => m && m.length > 0);
        if (filtered.length === 0)
            return;
        DMSService.sendRequest("mime.setDefaults", {
            "mimeTypes": filtered,
            "desktopId": desktopFileId
        }, response => {
            if (response.error) {
                log.warn("DesktopService.setDefaultApp failed:", response.error, "mimes:", filtered, "app:", desktopFileId);
            }
        });
    }

    function getDefaultApp(mimeType, callbackId = "") {
        DMSService.sendRequest("mime.getDefault", {
            "mimeType": mimeType
        }, response => {
            if (response.error) {
                log.warn("DesktopService.getDefaultApp failed:", response.error, "mime:", mimeType);
                return;
            }
            const result = response.result || {};
            root.getDefaultAppResult(mimeType, result.desktopId || "", callbackId);
        });
    }

    function getHandlersForMimeType(mimeType, callbackId = "") {
        DMSService.sendRequest("mime.handlersForMime", {
            "mimeType": mimeType
        }, response => {
            if (response.error) {
                log.warn("DesktopService.getHandlersForMimeType failed:", response.error, "mime:", mimeType);
                return;
            }
            const result = response.result || {};
            root.getHandlersForMimeResult(mimeType, result.apps || [], callbackId);
        });
    }

    function getAppsForMimeType(mimeType, callbackId = "") {
        DMSService.sendRequest("mime.appsForMime", {
            "mimeType": mimeType
        }, response => {
            if (response.error) {
                log.warn("DesktopService.getAppsForMimeType failed:", response.error, "mime:", mimeType);
                return;
            }
            const result = response.result || {};
            root.getAppsForMimeResult(mimeType, result.desktopIds || [], callbackId);
        });
    }
}
