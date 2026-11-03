pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtCore
import QtQuick
import qs.Services

Singleton {
    id: root

    readonly property var log: Log.scoped("Paths")

    readonly property url home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property url pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
    readonly property url xdgCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]

    readonly property url data: `${StandardPaths.standardLocations(StandardPaths.GenericDataLocation)[0]}/dms`
    readonly property url state: `${StandardPaths.standardLocations(StandardPaths.GenericStateLocation)[0]}/dms`
    readonly property url cache: `${StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]}/dms`
    readonly property url config: `${StandardPaths.standardLocations(StandardPaths.GenericConfigLocation)[0]}/dms`

    readonly property url imagecache: `${cache}/imagecache`

    property var iconResolver: null
    property var desktopIconResolver: null
    property var trashHandler: null

    Component.onCompleted: mkdir(imagecache)

    function stringify(path: url): string {
        const raw = path.toString();
        try {
            return decodeURIComponent(raw);
        } catch (e) {
            log.warn("failed to decode path:", raw, e);
            return raw;
        }
    }

    function expandTilde(path: string): string {
        if (!path.startsWith("~"))
            return path;
        return strip(root.home) + path.substring(1);
    }

    function shortenHome(path: string): string {
        return path.replace(strip(root.home), "~");
    }

    function strip(path: url): string {
        return stringify(path).replace("file://", "");
    }

    function toFileUrl(path: string): string {
        return path.startsWith("file://") ? path : "file://" + path;
    }

    function mkdir(path: url): void {
        Quickshell.execDetached(["mkdir", "-p", strip(path)]);
    }

    function copy(from: url, to: url): void {
        Quickshell.execDetached(["cp", strip(from), strip(to)]);
    }

    function isSteamApp(appId: string): bool {
        return appId && /^steam_app_\d+$/.test(appId);
    }

    function moddedAppId(appId: string): string {
        const subs = SettingsData.appIdSubstitutions || [];
        for (let i = 0; i < subs.length; i++) {
            const sub = subs[i];
            if (sub.type === "exact" && appId === sub.pattern) {
                return sub.replacement;
            } else if (sub.type === "contains" && appId.includes(sub.pattern)) {
                return sub.replacement;
            } else if (sub.type === "regex") {
                const match = appId.match(new RegExp(sub.pattern));
                if (match) {
                    return sub.replacement.replace(/\$(\d+)/g, (_, n) => match[n] || "");
                }
            }
        }
        const steamMatch = appId.match(/^steam_app_(\d+)$/);
        if (steamMatch)
            return `steam_icon_${steamMatch[1]}`;
        return appId;
    }

    function themedIconPath(name: string): string {
        if (!name)
            return "";
        const themed = iconResolver ? iconResolver(name) : "";
        if (themed)
            return themed;
        return Quickshell.iconPath(name, true);
    }

    function resolveIconPath(iconName: string): string {
        if (!iconName)
            return "";
        const moddedId = moddedAppId(iconName);
        if (moddedId !== iconName) {
            if (moddedId.startsWith("~") || moddedId.startsWith("/"))
                return toFileUrl(expandTilde(moddedId));
            if (moddedId.startsWith("file://"))
                return moddedId;
            return themedIconPath(moddedId);
        }
        if (!desktopIconResolver)
            return themedIconPath(iconName);
        return themedIconPath(iconName) || desktopIconResolver(iconName);
    }

    function trashPath(path: string, callback): void {
        if (!trashHandler)
            return;
        trashHandler(path, callback);
    }

    function copyPathToClipboard(path: string): void {
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", path]);
    }

    function resolveIconUrl(iconName: string): string {
        if (!iconName)
            return "";
        const moddedId = moddedAppId(iconName);
        const target = (moddedId !== iconName) ? moddedId : iconName;
        if (target.startsWith("~") || target.startsWith("/"))
            return toFileUrl(expandTilde(target));
        if (target.startsWith("file://"))
            return target;
        const themed = iconResolver ? iconResolver(target) : "";
        if (themed)
            return themed;
        return "image://icon/" + target;
    }

    function getAppIcon(appId: string, desktopEntry: var): string {
        if (appId === "org.quickshell") {
            return Qt.resolvedUrl("../assets/danklogo.svg");
        }

        const moddedId = moddedAppId(appId);
        if (moddedId !== appId)
            return resolveIconPath(appId);

        if (desktopEntry && desktopEntry.icon) {
            return themedIconPath(desktopEntry.icon);
        }

        const icon = themedIconPath(appId);
        if (icon && icon !== "")
            return icon;

        if (!desktopIconResolver)
            return "";
        return desktopIconResolver(appId);
    }

    readonly property var dmsAppIds: ["org.quickshell", "dev.duxlabs.shell", "com.danklinux.dms"]

    function isDmsAppId(appId: string): bool {
        return dmsAppIds.includes(appId);
    }

    function getAppName(appId: string, desktopEntry: var): string {
        if (isDmsAppId(appId)) {
            return "dms";
        }

        return desktopEntry && desktopEntry.name ? desktopEntry.name : appId;
    }

    function normalizeAppId(id: string): string {
        return id ? String(id).toLowerCase().trim() : "";
    }

    function isAppIdMatch(id: string, target: string, desktopId: string): bool {
        id = normalizeAppId(id);
        desktopId = normalizeAppId(desktopId);
        target = normalizeAppId(target);
        if (!target)
            return false;

        // 1. Substring match
        if (id.includes(target) || desktopId.includes(target)) {
            return true;
        }

        // 2. Match reverse-DNS segments (e.g. app.zen_browser.zen -> zen)
        if (target.indexOf(".") !== -1) {
            const parts = target.split(".");
            const lastPart = parts[parts.length - 1];
            if (lastPart && (id.includes(lastPart) || desktopId.includes(lastPart))) {
                return true;
            }
        }

        // 3. Bidirectional match (longer excluded name contains shorter app id)
        if (id.length >= 3 && target.includes(id)) {
            return true;
        }

        return false;
    }
}
