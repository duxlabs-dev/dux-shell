pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Common as DCommon
import qs.Services
import qs.Modules.Settings.Widgets

Singleton {
    readonly property real rowHeight: Theme.buttonHeightXS + Theme.spacingXS
    readonly property real headerHeight: Theme.buttonHeightXS + Theme.spacingXS
    readonly property real appIconSize: Theme.iconSizeMedium
    readonly property real windowHeight: SettingsMetrics.windowHeight
    readonly property real menuRowHeight: DCommon.Style.menuRowHeight
    readonly property real menuPadding: DCommon.Style.menuPadding
    readonly property real menuWidth: 240
    readonly property real dialogWidth: 360
    readonly property int refreshInterval: DgopService.updateInterval

    // Shared by the window and the bar popout, like the user/system filter; not persisted.
    property bool onlineOnly: false
    property bool showAdvanced: false
    property string processTab: "overview"
    property bool cpuPerThread: false

    // Desktop entries by the program their Exec= runs, plus its first fixed argument ("dms run" is the shell).
    readonly property var execEntries: {
        const map = {};
        for (const entry of DesktopEntries.applications?.values ?? []) {
            const argv = entry?.command ?? [];
            if (!argv[0])
                continue;
            const item = {
                "entry": entry,
                "arg": argv.slice(1).find(a => !a.startsWith("%")) ?? ""
            };
            for (const key of [argv[0], argv[0].split("/").pop()])
                (map[key] = map[key] ?? []).push(item);
        }
        return map;
    }

    function execEntry(program, process) {
        const arg = (process?.fullCommand ?? "").split(" ")[1] ?? "";
        const items = execEntries[program] ?? [];
        return (items.find(i => i.arg === arg) ?? items.find(i => i.arg === ""))?.entry ?? null;
    }

    // Cached per process until the window list or installed apps change.
    readonly property var _appMemo: ({
            "entries": null,
            "toplevels": null,
            "windowIds": {},
            "cache": new Map()
        })

    // A window names its app more reliably than the process name does. Built on demand, so nothing runs while no process view is open.
    function windowAppId(pid) {
        const memo = _appMemo;
        const toplevels = CompositorService.sortedToplevels ?? [];
        if (memo.toplevels !== toplevels) {
            memo.toplevels = toplevels;
            memo.windowIds = {};
            for (const t of toplevels) {
                const windowPid = CompositorService.windowPid(t);
                if (windowPid > 0 && t?.appId && !memo.windowIds[windowPid])
                    memo.windowIds[windowPid] = t.appId;
            }
        }
        return memo.windowIds[pid];
    }

    Connections {
        target: DgopService
        function onPollingActiveChanged() {
            if (!DgopService.pollingActive)
                _appMemo.cache = new Map();
        }
    }

    function appEntry(process, extraKeys) {
        const windowId = windowAppId(process?.pid);
        const memo = _appMemo;
        if (memo.entries !== execEntries || memo.cache.size > 4000) {
            memo.entries = execEntries;
            memo.cache = new Map();
        }
        const key = [process?.pid, process?.executablePath, process?.fullCommand, windowId].concat(extraKeys ?? []).join("\n");
        if (memo.cache.has(key))
            return memo.cache.get(key);
        const entry = lookupAppEntry(process, windowId, extraKeys);
        memo.cache.set(key, entry);
        return entry;
    }

    function lookupAppEntry(process, windowId, extraKeys) {
        const exe = process?.executablePath ?? "";
        const keys = [windowId].concat(extraKeys ?? []);
        for (const key of keys) {
            const entry = key ? DesktopEntries.heuristicLookup(key) : null;
            if (entry)
                return entry;
        }
        return (exe && execEntry(exe, process)) || (process?.command ? DesktopEntries.heuristicLookup(process.command) : null) || execEntry(exe.split("/").pop(), process) || execEntry(process?.command ?? "", process);
    }

    function columnLabel(id) {
        switch (id) {
        case "cpu":
            return I18n.tr("CPU");
        case "memory":
            return I18n.tr("Memory");
        case "gpu":
            return I18n.tr("GPU");
        case "vram":
            return I18n.tr("VRAM", "GPU video memory");
        case "gpuVideo":
            return I18n.tr("Video", "process column: GPU video engine usage in percent");
        case "diskRead":
            return I18n.tr("Disk read", "disk read rate");
        case "diskWrite":
            return I18n.tr("Disk write", "disk write rate");
        case "connections":
            return I18n.tr("Connections", "process column: number of open internet connections");
        case "netRx":
            return I18n.tr("Download", "process column: network download rate");
        case "netTx":
            return I18n.tr("Upload", "process column: network upload rate");
        case "status":
            return I18n.tr("Status");
        case "threads":
            return I18n.tr("Threads", "number of threads, CPU or process");
        case "nice":
            return I18n.tr("Nice", "process column: Linux nice value, scheduling priority");
        case "cpuTime":
            return I18n.tr("CPU time", "process column: total CPU time used");
        case "pid":
            return I18n.tr("PID");
        case "user":
            return I18n.tr("User");
        }
        return "";
    }

    function groupLabel(group) {
        switch (group) {
        case "disk":
            return I18n.tr("Disk");
        case "network":
            return I18n.tr("Network");
        }
        return "";
    }

    function statusLabel(letter) {
        switch (letter) {
        case "R":
            return I18n.tr("Running", "process state");
        case "S":
            return I18n.tr("Sleeping", "process state");
        case "D":
            return I18n.tr("Waiting", "process state: uninterruptible wait, usually for disk");
        case "Z":
            return I18n.tr("Zombie", "process state: exited, not yet reaped by its parent");
        case "T":
        case "t":
            return I18n.tr("Stopped", "process state");
        case "I":
            return I18n.tr("Idle", "process state");
        }
        return letter;
    }
}
