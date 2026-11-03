pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("ClipboardService")

    readonly property int longTextThreshold: 200

    readonly property bool clipboardAvailable: DMSService.isConnected && (DMSService.capabilities.length === 0 || DMSService.capabilities.includes("clipboard"))
    property bool pasteSupported: false
    readonly property bool pasteAvailable: clipboardAvailable && pasteSupported

    readonly property var terminalAppIds: ["kitty", "foot", "footclient", "alacritty", "st", "org.wezfurlong.wezterm", "com.mitchellh.ghostty", "ghostty", "org.kde.konsole", "konsole", "org.gnome.terminal", "gnome-terminal-server", "org.gnome.console", "kgx", "com.gexperts.tilix", "tilix", "terminator", "xfce4-terminal", "lxterminal", "deepin-terminal", "io.elementary.terminal", "rio", "contour", "wayst", "urxvt", "rxvt"]

    property var internalEntries: []
    property var clipboardEntries: []
    property var unpinnedEntries: []
    property var pinnedEntries: []
    property int pinnedCount: 0
    property int totalCount: 0
    property string searchText: ""
    property string activeFilter: "all"
    readonly property bool filterActive: searchText.trim().length > 0 || activeFilter !== "all"
    property int selectedIndex: 0
    property bool keyboardNavigationActive: false
    property int refCount: 0
    property bool _pasteSupportChecked: false
    property bool _launcherCacheValid: false
    property string _launcherCachedQuery: ""
    property var _launcherCachedEntries: []
    property int _launcherSearchSeq: 0

    signal historyCopied
    signal historyCleared
    signal launcherSearchReady(string query)

    Timer {
        id: pasteTimer
        interval: 200
        repeat: false
        onTriggered: root.sendPasteKeystroke()
    }

    Process {
        id: pasteCommand
        onExited: pasteTimer.start()
    }

    Connections {
        target: DMSService
        function onIsConnectedChanged() {
            root.refreshPasteSupport();
        }
    }

    // subscribed for the shell's lifetime; resubscribing replays every service's snapshot
    Component.onCompleted: DMSService.addSubscription("clipboard")

    onRefCountChanged: {
        if (refCount > 0 && !_pasteSupportChecked)
            refreshPasteSupport();
    }

    function refreshPasteSupport() {
        if (!DMSService.isConnected) {
            pasteSupported = false;
            _pasteSupportChecked = false;
            return;
        }
        _pasteSupportChecked = true;
        DMSService.sendRequest("clipboard.pasteSupported", null, function (response) {
            root.pasteSupported = !response.error && response.result && response.result.supported === true;
        });
    }

    function isTerminalFocused() {
        const appId = (ToplevelManager.activeToplevel?.appId ?? "").toLowerCase();
        if (!appId) {
            return false;
        }
        return terminalAppIds.includes(appId) || appId.endsWith("term") || appId.includes("terminal");
    }

    function pasteAfterCommand(command) {
        pasteCommand.command = command;
        pasteCommand.running = true;
    }

    function sendPasteKeystroke() {
        DMSService.sendRequest("clipboard.sendPaste", {
            "shift": isTerminalFocused()
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Paste failed: %1", "clipboard error toast, %1 is the error message").arg(response.error));
            }
        });
    }

    function updateFilteredModel() {
        const query = searchText.trim().toLowerCase();
        const filterAll = activeFilter === "all";
        const unpinned = [];
        const pinned = [];

        for (let i = 0; i < internalEntries.length; i++) {
            const entry = internalEntries[i];
            if (!filterAll && getEntryType(entry) !== activeFilter)
                continue;
            if (query.length > 0 && !entry.preview.toLowerCase().includes(query))
                continue;
            (entry.pinned ? pinned : unpinned).push(entry);
        }

        // JS Date keeps milliseconds only, so rows sharing one get id as the tie-break.
        const byTimestampDesc = (a, b) => (new Date(b.timestamp) - new Date(a.timestamp)) || (b.id - a.id);
        pinned.sort(byTimestampDesc);
        unpinned.sort(byTimestampDesc);

        pinnedEntries = pinned;
        unpinnedEntries = unpinned;
        clipboardEntries = pinned.concat(unpinned);
        totalCount = clipboardEntries.length;

        const activeCount = Math.max(unpinned.length, pinned.length);

        if (activeCount === 0) {
            keyboardNavigationActive = false;
            selectedIndex = 0;
            return;
        }

        if (selectedIndex >= activeCount)
            selectedIndex = activeCount - 1;
    }

    function refresh() {
        if (!clipboardAvailable) {
            return;
        }
        DMSService.sendRequest("clipboard.getHistory", null, function (response) {
            if (response.error) {
                log.warn("Failed to get history:", response.error);
                return;
            }
            applyHistory(response.result || []);
        });
    }

    function applyHistory(history) {
        internalEntries = history;
        pinnedCount = history.filter(e => e.pinned).length;
        updateFilteredModel();
    }

    function requestLauncherSearch(query, limit) {
        if (!clipboardAvailable) {
            return;
        }
        if (!_pasteSupportChecked)
            refreshPasteSupport();

        const trimmed = (query || "").toString().trim();
        const maxItems = limit > 0 ? limit : 20;
        if (_launcherCacheValid && _launcherCachedQuery === trimmed) {
            return;
        }

        _launcherSearchSeq++;
        const seq = _launcherSearchSeq;
        DMSService.sendRequest("clipboard.search", {
            "query": trimmed,
            "limit": maxItems
        }, function (response) {
            if (seq !== _launcherSearchSeq) {
                return;
            }
            if (response.error) {
                log.warn("Launcher clipboard search failed:", response.error);
                _launcherCacheValid = true;
                _launcherCachedQuery = trimmed;
                _launcherCachedEntries = [];
                launcherSearchReady(trimmed);
                return;
            }
            const result = response.result || {};
            _launcherCacheValid = true;
            _launcherCachedQuery = trimmed;
            _launcherCachedEntries = result.entries || [];
            launcherSearchReady(trimmed);
        });
    }

    function getCachedLauncherSearchEntries(query, limit) {
        if (!clipboardAvailable) {
            return [];
        }

        const trimmed = (query || "").toString().trim();
        const maxItems = limit > 0 ? limit : 20;
        if (!_launcherCacheValid || _launcherCachedQuery !== trimmed) {
            requestLauncherSearch(trimmed, maxItems);
            return [];
        }
        return _launcherCachedEntries.slice(0, maxItems);
    }

    function invalidateLauncherSearchCache() {
        _launcherCacheValid = false;
        _launcherCachedQuery = "";
        _launcherCachedEntries = [];
        _launcherSearchSeq++;
    }

    function reset() {
        searchText = "";
        selectedIndex = 0;
        keyboardNavigationActive = false;
        internalEntries = [];
        clipboardEntries = [];
        unpinnedEntries = [];
        pinnedEntries = [];
    }

    function copyEntry(entry, closeCallback, textOnly) {
        const asText = textOnly === true;
        DMSService.sendRequest("clipboard.copyEntry", {
            "id": entry.id,
            "textOnly": asText
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to copy entry"));
                return;
            }
            ToastService.showInfo(entry.isImage && !asText ? I18n.tr("Image copied to clipboard") : I18n.tr("Copied to clipboard"));
            historyCopied();
            if (closeCallback) {
                closeCallback();
            }
        });
    }

    function pasteClipboard(closeCallback) {
        if (closeCallback) {
            closeCallback();
        }
        if (pasteAvailable) {
            pasteTimer.start();
        }
    }

    function pasteEntry(entry, closeCallback) {
        if (!pasteAvailable) {
            copyEntry(entry, closeCallback);
            return;
        }
        DMSService.sendRequest("clipboard.copyEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to copy entry"));
                return;
            }
            if (closeCallback) {
                closeCallback();
            }
            pasteTimer.start();
        });
    }

    function pasteSelected(closeCallback) {
        if (!keyboardNavigationActive || clipboardEntries.length === 0 || selectedIndex < 0 || selectedIndex >= clipboardEntries.length) {
            return;
        }
        pasteEntry(clipboardEntries[selectedIndex], closeCallback);
    }

    function deleteEntry(entry) {
        DMSService.sendRequest("clipboard.deleteEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                log.warn("Failed to delete entry:", response.error);
                return;
            }
            internalEntries = internalEntries.filter(e => e.id !== entry.id);
            updateFilteredModel();
            if (clipboardEntries.length === 0) {
                keyboardNavigationActive = false;
                selectedIndex = 0;
                return;
            }
            if (selectedIndex >= clipboardEntries.length) {
                selectedIndex = clipboardEntries.length - 1;
            }
        });
    }

    function deletePinnedEntry(entry, confirmDialog) {
        if (!confirmDialog) {
            return;
        }
        confirmDialog.show(I18n.tr("Delete Saved Item?"), I18n.tr("This will permanently remove this saved clipboard item. This action cannot be undone."), function () {
            DMSService.sendRequest("clipboard.deleteEntry", {
                "id": entry.id
            }, function (response) {
                if (response.error) {
                    log.warn("Failed to delete entry:", response.error);
                    return;
                }
                internalEntries = internalEntries.filter(e => e.id !== entry.id);
                updateFilteredModel();
                ToastService.showInfo(I18n.tr("Saved item deleted"));
            });
        }, function () {});
    }

    function pinEntry(entry) {
        DMSService.sendRequest("clipboard.pinEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                // error text from core/internal/server/clipboard
                const limit = /^maximum pinned entries reached \((\d+)\)/.exec(response.error);
                ToastService.showError(limit ? I18n.tr("Maximum pinned entries reached") + " (" + limit[1] + ")" : I18n.tr("Failed to pin entry"));
                return;
            }
            ToastService.showInfo(I18n.tr("Entry pinned"));
        });
    }

    function unpinEntry(entry) {
        DMSService.sendRequest("clipboard.unpinEntry", {
            "id": entry.id
        }, function (response) {
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to unpin entry"));
                return;
            }
            ToastService.showInfo(I18n.tr("Entry unpinned"));
        });
    }

    function editEntry(entry, text, callback) {
        if (!entry || typeof entry.id !== "number") {
            if (callback) {
                callback({
                    "error": "Invalid entry"
                });
            }
            return;
        }
        DMSService.sendRequest("clipboard.editEntry", {
            "id": entry.id,
            "text": text
        }, function (response) {
            if (response.error) {
                log.warn("Failed to edit entry:", response.error);
                if (callback) {
                    callback(response);
                }
                return;
            }
            refresh();
            if (callback) {
                callback(response);
            }
        });
    }

    function clearAll() {
        const hasPinned = pinnedCount > 0;
        const savedCount = pinnedCount;
        DMSService.sendRequest("clipboard.clearHistory", null, function (response) {
            if (response.error) {
                log.warn("Failed to clear history:", response.error);
                return;
            }
            refresh();
            historyCleared();
            if (hasPinned) {
                ToastService.showInfo(I18n.tr("History cleared. %1 pinned entries kept.", "clipboard toast, %1 is a count of pinned entries").arg(savedCount));
            }
        });
    }

    function clearFiltered() {
        const ids = unpinnedEntries.map(entry => entry.id);
        if (ids.length === 0) {
            return;
        }
        DMSService.sendRequest("clipboard.deleteEntries", {
            "ids": ids
        }, function (response) {
            if (response.error) {
                log.warn("Failed to clear filtered entries:", response.error);
                return;
            }
            refresh();
            historyCleared();
        });
    }

    function getEntryPreview(entry) {
        return entry.preview || "";
    }

    function isTextMimeType(mimeType) {
        if (!mimeType || mimeType.startsWith("text/plain")) {
            return true;
        }
        return mimeType === "UTF8_STRING" || mimeType === "STRING" || mimeType === "TEXT";
    }

    function canEditEntry(entry) {
        return !!entry && !(entry.isImage ?? false) && isTextMimeType(entry.mimeType);
    }

    function isImageMimeType(mimeType) {
        return (mimeType || "").toString().toLowerCase().startsWith("image/");
    }

    function canPreviewEntry(entry) {
        return !!entry && !!(entry.isImage ?? false) && typeof entry.id === "number" && isImageMimeType(entry.mimeType);
    }

    function imageDataUrl(data, mimeType) {
        const rawData = (data || "").toString();
        if (rawData.length === 0)
            return "";
        if (rawData.startsWith("data:"))
            return rawData.startsWith("data:image/") ? rawData : "";
        if (!isImageMimeType(mimeType))
            return "";
        return "data:" + mimeType + ";base64," + rawData;
    }

    function getEntryType(entry) {
        if (entry.isImage) {
            return "image";
        }
        if (entry.size > longTextThreshold) {
            return "long_text";
        }
        return "text";
    }

    function getPinnedEntryByHash(entryHash) {
        if (!entryHash) {
            return null;
        }
        return internalEntries.find(entry => entry.pinned && entry.hash === entryHash) || null;
    }

    function hashedPinnedEntry(entryHash) {
        return getPinnedEntryByHash(entryHash) !== null;
    }

    onClipboardAvailableChanged: {
        if (!clipboardAvailable || refCount <= 0)
            return;
        refresh();
    }

    // only pinnedCount is tracked while no surface is open; the bar menu reads it, surfaces refresh on open
    Connections {
        target: DMSService
        function onClipboardStateUpdate(data) {
            const history = data.history || [];
            if (root.refCount > 0) {
                root.applyHistory(history);
                return;
            }
            root.pinnedCount = history.filter(e => e.pinned).length;
        }
    }
}
