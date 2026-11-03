pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services

Singleton {
    id: root
    readonly property var log: Log.scoped("NotepadStorageService")

    property int refCount: 0
    readonly property int largeFileBytes: 5 * 1024 * 1024
    property var approvedLargeFiles: ({})

    readonly property string baseDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.GenericStateLocation) + "/dms")
    readonly property string filesDir: baseDir + "/notepad-files"
    readonly property string metadataPath: baseDir + "/notepad-session.json"

    property var tabs: []
    property int currentTabIndex: 0
    property var tabsBeingCreated: ({})
    property bool metadataLoaded: false

    // Shared live edit state across slideout and popout surfaces.
    property var sessionBuffers: ({})
    property int sessionBufferRevision: 0

    function setSessionBuffer(tabId, content, baseline) {
        if (tabId === undefined || tabId === null || tabId < 0)
            return;
        var next = Object.assign({}, sessionBuffers);
        if (content !== baseline) {
            next[tabId] = {
                content: content,
                baseline: baseline
            };
        } else {
            delete next[tabId];
        }
        sessionBuffers = next;
        sessionBufferRevision++;
    }

    function getSessionBuffer(tabId) {
        return sessionBuffers[tabId];
    }

    function clearSessionBuffer(tabId) {
        if (sessionBuffers[tabId] === undefined)
            return;
        var next = Object.assign({}, sessionBuffers);
        delete next[tabId];
        sessionBuffers = next;
        sessionBufferRevision++;
    }

    property var conflictTabId: -1
    property string conflictDiskContent: ""

    function flagConflict(tabId, diskContent) {
        conflictDiskContent = diskContent;
        conflictTabId = tabId;
    }

    function clearConflict() {
        conflictTabId = -1;
        conflictDiskContent = "";
    }

    FileView {
        id: metadataFile
        path: root.refCount > 0 ? root.metadataPath : ""
        blockWrites: true
        atomicWrites: true

        onLoaded: {
            try {
                var data = JSON.parse(text());
                root.tabs = data.tabs || [];
                root.currentTabIndex = data.currentTabIndex || 0;
                root.metadataLoaded = true;
                root.validateTabs();
            } catch (e) {
                log.warn("Failed to parse notepad metadata:", e);
                root.createDefaultTab();
            }
        }

        onLoadFailed: {
            root.createDefaultTab();
        }
    }

    onRefCountChanged: {
        if (refCount !== 1)
            return;
        ensureDirectories();
        if (metadataLoaded)
            return;
        metadataFile.path = "";
        metadataFile.path = root.metadataPath;
    }

    property bool _directoriesEnsured: false

    function ensureDirectories() {
        if (_directoriesEnsured)
            return;
        _directoriesEnsured = true;
        Proc.runCommand("", ["mkdir", "-p", root.baseDir, root.filesDir], null);
    }

    function loadMetadata() {
        metadataFile.path = "";
        metadataFile.path = root.metadataPath;
    }

    function createDefaultTab() {
        var id = Date.now();
        var filePath = "notepad-files/untitled-" + id + ".txt";
        var fullPath = baseDir + "/" + filePath;

        var newTabsBeingCreated = Object.assign({}, tabsBeingCreated);
        newTabsBeingCreated[id] = true;
        tabsBeingCreated = newTabsBeingCreated;

        root.createEmptyFile(fullPath, function () {
            root.tabs = [
                {
                    id: id,
                    title: I18n.tr("Untitled", "default title of a new notepad tab or untitled window"),
                    filePath: filePath,
                    isTemporary: true,
                    lastModified: new Date().toISOString(),
                    cursorPosition: 0,
                    scrollPosition: 0
                }
            ];
            root.currentTabIndex = 0;

            var updatedTabsBeingCreated = Object.assign({}, tabsBeingCreated);
            delete updatedTabsBeingCreated[id];
            tabsBeingCreated = updatedTabsBeingCreated;
            root.saveMetadata();
        });
    }

    function saveMetadata() {
        var metadata = {
            version: 1,
            currentTabIndex: currentTabIndex,
            tabs: tabs
        };
        metadataFile.setText(JSON.stringify(metadata, null, 2));
    }

    function getTabById(tabId) {
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].id === tabId)
                return tabs[i];
        }
        return null;
    }

    function loadTabContent(tabIndex, callback, onLargeFile) {
        if (tabIndex < 0 || tabIndex >= tabs.length) {
            callback("");
            return;
        }

        var tab = tabs[tabIndex];
        var requestTabId = tab.id;
        var fullPath = tab.isTemporary ? baseDir + "/" + tab.filePath : tab.filePath;

        if (tabsBeingCreated[tab.id]) {
            Qt.callLater(() => {
                loadTabContent(tabIndex, callback, onLargeFile);
            });
            return;
        }

        readFileSize(fullPath, size => {
            var currentTab = root.getTabById(requestTabId);
            var currentPath = currentTab ? (currentTab.isTemporary ? baseDir + "/" + currentTab.filePath : currentTab.filePath) : "";

            if (!currentTab || currentPath !== fullPath) {
                callback("");
                return;
            }

            if (size < 0) {
                log.warn("Tab file does not exist:", fullPath);
                callback("");
                return;
            }

            if (!currentTab.isTemporary && root.needsLargeFileConfirm(fullPath, size)) {
                onLargeFile(size);
                return;
            }

            tabFileLoaderComponent.createObject(root, {
                path: fullPath,
                callback: callback
            });
        });
    }

    function readFileSize(path, callback) {
        Proc.runCommand("", ["sh", "-c", "test -f \"$1\" && wc -c < \"$1\"", "sh", path], (output, exitCode) => {
            callback(exitCode === 0 ? parseInt(output) : -1);
        });
    }

    function needsLargeFileConfirm(path, size) {
        return size > largeFileBytes && !approvedLargeFiles[path];
    }

    function approveLargeFile(path) {
        approvedLargeFiles[path] = true;
    }

    function saveTabContent(tabIndex, content) {
        if (tabIndex < 0 || tabIndex >= tabs.length)
            return;
        var tab = tabs[tabIndex];
        var fullPath = tab.isTemporary ? baseDir + "/" + tab.filePath : tab.filePath;

        var saver = tabFileSaverComponent.createObject(root, {
            path: fullPath,
            content: content,
            tabIndex: tabIndex
        });
    }

    function createNewTab() {
        var id = Date.now();
        var filePath = "notepad-files/untitled-" + id + ".txt";
        var fullPath = baseDir + "/" + filePath;

        var newTab = {
            id: id,
            title: I18n.tr("Untitled"),
            filePath: filePath,
            isTemporary: true,
            lastModified: new Date().toISOString(),
            cursorPosition: 0,
            scrollPosition: 0
        };

        var newTabsBeingCreated = Object.assign({}, tabsBeingCreated);
        newTabsBeingCreated[id] = true;
        tabsBeingCreated = newTabsBeingCreated;
        createEmptyFile(fullPath, function () {
            var newTabs = tabs.slice();
            newTabs.push(newTab);
            tabs = newTabs;
            currentTabIndex = tabs.length - 1;

            var updatedTabsBeingCreated = Object.assign({}, tabsBeingCreated);
            delete updatedTabsBeingCreated[id];
            tabsBeingCreated = updatedTabsBeingCreated;
            saveMetadata();
        });

        return newTab;
    }

    function createTabForFile(path) {
        var id = Date.now();
        var fileName = path.split('/').pop();

        var newTab = {
            id: id,
            title: fileName,
            filePath: path,
            isTemporary: false,
            lastModified: new Date().toISOString(),
            cursorPosition: 0,
            scrollPosition: 0
        };

        var newTabs = tabs.slice();
        newTabs.push(newTab);
        tabs = newTabs;
        currentTabIndex = tabs.length - 1;
        saveMetadata();

        return newTab;
    }

    function closeTab(tabIndex) {
        if (tabIndex < 0 || tabIndex >= tabs.length)
            return;
        var newTabs = tabs.slice();
        var closedTabId = newTabs[tabIndex] ? newTabs[tabIndex].id : -1;
        clearSessionBuffer(closedTabId);
        if (conflictTabId === closedTabId)
            clearConflict();

        if (newTabs.length <= 1) {
            var id = Date.now();
            var filePath = "notepad-files/untitled-" + id + ".txt";

            var newTabsBeingCreated = Object.assign({}, tabsBeingCreated);
            newTabsBeingCreated[id] = true;
            tabsBeingCreated = newTabsBeingCreated;
            createEmptyFile(baseDir + "/" + filePath, function () {
                newTabs[0] = {
                    id: id,
                    title: I18n.tr("Untitled"),
                    filePath: filePath,
                    isTemporary: true,
                    lastModified: new Date().toISOString(),
                    cursorPosition: 0,
                    scrollPosition: 0
                };
                currentTabIndex = 0;
                tabs = newTabs;

                var updatedTabsBeingCreated = Object.assign({}, tabsBeingCreated);
                delete updatedTabsBeingCreated[id];
                tabsBeingCreated = updatedTabsBeingCreated;
                saveMetadata();
            });
            return;
        } else {
            var tabToDelete = newTabs[tabIndex];
            if (tabToDelete && tabToDelete.isTemporary) {
                deleteFile(baseDir + "/" + tabToDelete.filePath);
            }

            newTabs.splice(tabIndex, 1);
            if (currentTabIndex >= newTabs.length) {
                currentTabIndex = newTabs.length - 1;
            } else if (currentTabIndex > tabIndex) {
                currentTabIndex -= 1;
            }
        }

        tabs = newTabs;
        saveMetadata();
    }

    function switchToTab(tabIndex) {
        if (tabIndex < 0 || tabIndex >= tabs.length)
            return;
        currentTabIndex = tabIndex;
        saveMetadata();
    }

    function reorderTab(fromIndex, toIndex) {
        if (fromIndex < 0 || fromIndex >= tabs.length || toIndex < 0 || toIndex >= tabs.length)
            return;
        if (fromIndex === toIndex)
            return;
        var newTabs = tabs.slice();
        var moved = newTabs.splice(fromIndex, 1)[0];
        newTabs.splice(toIndex, 0, moved);
        tabs = newTabs;

        if (currentTabIndex === fromIndex) {
            currentTabIndex = toIndex;
        } else if (fromIndex < currentTabIndex && toIndex >= currentTabIndex) {
            currentTabIndex--;
        } else if (fromIndex > currentTabIndex && toIndex <= currentTabIndex) {
            currentTabIndex++;
        }

        saveMetadata();
    }

    function saveTabAs(tabIndex, userPath) {
        if (tabIndex < 0 || tabIndex >= tabs.length)
            return;
        var tab = tabs[tabIndex];
        var fileName = userPath.split('/').pop();

        if (tab.isTemporary) {
            var tempPath = baseDir + "/" + tab.filePath;
            copyFile(tempPath, userPath);
            deleteFile(tempPath);
        }

        var newTabs = tabs.slice();
        newTabs[tabIndex] = Object.assign({}, tab, {
            title: fileName,
            filePath: userPath,
            isTemporary: false,
            lastModified: new Date().toISOString()
        });
        tabs = newTabs;
        saveMetadata();
    }

    function renameTab(tabIndex, newTitle) {
        if (tabIndex < 0 || tabIndex >= tabs.length)
            return;
        var trimmed = (newTitle || "").trim();
        var tab = tabs[tabIndex];
        if (trimmed.length === 0 || trimmed === tab.title)
            return;
        if (tab.isTemporary) {
            updateTabMetadata(tabIndex, {
                title: trimmed
            });
            return;
        }

        var dir = tab.filePath.substring(0, tab.filePath.lastIndexOf('/') + 1);
        var newPath = dir + trimmed;
        moveFile(tab.filePath, newPath);
        updateTabMetadata(tabIndex, {
            title: trimmed,
            filePath: newPath
        });
    }

    function updateTabMetadata(tabIndex, properties) {
        if (tabIndex < 0 || tabIndex >= tabs.length)
            return;
        var newTabs = tabs.slice();
        var updatedTab = Object.assign({}, newTabs[tabIndex], properties);
        updatedTab.lastModified = new Date().toISOString();
        newTabs[tabIndex] = updatedTab;
        tabs = newTabs;
        saveMetadata();
    }

    function validateTabs() {
        var validTabs = [];
        for (var i = 0; i < tabs.length; i++) {
            var tab = tabs[i];
            validTabs.push(tab);
        }
        tabs = validTabs;

        if (tabs.length === 0) {
            root.createDefaultTab();
        }
    }

    Component {
        id: tabFileLoaderComponent
        FileView {
            property var callback
            blockLoading: true
            preload: true

            onLoaded: {
                callback(text());
                destroy();
            }

            onLoadFailed: {
                callback("");
                destroy();
            }
        }
    }

    Component {
        id: tabFileSaverComponent
        FileView {
            property string content
            property int tabIndex
            property var creationCallback

            blockWrites: false
            atomicWrites: true

            Component.onCompleted: setText(content)

            onSaved: {
                if (tabIndex >= 0) {
                    root.updateTabMetadata(tabIndex, {});
                }
                if (creationCallback) {
                    creationCallback();
                }
                destroy();
            }

            onSaveFailed: {
                log.error("Failed to save tab content");
                if (creationCallback) {
                    creationCallback();
                }
                destroy();
            }
        }
    }

    function createEmptyFile(path, callback) {
        var cleanPath = decodeURI(path.toString());

        if (!cleanPath.startsWith("/")) {
            cleanPath = baseDir + "/" + cleanPath;
        }

        Proc.runCommand("", ["touch", cleanPath], (output, exitCode) => {
            if (callback)
                callback();
        });
    }

    function copyFile(source, destination) {
        Proc.runCommand("", ["cp", source, destination], null);
    }

    function deleteFile(path) {
        Proc.runCommand("", ["rm", "-f", path], null);
    }

    function moveFile(source, destination) {
        Proc.runCommand("", ["mv", source, destination], null);
    }
}
