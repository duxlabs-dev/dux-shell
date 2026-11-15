pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/WallpaperFormats.js" as WallpaperFormats
import "../Common/WallpaperMatch.js" as WallpaperMatch

Singleton {
    id: root

    readonly property var log: Log.scoped("WallpaperLibraryService")

    property int refCount: 0
    readonly property bool held: refCount > 0

    readonly property int requiredApiVersion: 41
    readonly property bool connected: DMSService.capabilities.includes("wallpaper") && DMSService.apiVersion >= requiredApiVersion
    readonly property var folders: SessionData.wallpaperFolders
    readonly property bool enabled: folders.length > 0 && connected
    readonly property var visibleFolders: folders.filter(folder => !folder.hidden)
    readonly property var selection: {
        const visible = new Set(visibleFolders.map(folder => folder.path));
        return SessionData.wallpaperFolderSelection.filter(path => visible.has(path));
    }
    readonly property bool filtering: selection.length > 0
    readonly property bool fitFilter: SessionData.wallpaperHideMismatched && enabled

    property var items: []
    property var missing: []
    property bool loaded: false
    property int revision: 0

    property var variantOwners: new Map()
    property int requestId: 0
    property string requestKey: ""
    property bool requestDimensions: false

    onHeldChanged: {
        if (held) {
            Qt.callLater(refresh);
            return;
        }
        requestId++;
        requestKey = "";
        store([], [], false);
    }
    onEnabledChanged: Qt.callLater(refresh)
    onFoldersChanged: Qt.callLater(refresh)
    // Deferred because bindings derived from the selection may not have updated when this fires.
    onSelectionChanged: Qt.callLater(bumpRevision)
    onFitFilterChanged: {
        Qt.callLater(refresh);
        Qt.callLater(bumpRevision);
    }

    function bumpRevision() {
        revision++;
    }

    function refresh() {
        if (!held)
            return;
        if (!enabled) {
            requestId++;
            requestKey = "";
            store([], [], true);
            return;
        }
        const requested = requestFolders();
        const key = JSON.stringify(requested);
        // A list fetched with sizes also serves a request without them.
        if (key === requestKey && (requestDimensions || !fitFilter))
            return;
        requestKey = key;
        requestDimensions = fitFilter;
        const request = ++requestId;
        list(requested, result => {
            if (request !== requestId)
                return;
            if (result) {
                store(result.items ?? [], result.missing ?? [], true);
                return;
            }
            requestKey = "";
            loaded = true;
        });
    }

    function store(newItems, newMissing, isLoaded) {
        const owners = new Map();
        for (const item of newItems) {
            for (const variant of item.variants ?? [])
                owners.set(variant.path, item.path);
        }
        variantOwners = owners;
        items = newItems;
        missing = newMissing;
        loaded = isLoaded;
        revision++;
    }

    // Hidden folders are included: they have to claim their own files.
    function requestFolders() {
        return folders.map(folder => ({
                    "path": folder.path,
                    "recursive": folder.recursive
                }));
    }

    function list(requested, callback) {
        DMSService.sendRequest("wallpaper.list", {
            "folders": requested,
            "extensions": WallpaperFormats.extensions(true),
            "dimensions": fitFilter
        }, response => {
            if (response.error) {
                log.warn("Failed to list wallpapers:", response.error);
                callback(null);
                return;
            }
            const result = response.result;
            if (result.missing.length > 0)
                log.warn("Wallpaper folder not available:", result.missing.join(", "));
            if (result.truncated)
                log.warn("Wallpaper list cut short:", requested.map(folder => folder.path).join(", "));
            callback(result);
        });
    }

    function itemsIn(entries, paths) {
        const wanted = new Set(paths);
        return entries.filter(item => wanted.has(item.folder));
    }

    function selected(entries) {
        return itemsIn(entries, filtering ? selection : visibleFolders.map(folder => folder.path));
    }

    function folderItems(path) {
        return itemsIn(items, [path]);
    }

    // callback gets the listed folder that owns filePath, or "" when none does.
    function folderOf(filePath, callback) {
        DMSService.sendRequest("wallpaper.folderOf", {
            "path": filePath,
            "folders": requestFolders()
        }, response => {
            if (response.error)
                log.warn("Failed to find the wallpaper folder:", response.error);
            callback(response.result ?? "");
        });
    }

    function inPool(ownerPath) {
        const owner = folders.find(folder => folder.path === ownerPath);
        return !!owner && !owner.hidden && (!filtering || selection.includes(ownerPath));
    }

    function physicalSize(screen) {
        const scale = CompositorService.getScreenScale(screen);
        return {
            "width": Math.round(screen.width * scale),
            "height": Math.round(screen.height * scale)
        };
    }

    // Shared mode judges against the screen with the most pixels.
    function fitDisplay(screenName) {
        const screens = Quickshell.screens;
        if (screens.length === 0)
            return null;
        const named = SessionData.perMonitorWallpaper ? SessionData._screenByName(screenName) : null;
        if (named)
            return physicalSize(named);
        let best = null;
        for (let i = 0; i < screens.length; i++) {
            const size = physicalSize(screens[i]);
            if (!best || size.width * size.height > best.width * best.height)
                best = size;
        }
        return best;
    }

    function fitting(entries, screenName) {
        if (!fitFilter)
            return entries;
        const display = fitDisplay(screenName);
        if (!display)
            return entries;
        // The wallpaper on screen stays listed, so it can still be shown as current.
        const current = listedPath(SessionData.perMonitorWallpaper && screenName ? SessionData.getMonitorWallpaper(screenName) : SessionData.wallpaperPath);
        return entries.filter(item => item.path === current || WallpaperMatch.fits(item, display));
    }

    function fits(item, screenName) {
        return !fitFilter || WallpaperMatch.fits(item, fitDisplay(screenName));
    }

    function variantFor(item, screenName) {
        if (fitFilter)
            return WallpaperMatch.variantFor(item, fitDisplay(screenName));
        const screen = SessionData._screenByName(screenName) || Quickshell.screens[0];
        return WallpaperMatch.variantFor(item, screen ? {
            "width": screen.width,
            "height": screen.height
        } : null);
    }

    function variantPath(path, screenName) {
        if (!variantOwners.has(path))
            return path;
        const item = items.find(entry => entry.path === path);
        return item ? variantFor(item, screenName) : path;
    }

    function listedPath(path) {
        return variantOwners.get(path) ?? path;
    }

    function normalizeFolder(path) {
        const absolute = path.startsWith("/") ? path : Paths.strip(Paths.home) + "/" + path;
        const segments = [];
        for (const segment of absolute.split("/")) {
            if (segment === "..")
                segments.pop();
            else if (segment && segment !== ".")
                segments.push(segment);
        }
        return "/" + segments.join("/");
    }

    function folderName(path) {
        return path.replace(/\/+$/, "").split("/").pop() || path;
    }

    function isListed(path) {
        const normalized = normalizeFolder(path);
        return folders.some(folder => folder.path === normalized);
    }

    function warnAlreadyAdded() {
        ToastService.showWarning(I18n.tr("Folder already added", "toast when adding a wallpaper folder that is already listed"));
    }

    function addFolder(path) {
        const normalized = normalizeFolder(path);
        if (isListed(normalized)) {
            warnAlreadyAdded();
            return;
        }
        DMSService.sendRequest("wallpaper.folderListed", {
            "path": normalized,
            "folders": folders.map(folder => folder.path)
        }, response => {
            if (response.error)
                log.warn("Failed to compare wallpaper folders:", response.error);
            if (response.result === true || isListed(normalized)) {
                warnAlreadyAdded();
                return;
            }
            SessionData.set("wallpaperFolders", folders.concat([
                {
                    "path": normalized,
                    "recursive": true,
                    "hidden": false
                }
            ]));
        });
    }

    function removeFolder(path) {
        const remaining = folders.filter(folder => folder.path !== path);
        if (remaining.length === folders.length)
            return false;
        SessionData.set("wallpaperFolders", remaining);
        SessionData.set("wallpaperFolderSelection", SessionData.wallpaperFolderSelection.filter(ticked => ticked !== path));
        return true;
    }

    function updateFolder(path, change) {
        if (!folders.some(folder => folder.path === path))
            return false;
        SessionData.set("wallpaperFolders", folders.map(folder => folder.path === path ? Object.assign({}, folder, change) : folder));
        return true;
    }

    function setFolderHidden(path, hidden) {
        return updateFolder(path, {
            "hidden": !!hidden
        });
    }

    function setFolderRecursive(path, recursive) {
        return updateFolder(path, {
            "recursive": !!recursive
        });
    }

    function toggleSelected(path) {
        const ticked = SessionData.wallpaperFolderSelection;
        SessionData.set("wallpaperFolderSelection", ticked.includes(path) ? ticked.filter(other => other !== path) : ticked.concat([path]));
    }

    function clearSelection() {
        SessionData.set("wallpaperFolderSelection", []);
    }

    function suggestFolders(callback) {
        DMSService.sendRequest("wallpaper.suggestFolders", {
            "folders": folders.map(folder => folder.path)
        }, response => {
            if (response.error)
                log.warn("Failed to suggest wallpaper folders:", response.error);
            callback(response.result ?? []);
        });
    }
}
