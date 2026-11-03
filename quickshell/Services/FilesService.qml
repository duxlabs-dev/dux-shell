pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Services

Singleton {
    id: root

    readonly property bool connected: DMSService.isConnected && DMSService.subscribeConnected && DMSService.capabilities.includes("files")
    readonly property var capabilities: ({
            "mkdir": true,
            "rename": true,
            "trash": true
        })
    property var userDirs: []
    property int refCount: 0

    signal watchEvent(var data)

    onRefCountChanged: {
        if (refCount > 0) {
            ensureSubscription();
        } else if (refCount === 0 && DMSService.activeSubscriptions.includes("files")) {
            DMSService.removeSubscription("files");
        }
    }

    function addRef() {
        refCount++;
    }

    function removeRef() {
        refCount = Math.max(0, refCount - 1);
    }

    function ensureSubscription() {
        if (DMSService.activeSubscriptions.includes("files"))
            return;
        if (DMSService.activeSubscriptions.includes("all"))
            return;
        DMSService.addSubscription("files");
    }

    onConnectedChanged: {
        if (connected)
            refreshUserDirs();
    }

    function refreshUserDirs() {
        _send("files.userDirs", null, result => {
            if (result.error)
                return;
            root.userDirs = result.dirs || [];
        });
    }

    function watch(path, options, callback) {
        ensureSubscription();
        _send("files.watch", Object.assign({
            "path": path
        }, _options(options)), callback);
    }

    function page(watchId, options, callback) {
        _send("files.list", Object.assign({
            "watchId": watchId
        }, _options(options)), callback);
    }

    function unwatch(watchId) {
        if (!watchId)
            return;
        _send("files.unwatch", {
            "watchId": watchId
        }, null);
    }

    function stat(path, callback) {
        _send("files.stat", {
            "path": path
        }, callback);
    }

    function count(paths, includeHidden, callback) {
        _send("files.count", {
            "paths": paths,
            "includeHidden": includeHidden === true
        }, callback);
    }

    function thumbnails(paths, size, watchId, callback) {
        const params = {
            "paths": paths,
            "size": size || "normal"
        };
        if (watchId)
            params.watchId = watchId;
        _send("files.thumbnail", params, callback);
    }

    function mkdir(path, callback) {
        _send("files.mkdir", {
            "path": path
        }, callback);
    }

    function rename(path, name, callback) {
        _send("files.rename", {
            "path": path,
            "name": name
        }, callback);
    }

    function trash(paths, callback) {
        _send("files.trash", {
            "paths": paths
        }, callback);
    }

    function _options(options) {
        const opts = options || {};
        const params = {};
        if (opts.includeHidden !== undefined)
            params.includeHidden = opts.includeHidden;
        if (opts.filters !== undefined)
            params.filters = opts.filters;
        if (opts.sortKey)
            params.sort = opts.sortKey;
        if (opts.sortDesc !== undefined)
            params.desc = opts.sortDesc;
        if (opts.dirsFirst !== undefined)
            params.dirsFirst = opts.dirsFirst;
        if (opts.limit)
            params.limit = opts.limit;
        if (opts.cursor)
            params.cursor = opts.cursor;
        return params;
    }

    function _send(method, params, callback) {
        DMSService.sendRequest(method, params, response => {
            if (!callback)
                return;
            if (response.error) {
                callback({
                    "error": response.error,
                    "code": response.code || ""
                });
                return;
            }
            callback(response.result || {});
        });
    }

    Connections {
        target: DMSService

        function onFilesEvent(data) {
            root.watchEvent(data);
        }
    }
}
