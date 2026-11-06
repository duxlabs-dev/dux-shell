pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Common as DCommon
import qs.Services
import qs.Modules.Settings.Widgets
import "ProcessIcons.js" as ProcessIcons

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
            "cache": new Map(),
            "icons": new Map(),
            "iconIndex": null,
            "substitutions": null,
            "processes": null,
            "byPid": new Map(),
            "launchers": new Set()
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
            if (!DgopService.pollingActive) {
                _appMemo.cache = new Map();
                _appMemo.icons = new Map();
            }
        }
        function onAllProcessesChanged() {
            if (!DgopService.allProcesses?.length) {
                _appMemo.processes = null;
                _appMemo.byPid = new Map();
                _appMemo.launchers = new Set();
            }
        }
    }

    function appEntry(process, extraKeys) {
        const windowId = windowAppId(process?.pid);
        const memo = _appMemo;
        if (memo.entries !== execEntries || memo.cache.size > 4000) {
            memo.entries = execEntries;
            memo.cache = new Map();
            memo.icons = new Map();
        }
        const key = [process?.pid, process?.executablePath, process?.fullCommand, windowId].concat(extraKeys ?? []).join("\n");
        if (!memo.cache.has(key))
            memo.cache.set(key, lookupAppEntry(process, windowId, extraKeys));
        const entry = memo.cache.get(key) ?? shellAppEntry(process);
        if (entry)
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

    // Apps built on Quickshell run "qs -p <runtime dir>/<app>-shell/..." from their own binary, often without a window.
    function isShellApp(process) {
        return /^qs -p \S+-shell\//.test(process?.fullCommand ?? "");
    }

    function indexProcesses() {
        const memo = _appMemo;
        const processes = DgopService.allProcesses ?? [];
        if (memo.processes === processes)
            return;
        memo.processes = processes;
        memo.byPid = new Map(processes.map(p => [p.pid, p]));
        memo.launchers = new Set(processes.filter(isShellApp).map(p => p.ppid));
    }

    // The app's binary and its qs both belong to the desktop entry that runs the binary, whatever arguments that entry passes.
    // A miss isn't cached: it depends on which processes the current list holds.
    function shellAppEntry(process) {
        indexProcesses();
        const memo = _appMemo;
        const launcher = memo.launchers.has(process?.pid) ? process : isShellApp(process) ? memo.byPid.get(process.ppid) : null;
        return launcher ? execEntries[programName(launcher)]?.[0]?.entry ?? null : null;
    }

    function programName(process) {
        const path = process?.executablePath || (process?.fullCommand ?? "").split(" ")[0] || (process?.command ?? "");
        return path.replace(/ \(deleted\)$/, "").split("/").pop();
    }

    function programRow(program) {
        const name = program.toLowerCase();
        return ProcessIcons.PROGRAM_ICONS.find(r => r.programs.includes(name));
    }

    // Exact names only: the app id search behind Paths.getAppIcon matches parts of words, so "sh" finds any Exec line with "share" in it.
    // Theme lookups aren't exact for names with a dash: "start-hyprland" falls back to the unrelated "start" icon.
    function programIcon(program) {
        if (Paths.moddedAppId(program) !== program)
            return Paths.resolveIconPath(program);
        const name = program.toLowerCase();
        const row = programRow(program);
        const names = row ? row.icons ?? [] : name.includes("-") ? [] : [...new Set([program, name, name.replace(/[\d.]+$/, "")])];
        for (const candidate of names) {
            const icon = Paths.themedIconPath(candidate);
            if (icon)
                return icon;
        }
        return row?.logo ? Qt.resolvedUrl("../../assets/" + row.logo) : "";
    }

    function ownIcon(process, entry) {
        const memo = _appMemo;
        const iconIndex = IconThemeService._iconPaths;
        const substitutions = SettingsData.appIdSubstitutions;
        if (memo.iconIndex !== iconIndex || memo.substitutions !== substitutions) {
            memo.iconIndex = iconIndex;
            memo.substitutions = substitutions;
            memo.icons = new Map();
        }
        const program = programName(process);
        const command = process?.command ?? "";
        const key = [entry?.id, program, command].join("\n");
        if (!memo.icons.has(key))
            memo.icons.set(key, (entry ? Paths.getAppIcon(entry.id, entry) : "") || programIcon(command) || (program !== command ? programIcon(program) : ""));
        return memo.icons.get(key);
    }

    // A process without an icon of its own shows the one of its closest parent app that has one.
    function appIcon(process, entry) {
        indexProcesses();
        const memo = _appMemo;
        let icon = ownIcon(process, entry);
        let parent = memo.byPid.get(process?.ppid);
        for (let depth = 0; !icon && parent && depth < 32; depth++) {
            const parentEntry = appEntry(parent);
            if (parentEntry || programRow(programName(parent))?.passesIcon)
                icon = ownIcon(parent, parentEntry);
            parent = memo.byPid.get(parent.ppid);
        }
        return icon;
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
            return I18n.tr("Priority", "process column: scheduling priority level");
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
