pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Common

Singleton {
    id: root

    readonly property string _homeDir: Quickshell.env("HOME") || ""
    readonly property string _xdgDataHome: Quickshell.env("XDG_DATA_HOME") || (_homeDir + "/.local/share")
    readonly property string trashFilesDir: _xdgDataHome + "/Trash/files"

    readonly property bool monitoring: SettingsData.dockConfigs.some(config => config.showTrash && (config.enabled || config.openOnOverview))

    property int count: 0
    readonly property bool isEmpty: count === 0

    property var availableFileManagers: ["default"]
    property bool _fileManagersDetected: false
    property var _pendingOpenOptions: null
    property string defaultFileManagerLabel: "default (xdg-open)"

    signal emptyTrashConfirmRequested(int itemCount)

    onMonitoringChanged: {
        if (!monitoring) {
            count = 0;
            return;
        }
        refreshCount();
    }

    Loader {
        id: homeTrashWatch
        active: root.monitoring
        sourceComponent: FolderListModel {
            folder: "file://" + root.trashFilesDir
            showDirs: true
            showFiles: true
            showHidden: true
            showDotAndDotDot: false
            sortField: FolderListModel.Name
            nameFilters: ["*"]
            onCountChanged: root.refreshCount()
        }
    }

    Process {
        id: detectProc
        running: false
        command: ["sh", "-c", "for fm in nautilus thunar dolphin nemo caja pcmanfm pcmanfm-qt krusader; do command -v $fm >/dev/null 2>&1 && echo $fm; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const detected = (text || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
                root.availableFileManagers = ["default"].concat(detected).concat(["custom"]);
                if (!root._pendingOpenOptions)
                    return;
                const options = root._pendingOpenOptions;
                root._pendingOpenOptions = null;
                root.openTrash(options);
            }
        }
    }

    Component.onCompleted: {
        Paths.trashHandler = (path, callback) => trashPath(path, callback);
        refreshCount();
    }

    function detectFileManagers() {
        if (_fileManagersDetected)
            return;
        _fileManagersDetected = true;
        detectProc.running = true;
    }

    function refreshCount() {
        if (!monitoring)
            return;
        Proc.runCommand("trash-count", [Proc.dmsBin, "trash", "count"], (output, exitCode) => {
            const homeCount = homeTrashWatch.item?.count ?? 0;
            if (exitCode !== 0) {
                root.count = homeCount;
                return;
            }
            const n = parseInt((output || "").trim(), 10);
            root.count = isNaN(n) ? homeCount : n;
        });
    }

    function trashPath(path, callback) {
        if (!path) {
            if (callback)
                callback(false, "empty path");
            return;
        }
        Proc.runCommand(null, [Proc.dmsBin, "trash", "put", path], (output, exitCode) => {
            const ok = exitCode === 0;
            if (!ok)
                ToastService.showError(I18n.tr("Failed to move to trash"), path);
            refreshCount();
            if (callback)
                callback(ok, output);
        });
    }

    function openTrash(options) {
        const choice = options?.trashFileManager || "default";
        switch (choice) {
        case "default":
            Quickshell.execDetached(["xdg-open", "trash:///"]);
            return;
        case "custom":
            openCustom(options);
            return;
        }
        if (!_fileManagersDetected) {
            _pendingOpenOptions = options;
            detectFileManagers();
            return;
        }
        if (availableFileManagers.indexOf(choice) < 0) {
            ToastService.showInfo(I18n.tr("Cannot open trash: '%1' is not installed", "dock trash toast, %1 is the file manager name").arg(choice), I18n.tr("Pick a different file manager in Settings → Dock → Trash."));
            return;
        }
        Quickshell.execDetached([choice, "trash:///"]);
    }

    function openCustom(options) {
        const cmd = (options?.trashCustomCommand || "").trim();
        if (!cmd) {
            ToastService.showInfo(I18n.tr("Cannot open trash: no custom command set"), I18n.tr("Configure one in Settings → Dock → Trash."));
            return;
        }
        Proc.runCommand(null, ["sh", "-c", cmd], (output, exitCode) => {
            if (exitCode !== 0) {
                ToastService.showError(I18n.tr("Trash command failed (exit %1)", "dock trash error toast, %1 is the exit code").arg(exitCode), I18n.tr("Check your custom command in Settings → Dock → Trash."));
            }
        }, 0, Proc.noTimeout);
    }

    function requestEmptyTrash() {
        if (isEmpty)
            return;
        emptyTrashConfirmRequested(count);
    }

    function emptyTrash() {
        Proc.runCommand("trash-empty", [Proc.dmsBin, "trash", "empty"], (output, exitCode) => {
            if (exitCode !== 0)
                ToastService.showError(I18n.tr("Failed to empty trash"), output || "");
            refreshCount();
        });
    }
}
