pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.I3
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.DCommon.Common as DCommon
import qs.Services
import "../Common/WorkspaceModel.js" as WorkspaceModel
import "../Common/WindowModel.js" as WindowModel

Singleton {
    id: root
    readonly property var log: Log.scoped("CompositorService")

    property bool isHyprland: false
    property bool isNiri: false
    property bool isMango: false
    property bool isSway: false
    property bool isScroll: false
    property bool isMiracle: false
    property bool isLabwc: false
    property bool isAqueous: false
    property bool isUmbriel: false
    property bool isKwin: false
    property string compositor: "unknown"
    property bool compositorDetected: false
    property bool outputPowerAvailable: false
    readonly property bool genericPowerBackend: compositorDetected && !isNiri && !isHyprland && !isMango && !isSway && !isScroll && !isMiracle && !isLabwc && !isUmbriel
    onGenericPowerBackendChanged: probeOutputPower()

    readonly property bool inOverview: (isHyprland && HyprlandService.inOverview) || (isNiri && NiriService.inOverview) || (isMango && MangoService.inOverview)

    function probeOutputPower() {
        outputPowerAvailable = false;
        if (!genericPowerBackend)
            return;
        const backend = compositor;
        Proc.runCommand("output-power-probe", [Proc.dmsBin, "dpms", "list"], (output, code) => {
            if (root.compositor === backend && root.genericPowerBackend)
                root.outputPowerAvailable = code === 0;
        }, 0, 5000);
    }

    function setOutputPower(on) {
        Proc.runCommand("output-power-action", [Proc.dmsBin, "dpms", on ? "on" : "off"], (output, code) => {
            if (code !== 0)
                ToastService.showError(I18n.tr("Error"), I18n.tr("Failed to change display power", "Error shown when changing monitor power fails"));
        }, 0, 12000);
    }

    Connections {
        target: DMSService
        function onConnectionStateChanged() {
            if (DMSService.isConnected)
                root.probeOutputPower();
            else
                root.outputPowerAvailable = false;
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() {
            root.probeOutputPower();
            root.refreshHyprlandMonitorLayout();
        }
    }
    readonly property bool frameCompositorLayoutReady: (!isNiri || NiriService.frameLayoutReady) && (!isHyprland || HyprlandService.frameLayoutReady)
    readonly property bool useHyprlandFocusGrab: isHyprland && Quickshell.env("DMS_HYPRLAND_EXCLUSIVE_FOCUS") !== "1"

    readonly property string hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property string niriSocket: Quickshell.env("NIRI_SOCKET")
    readonly property string swaySocket: Quickshell.env("SWAYSOCK")
    readonly property string miracleSocket: Quickshell.env("MIRACLESOCK")
    readonly property string labwcPid: Quickshell.env("LABWC_PID")
    readonly property string mangoSignature: Quickshell.env("MANGO_INSTANCE_SIGNATURE")
    property bool useNiriSorting: isNiri && NiriService
    property bool useMangoSorting: isMango && MangoService

    property var randrScales: ({})
    property bool randrReady: false
    signal randrDataReady

    property var sortedToplevels: []
    property var hyprlandVisibleSpecialWorkspaces: ({})
    property bool _sortScheduled: false

    signal toplevelsChanged
    signal workspaceStateChanged
    property int windowStateRevision: 0
    onToplevelsChanged: windowStateRevision++
    onWorkspaceStateChanged: windowStateRevision++

    // Hyprland emits no event for a pure move/resize (verified via socket2,
    // see issue #3168), so smart auto-hide overlap goes stale until the next
    // workspace switch. Only floating windows can enter or leave the dock edge
    // that way: tiled layouts always reach the screen edge, and their changes
    // come with events. So poll only while a floating window is on a visible
    // workspace: compare the geometry from the previous refresh, bump the
    // revision only on change, then request the next refresh (async, so its
    // result is read on the following tick).
    property string _hyprlandGeometryKey: ""
    readonly property bool _dockSmartAutoHideActive: SettingsData.dockConfigs.some(config => config?.enabled && config?.smartAutoHide)
    readonly property bool _hyprlandFloatingOnVisibleWorkspace: {
        if (!isHyprland || !_dockSmartAutoHideActive)
            return false;
        windowStateRevision;
        const visible = new Set((Hyprland.monitors?.values ?? []).map(m => m.activeWorkspace?.id));
        return (Hyprland.toplevels?.values ?? []).some(t => {
            const ipc = t.lastIpcObject;
            if (!ipc?.floating)
                return false;
            const ws = ipc.workspace;
            return visible.has(t.workspace?.id ?? ws?.id) || (ws?.name ?? "").startsWith("special");
        });
    }

    Timer {
        interval: 1000
        repeat: true
        running: root._hyprlandFloatingOnVisibleWorkspace
        onTriggered: {
            const toplevels = Hyprland.toplevels?.values ?? [];
            const key = toplevels.map(t => {
                const ipc = t.lastIpcObject;
                return ipc ? `${ipc.address}:${ipc.at}:${ipc.size}:${ipc.workspace?.id}` : "";
            }).join("|");
            if (key !== root._hyprlandGeometryKey) {
                root._hyprlandGeometryKey = key;
                root.windowStateRevision++;
            }
            try {
                Hyprland.refreshToplevels();
            } catch (e) {}
        }
    }
    readonly property var _edgePositions: ({
            top: SettingsData.Position.Top,
            bottom: SettingsData.Position.Bottom,
            left: SettingsData.Position.Left,
            right: SettingsData.Position.Right
        })

    readonly property bool supportsMinimize: isAqueous && AqueousService.available ? AqueousService.capabilities.commands && !AqueousService.locked : DCommon.Compositor.supportsMinimize

    readonly property bool hasWorkspaceIpc: {
        switch (compositor) {
        case "niri":
        case "hyprland":
        case "mango":
        case "sway":
        case "scroll":
        case "miracle":
        case "umbriel":
            return true;
        default:
            return false;
        }
    }
    readonly property bool ephemeralWorkspaces: isHyprland
    readonly property bool windowOverlapSupported: {
        switch (compositor) {
        case "niri":
        case "hyprland":
        case "mango":
            return true;
        case "aqueous":
            return AqueousService.available;
        default:
            return false;
        }
    }
    readonly property bool workspaceReorderSupported: isNiri

    readonly property bool isKnownCompositor: configKey !== ""
    readonly property bool supportsWindowRules: isNiri || isHyprland || isMango
    readonly property string dmsFloatingRuleId: "dms-floating-windows"
    property bool dmsWindowFloatingActive: false
    readonly property string dmsOpaqueRuleId: "dms-window-opaque"
    readonly property bool supportsLayoutConfig: isNiri || isHyprland || isMango
    readonly property bool supportsCursorConfig: isNiri || isHyprland || isMango
    readonly property bool supportsDisplayConfig: isNiri || isHyprland || isMango || isAqueous
    readonly property bool supportsBarAutoHideReveal: isNiri || isHyprland || isMango
    readonly property bool supportsWorkspaces: isNiri || isHyprland || isMango || isAqueous || isUmbriel
    // compositors where a workspace that does not exist yet is still a valid switch target
    readonly property bool supportsPersistentWorkspaces: isHyprland || isMango || isSway || isScroll || isMiracle
    readonly property bool supportsWorkspaceUrgency: isKnownCompositor && !isLabwc
    readonly property bool supportsWorkspaceFollowFocus: isKnownCompositor && !isLabwc
    // labwc root menu and desktop scroll, sway/scroll --whole-window binds, plasmashell desktop menu
    readonly property bool reservesDesktopInput: isLabwc || isSway || isScroll || isKwin
    readonly property bool desktopContextMenuEnabled: {
        switch (SettingsData.desktopContextMenu) {
        case "on":
            return true;
        case "off":
            return false;
        default:
            return !reservesDesktopInput;
        }
    }
    readonly property bool supportsSmartDock: isNiri || isHyprland || isMango || isAqueous
    readonly property bool supportsNativeOverview: isNiri || isAqueous
    readonly property bool supportsPointerConfig: isNiri || isHyprland || isMango
    readonly property bool supportsInputConfig: isNiri || isHyprland || isMango

    readonly property string displayName: {
        switch (compositor) {
        case "niri":
            return "niri";
        case "hyprland":
            return "Hyprland";
        case "mango":
            return "MangoWC";
        case "sway":
            return "Sway";
        case "scroll":
            return "Scroll";
        case "miracle":
            return "Miracle WM";
        case "labwc":
            return "Labwc";
        case "aqueous":
            return "Aqueous";
        case "umbriel":
            return "Umbriel";
        case "kwin":
            return "KWin";
        default:
            return "";
        }
    }

    readonly property string configKey: {
        switch (compositor) {
        case "niri":
        case "hyprland":
        case "mango":
        case "sway":
        case "scroll":
        case "miracle":
        case "labwc":
        case "aqueous":
        case "umbriel":
            return compositor;
        default:
            return "";
        }
    }

    property var _workspaceRecords: ({})

    Connections {
        target: AqueousService
        enabled: root.isAqueous
        function onStateChanged() {
            root.scheduleSort();
            if (AqueousService.available)
                root.workspaceStateChanged();
        }
    }

    Connections {
        target: NiriService
        enabled: root.isNiri
        function onAllWorkspacesChanged() {
            root.workspaceStateChanged();
        }
        function onWindowUrgentChanged() {
            root.workspaceStateChanged();
        }
        function onWindowsChanged() {
            if (NiriService.titleOnlyWindowsUpdate)
                return;
            root.workspaceStateChanged();
        }
        function onCurrentOutputChanged() {
            root.workspaceStateChanged();
        }
    }

    Connections {
        target: root.isHyprland ? Hyprland.workspaces : null
        function onValuesChanged() {
            root.workspaceStateChanged();
        }
    }

    Connections {
        target: root.isSway || root.isScroll || root.isMiracle ? I3.workspaces : null
        function onValuesChanged() {
            root.workspaceStateChanged();
        }
    }

    Binding {
        target: UmbrielService
        property: "active"
        value: root.isUmbriel
    }

    Connections {
        target: UmbrielService
        enabled: root.isUmbriel
        function onWorkspacesChanged() {
            root.workspaceStateChanged();
        }
        function onWindowsChanged() {
            root.workspaceStateChanged();
        }
    }

    function canMinimize(toplevel) {
        if (isAqueous && toplevel?.aqueousWindowId)
            return AqueousService.available && !AqueousService.locked && AqueousService.capabilities.commands && toplevel.canMinimize;
        return supportsMinimize && toplevel && toplevel.minimized !== undefined;
    }

    function closeNiriOverviewOnWindowFocus() {
        if (SettingsData.closeNiriOverviewOnWindowFocus && isNiri && NiriService.inOverview)
            NiriService.closeOverview();
    }

    function activateToplevel(toplevel) {
        if (!toplevel)
            return;
        if (isAqueous && toplevel.aqueousWindowId) {
            toplevel.activate();
            return;
        }
        closeNiriOverviewOnWindowFocus();
        if (canMinimize(toplevel) && toplevel.minimized)
            toplevel.minimized = false;
        toplevel.activate();
    }

    function toggleToplevel(toplevel) {
        if (!toplevel)
            return;
        if (!canMinimize(toplevel)) {
            activateToplevel(toplevel);
            return;
        }
        if (toplevel.minimized) {
            activateToplevel(toplevel);
            return;
        }
        if (toplevel.activated) {
            toplevel.minimized = true;
            return;
        }
        activateToplevel(toplevel);
    }

    function fetchRandrData() {
        Proc.runCommand("randr", [Proc.dmsBin, "randr", "--json"], (output, exitCode) => {
            if (exitCode === 0 && output) {
                try {
                    const data = JSON.parse(output.trim());
                    if (data.outputs && Array.isArray(data.outputs)) {
                        const scales = {};
                        for (const out of data.outputs) {
                            if (out.name && out.scale > 0)
                                scales[out.name] = out.scale;
                        }
                        randrScales = scales;
                    }
                } catch (e) {
                    log.warn("failed to parse randr data:", e);
                }
            }
            randrReady = true;
            randrDataReady();
        }, 0, 3000);
    }

    // wlr-output reports wl_fixed (1/256 steps), surfaces render at fractional-scale-v1 N/120
    function fractionalScale(fixedScale) {
        return Math.round(fixedScale * 120) / 120;
    }

    function getScreenScale(screen) {
        if (!screen)
            return 1;

        if (Quickshell.env("QT_WAYLAND_FORCE_DPI") || Quickshell.env("QT_SCALE_FACTOR")) {
            return screen.devicePixelRatio || 1;
        }

        const randrScale = randrScales[screen.name];
        if (randrScale !== undefined && randrScale > 0)
            return fractionalScale(randrScale);

        if (WlrOutputService.wlrOutputAvailable && screen) {
            const wlrOutput = WlrOutputService.getOutput(screen.name);
            if (wlrOutput?.enabled && wlrOutput.scale !== undefined && wlrOutput.scale > 0) {
                return fractionalScale(wlrOutput.scale);
            }
        }

        if (isNiri && screen) {
            const niriScale = NiriService.displayScales[screen.name];
            if (niriScale !== undefined)
                return niriScale;
        }

        if (isHyprland && screen) {
            const hyprlandMonitor = Hyprland.monitors.values.find(m => m.name === screen.name);
            if (hyprlandMonitor?.scale !== undefined)
                return hyprlandMonitor.scale;
        }

        if (isMango && screen) {
            const mangoScale = MangoService.getOutputScale(screen.name);
            if (mangoScale !== undefined && mangoScale > 0)
                return mangoScale;
        }

        return screen?.devicePixelRatio || 1;
    }

    property var _windowKeys: []
    property int _windowSerial: 0

    function windowKey(toplevel) {
        if (!toplevel)
            return "";
        if (toplevel.aqueousKey)
            return toplevel.aqueousKey;
        if (toplevel.niriWindowId !== undefined)
            return "niri:" + toplevel.niriWindowId;
        if (toplevel.mangoWindowId !== undefined)
            return "mango:" + toplevel.mangoWindowId;
        const known = _windowKeys.find(entry => entry.toplevel === toplevel);
        if (known)
            return known.key;
        const live = ToplevelManager.toplevels?.values;
        if (live) {
            for (let i = _windowKeys.length - 1; i >= 0; i--) {
                if (!live.includes(_windowKeys[i].toplevel))
                    _windowKeys.splice(i, 1);
            }
        }
        const key = "window:" + (++_windowSerial);
        _windowKeys.push({
            toplevel,
            key
        });
        return key;
    }

    function getFocusedScreenName() {
        if (isAqueous && AqueousService.available)
            return AqueousService.focusedOutput;
        if (isHyprland && Hyprland.focusedMonitor)
            return Hyprland.focusedMonitor.name;
        if (isNiri && NiriService.currentOutput)
            return NiriService.currentOutput;
        if (isSway || isScroll || isMiracle) {
            const focusedWs = I3.workspaces?.values?.find(ws => ws.focused === true);
            return focusedWs?.monitor?.name || "";
        }
        if (isMango && MangoService.activeOutput)
            return MangoService.activeOutput;
        if (isUmbriel)
            return UmbrielService.focusedOutput;

        return "";
    }

    function getFocusedScreen() {
        const screenName = getFocusedScreenName();
        if (!screenName)
            return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;

        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === screenName)
                return Quickshell.screens[i];
        }
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    Timer {
        id: sortDebounceTimer
        interval: 100
        repeat: false
        onTriggered: {
            _sortScheduled = false;
            const next = computeSortedToplevels();
            // Avoid reassigning (and invalidating bindings) when contents are equivalent.
            if (!_toplevelListEquivalent(next, sortedToplevels))
                sortedToplevels = next;
            toplevelsChanged();
        }
    }

    function _toplevelListEquivalent(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++) {
            const x = a[i];
            const y = b[i];
            if (x === y)
                continue;
            if (!x || !y)
                return false;
            // Only niri/mango enriched snapshots support value comparison
            const xKey = x.niriWindowId !== undefined ? x.niriWindowId : x.mangoWindowId;
            const yKey = y.niriWindowId !== undefined ? y.niriWindowId : y.mangoWindowId;
            if (xKey === undefined || yKey === undefined)
                return false;
            if (xKey !== yKey || x.niriWorkspaceId !== y.niriWorkspaceId || x.mangoMonitor !== y.mangoMonitor || x.appId !== y.appId || x.title !== y.title || !!x.activated !== !!y.activated || !!x.fullscreen !== !!y.fullscreen || !!x.maximized !== !!y.maximized || !!x.minimized !== !!y.minimized)
                return false;
        }
        return true;
    }

    function scheduleSort() {
        if (_sortScheduled)
            return;
        _sortScheduled = true;
        sortDebounceTimer.restart();
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            root.scheduleSort();
        }
    }
    Connections {
        target: isHyprland ? Hyprland : null
        enabled: isHyprland

        function onRawEvent(event) {
            if (event.name === "monitoraddedv2" || event.name === "monitorremoved" || event.name === "configreloaded") {
                if (event.name === "configreloaded")
                    HyprlandService.refreshFollowMouse();
                root.refreshHyprlandMonitorLayout();
                return;
            }
            if (event.name === "openwindow" || event.name === "closewindow" || event.name === "movewindow" || event.name === "movewindowv2" || event.name === "workspace" || event.name === "workspacev2" || event.name === "focusedmon" || event.name === "focusedmonv2" || event.name === "activewindow" || event.name === "activewindowv2" || event.name === "changefloatingmode" || event.name === "fullscreen" || event.name === "moveintogroup" || event.name === "moveoutofgroup" || event.name === "activespecial") {
                try {
                    Hyprland.refreshToplevels();
                    if (event.name === "workspace" || event.name === "workspacev2" || event.name === "focusedmon" || event.name === "focusedmonv2" || event.name === "activespecial")
                        Hyprland.refreshMonitors();
                } catch (e) {}
                if (event.name === "activespecial")
                    root.updateHyprlandVisibleSpecialWorkspaces(event);
                root.scheduleSort();
                if (event.name === "activewindow" || event.name === "activewindowv2")
                    root.workspaceStateChanged();
            }
        }
    }
    Connections {
        target: NiriService
        enabled: root.isNiri
        function onWindowsChanged() {
            root.scheduleSort();
        }
    }

    Component.onCompleted: {
        fetchRandrData();
        detectCompositor();
        updateHyprlandVisibleSpecialWorkspaces(null);
        scheduleSort();
    }

    Connections {
        target: MangoService
        enabled: root.isMango
        function onStateChanged() {
            root.scheduleSort();
            root.workspaceStateChanged();
        }
        function onWindowsChanged() {
            root.scheduleSort();
        }
    }

    function computeSortedToplevels() {
        if (isAqueous && AqueousService.available)
            return AqueousService.toplevels;
        if (!ToplevelManager.toplevels || !ToplevelManager.toplevels.values)
            return [];

        if (useNiriSorting)
            return NiriService.sortToplevels(ToplevelManager.toplevels.values);

        if (useMangoSorting)
            return MangoService.sortToplevels(ToplevelManager.toplevels.values);

        if (isHyprland)
            return sortHyprlandToplevelsSafe();

        return Array.from(ToplevelManager.toplevels.values);
    }

    function _get(o, path, fallback) {
        try {
            let v = o;
            for (let i = 0; i < path.length; i++) {
                if (v === null || v === undefined)
                    return fallback;
                v = v[path[i]];
            }
            return (v === undefined || v === null) ? fallback : v;
        } catch (e) {
            return fallback;
        }
    }

    function _normalizeSpecialWorkspaceName(name) {
        const raw = String(name ?? "").trim();
        if (raw.length === 0)
            return "";
        if (raw === "special")
            return "special:special";
        return raw.startsWith("special:") ? raw : `special:${raw}`;
    }

    function _hyprlandRawEventParts(event, argumentCount) {
        if (!event)
            return [];
        try {
            const parsed = event.parse(argumentCount);
            if (parsed && parsed.length !== undefined)
                return parsed;
        } catch (e) {}
        const data = String(event.data ?? "");
        return data.length > 0 ? data.split(",") : [];
    }

    function _specialWorkspaceNameFromMonitor(monitor) {
        if (!monitor)
            return "";
        const candidates = [monitor.activeSpecialWorkspace?.name, monitor.specialWorkspace?.name, monitor.lastIpcObject?.specialWorkspace?.name, monitor.lastIpcObject?.specialWorkspace, monitor.lastIpcObject?.activeSpecialWorkspace?.name];
        for (let i = 0; i < candidates.length; i++) {
            const normalized = _normalizeSpecialWorkspaceName(candidates[i]);
            if (normalized)
                return normalized;
        }
        return "";
    }

    function updateHyprlandVisibleSpecialWorkspaces(event) {
        if (!isHyprland) {
            hyprlandVisibleSpecialWorkspaces = ({});
            return;
        }

        const next = {};
        try {
            const monitors = Hyprland.monitors?.values || [];
            for (const monitor of monitors) {
                const monitorName = monitor?.name ?? monitor?.lastIpcObject?.name ?? "";
                if (!monitorName)
                    continue;
                const specialName = _specialWorkspaceNameFromMonitor(monitor);
                if (specialName)
                    next[monitorName] = specialName;
            }
        } catch (e) {
            log.warn("updateHyprlandVisibleSpecialWorkspaces monitor snapshot failed:", e);
        }

        if (event?.name === "activespecial") {
            const parts = _hyprlandRawEventParts(event, 2);
            const specialName = _normalizeSpecialWorkspaceName(parts[0]);
            const monitorName = String(parts[1] ?? Hyprland.focusedMonitor?.name ?? Hyprland.focusedWorkspace?.monitor?.name ?? "");
            if (monitorName) {
                if (specialName)
                    next[monitorName] = specialName;
                else
                    delete next[monitorName];
            }
        }

        hyprlandVisibleSpecialWorkspaces = next;
    }

    function sortHyprlandToplevelsSafe() {
        if (!Hyprland.toplevels || !Hyprland.toplevels.values)
            return [];

        const items = Array.from(Hyprland.toplevels.values);

        function _get(o, path, fb) {
            try {
                let v = o;
                for (let k of path) {
                    if (v == null)
                        return fb;
                    v = v[k];
                }
                return (v == null) ? fb : v;
            } catch (e) {
                return fb;
            }
        }

        let snap = [];
        for (let i = 0; i < items.length; i++) {
            const t = items[i];
            if (!t)
                continue;
            const addr = t.address || "";
            if (!addr)
                continue;
            const li = t.lastIpcObject || null;

            const monName = _get(li, ["monitor"], null) ?? _get(t, ["monitor", "name"], "");
            const monX = _get(t, ["monitor", "x"], Number.MAX_SAFE_INTEGER);
            const monY = _get(t, ["monitor", "y"], Number.MAX_SAFE_INTEGER);

            const wsId = _get(li, ["workspace", "id"], null) ?? _get(t, ["workspace", "id"], Number.MAX_SAFE_INTEGER);

            const at = _get(li, ["at"], null);
            let atX = (at !== null && at !== undefined && typeof at[0] === "number") ? at[0] : 1e9;
            let atY = (at !== null && at !== undefined && typeof at[1] === "number") ? at[1] : 1e9;

            const relX = Number.isFinite(monX) ? (atX - monX) : atX;
            const relY = Number.isFinite(monY) ? (atY - monY) : atY;

            snap.push({
                monKey: String(monName),
                monOrderX: Number.isFinite(monX) ? monX : Number.MAX_SAFE_INTEGER,
                monOrderY: Number.isFinite(monY) ? monY : Number.MAX_SAFE_INTEGER,
                wsId: (typeof wsId === "number") ? wsId : Number.MAX_SAFE_INTEGER,
                x: relX,
                y: relY,
                title: t.title || "",
                address: addr,
                wayland: t.wayland
            });
        }

        const groups = new Map();
        for (const it of snap) {
            const key = it.monKey + "::" + it.wsId;
            if (!groups.has(key))
                groups.set(key, []);
            groups.get(key).push(it);
        }

        let groupList = [];
        for (const [key, arr] of groups) {
            const repr = arr[0];
            groupList.push({
                key,
                monKey: repr.monKey,
                monOrderX: repr.monOrderX,
                monOrderY: repr.monOrderY,
                wsId: repr.wsId,
                items: arr
            });
        }

        groupList.sort((a, b) => {
            if (a.monOrderX !== b.monOrderX)
                return a.monOrderX - b.monOrderX;
            if (a.monOrderY !== b.monOrderY)
                return a.monOrderY - b.monOrderY;
            if (a.monKey !== b.monKey)
                return a.monKey.localeCompare(b.monKey);
            if (a.wsId !== b.wsId)
                return a.wsId - b.wsId;
            return 0;
        });

        const COLUMN_THRESHOLD = 48;
        const JITTER_Y = 6;

        let ordered = [];
        for (const g of groupList) {
            const arr = g.items;

            const xs = arr.map(it => it.x).filter(x => Number.isFinite(x)).sort((a, b) => a - b);
            let colCenters = [];
            if (xs.length > 0) {
                for (const x of xs) {
                    if (colCenters.length === 0) {
                        colCenters.push(x);
                    } else {
                        const last = colCenters[colCenters.length - 1];
                        if (x - last >= COLUMN_THRESHOLD) {
                            colCenters.push(x);
                        }
                    }
                }
            } else {
                colCenters = [0];
            }

            for (const it of arr) {
                let bestCol = 0;
                let bestDist = Number.POSITIVE_INFINITY;
                for (let ci = 0; ci < colCenters.length; ci++) {
                    const d = Math.abs(it.x - colCenters[ci]);
                    if (d < bestDist) {
                        bestDist = d;
                        bestCol = ci;
                    }
                }
                it._col = bestCol;
            }

            arr.sort((a, b) => {
                if (a._col !== b._col)
                    return a._col - b._col;

                const dy = a.y - b.y;
                if (Math.abs(dy) > JITTER_Y)
                    return dy;

                if (a.title !== b.title)
                    return a.title.localeCompare(b.title);
                if (a.address !== b.address)
                    return a.address.localeCompare(b.address);
                return 0;
            });

            ordered.push.apply(ordered, arr);
        }
        return ordered.map(x => {
            if (!x.wayland)
                return null;
            x.wayland.address = x.address;
            return x.wayland;
        }).filter(w => w !== null && w !== undefined);
    }

    function filterCurrentWorkspace(toplevels, screen) {
        if (isAqueous && AqueousService.available) {
            const active = AqueousService.workspacesForOutput(_screenName(screen)).filter(w => w.active).map(w => w.id);
            return toplevels.filter(t => active.includes(t.aqueousWorkspaceId));
        }
        if (useNiriSorting)
            return NiriService.filterCurrentWorkspace(toplevels, screen);
        if (useMangoSorting)
            return MangoService.filterCurrentWorkspace(toplevels, screen);
        if (isHyprland)
            return filterHyprlandCurrentWorkspaceSafe(toplevels, screen);
        return toplevels;
    }

    readonly property string toplevelKey: {
        switch (compositor) {
        case "aqueous":
            return AqueousService.available ? "aqueousKey" : "address";
        case "niri":
            return "niriWindowId";
        case "mango":
            return "mangoWindowId";
        default:
            return "address";
        }
    }

    function toplevelPlacement(toplevel) {
        if (!toplevel)
            return {
                "workspace": "",
                "output": ""
            };
        if (isAqueous && AqueousService.available) {
            const workspace = AqueousService.workspaces.find(w => w.id === toplevel.aqueousWorkspaceId);
            return {
                "workspace": String(workspace?.name || workspace?.number || ""),
                "output": AqueousService.outputs.find(o => o.id === toplevel.aqueousOutputId)?.name ?? ""
            };
        }
        if (useNiriSorting) {
            const workspace = NiriService.allWorkspaces.find(w => w.id === toplevel.niriWorkspaceId);
            return {
                "workspace": String(workspace?.name || workspace?.idx || ""),
                "output": workspace?.output ?? ""
            };
        }
        if (useMangoSorting)
            return {
                "workspace": (toplevel.mangoTags || []).join(", "),
                "output": toplevel.mangoMonitor ?? ""
            };
        if (isHyprland) {
            const workspace = WindowModel.hyprlandToplevelFor(Array.from(Hyprland.toplevels?.values || []), toplevel)?.workspace;
            return {
                "workspace": workspace?.name ?? "",
                "output": workspace?.monitor?.name ?? ""
            };
        }
        return {
            "workspace": "",
            "output": toplevel.screens?.[0]?.name ?? ""
        };
    }

    function fullscreenToplevelOnScreen(screenOrName) {
        const screenName = _screenName(screenOrName);
        if (isAqueous && AqueousService.available)
            return AqueousService.windows.some(w => w.output === AqueousService.outputId(screenName) && w.visible && w.fullscreen);
        if (!screenName || !ToplevelManager.toplevels?.values)
            return false;

        const toplevels = ToplevelManager.toplevels.values;
        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i];
            if (toplevel?.fullscreen && toplevel.activated && _toplevelOnScreen(toplevel, screenName))
                return true;
        }
        return false;
    }

    function filterCurrentDisplay(toplevels, screenName) {
        if (!toplevels || toplevels.length === 0 || !screenName)
            return toplevels;
        if (useNiriSorting) {
            const active = ToplevelManager.activeToplevel;
            if (active && toplevels.length === 1 && toplevels[0] === active) {
                if (NiriService.currentOutput !== screenName)
                    return [];
                const focusedWin = NiriService.windows.find(nw => nw.is_focused);
                if (!focusedWin)
                    return [];
                const screenWsIds = new Set(NiriService.allWorkspaces.filter(ws => ws.output === screenName).map(ws => ws.id));
                return screenWsIds.has(focusedWin.workspace_id) ? toplevels : [];
            }
            return NiriService.filterCurrentDisplay(toplevels, screenName);
        }
        if (useMangoSorting)
            return MangoService.filterCurrentDisplay(toplevels, screenName);
        if (isHyprland)
            return filterHyprlandCurrentDisplaySafe(toplevels, screenName);
        return toplevels.filter(t => _toplevelOnScreen(t, screenName));
    }

    function _screenName(screenOrName) {
        if (typeof screenOrName === "string")
            return screenOrName;
        return screenOrName?.name ?? "";
    }

    function _toplevelOnScreen(toplevel, screenName) {
        if (!toplevel || !screenName)
            return false;
        const screens = toplevel.screens;
        if (!screens)
            return false;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i]?.name === screenName)
                return true;
        }
        return false;
    }

    function _hyprlandToplevelMapped(hyprToplevel) {
        if (!hyprToplevel)
            return false;
        if (hyprToplevel.mapped === false)
            return false;
        const ipcMapped = hyprToplevel.lastIpcObject?.mapped;
        if (ipcMapped === false)
            return false;
        if (hyprToplevel.hidden === true)
            return false;
        const ipcHidden = hyprToplevel.lastIpcObject?.hidden;
        if (ipcHidden === true)
            return false;
        return true;
    }

    readonly property var specialWorkspaceNames: {
        if (!isHyprland)
            return [];
        const names = ["special"];
        for (const ws of Hyprland.workspaces?.values || []) {
            if (!WorkspaceModel.hyprlandSpecial(ws))
                continue;
            const name = WorkspaceModel.hyprlandSpecialDisplayName(ws.name ?? "");
            if (!names.includes(name))
                names.push(name);
        }
        return names;
    }

    function hyprlandAddressFor(window) {
        return isHyprland ? (_hyprlandToplevelFor(window)?.address ?? "") : "";
    }

    // IPC callers pass Hyprland's own names, prefixed or not
    function _scratchpadName(name) {
        const bare = WorkspaceModel.hyprlandSpecialDisplayName(String(name ?? ""));
        return !bare || bare === "special" ? "special" : bare;
    }

    function toggleSpecialWorkspace(name) {
        if (!isHyprland)
            return;
        const bare = _scratchpadName(name);
        HyprlandService.toggleSpecial(bare === "special" ? "" : bare);
    }

    function _hyprlandToplevelFor(window) {
        if (!window)
            return null;
        const byAddress = typeof window === "string";
        for (const t of Hyprland.toplevels?.values || []) {
            if (byAddress ? t.address === window : t.wayland === window)
                return t;
        }
        return null;
    }

    function windowScratchpadName(window) {
        if (!isHyprland)
            return "";
        const t = _hyprlandToplevelFor(window);
        const ws = String(t?.lastIpcObject?.workspace?.name || t?.workspace?.name || "");
        return WorkspaceModel.hyprlandSpecialName(ws) ? WorkspaceModel.hyprlandSpecialDisplayName(ws) : "";
    }

    // "+0" is Hyprland's own way out but resolves against the focused monitor, so prefer the window's monitor when known
    function moveWindowOutOfSpecial(window) {
        const t = _hyprlandToplevelFor(window);
        if (!t?.address)
            return;
        const target = t.monitor?.activeWorkspace;
        HyprlandService.moveToWorkspace(target?.name ? WorkspaceModel.hyprlandSelector(target) : "+0", t.address, true);
    }

    function moveWindowToSpecial(window, name) {
        const address = hyprlandAddressFor(window);
        if (!address)
            return;
        const bare = _scratchpadName(name);
        HyprlandService.moveToWorkspace(bare === "special" ? "special" : "special:" + bare, address, false);
    }

    function hyprlandVisibleSpecialWorkspaceOnScreen(screenOrName) {
        const screenName = _screenName(screenOrName);
        if (!isHyprland || !screenName)
            return "";
        hyprlandVisibleSpecialWorkspaces;
        const trackedName = hyprlandVisibleSpecialWorkspaces[screenName] ?? "";
        if (trackedName)
            return trackedName;
        try {
            const monitor = Hyprland.monitors?.values?.find(m => m.name === screenName);
            return _specialWorkspaceNameFromMonitor(monitor);
        } catch (e) {
            return "";
        }
    }

    // Workspace moves can land before Hyprland announces the monitor and before the Wayland
    // output reaches us, so re-read both models once the screen set settles (#3133)
    function refreshHyprlandMonitorLayout() {
        if (!isHyprland)
            return;
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        HyprlandService.refreshWorkspaceRules();
    }

    function _screenForName(screenOrName) {
        if (screenOrName && typeof screenOrName !== "string")
            return screenOrName;
        const screenName = _screenName(screenOrName);
        if (!screenName)
            return null;
        const screens = Quickshell.screens || [];
        for (let i = 0; i < screens.length; i++) {
            if (screens[i]?.name === screenName)
                return screens[i];
        }
        return null;
    }

    function frameConfiguredForScreen(screenOrName) {
        if (!FrameTransitionState.effectiveFrameEnabled)
            return false;
        const screen = _screenForName(screenOrName);
        if (!screen || !SettingsData.isScreenInPreferences(screen, SettingsData.frameScreenPreferences))
            return false;
        return true;
    }

    function frameWindowVisibleForScreen(screenOrName) {
        return frameConfiguredForScreen(screenOrName);
    }

    function overviewActiveOnScreen(screenOrName) {
        if (isAqueous && AqueousService.available)
            return !!AqueousService.sessionState.overview_output && AqueousService.sessionState.overview_output === AqueousService.outputId(_screenName(screenOrName));
        return isNiri && NiriService.inOverview;
    }

    function usesConnectedFrameChromeForScreen(screenOrName) {
        return FrameTransitionState.effectiveConnectedFrameModeActive && frameWindowVisibleForScreen(screenOrName);
    }

    function canShareConnectedFrameChromeForScreen(screenOrName) {
        if (!usesConnectedFrameChromeForScreen(screenOrName))
            return false;
        if (!isHyprland)
            return true;

        const screenName = _screenName(screenOrName);
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        const specialWorkspace = monitor?.lastIpcObject?.specialWorkspace?.name;
        const workspace = specialWorkspace ? Hyprland.workspaces.values.find(w => w.name === specialWorkspace) : monitor?.activeWorkspace;
        if (!workspace)
            return true;
        return !workspace.toplevels.values.some(t => t.lastIpcObject?.fullscreen === 2);
    }

    // Connected mode renders the bar inside the frame surface.
    function frameHostsSurfacesForScreen(screenOrName) {
        return FrameTransitionState.effectiveConnectedFrameModeActive && frameConfiguredForScreen(screenOrName);
    }

    // A surface set to the overlay layer cannot live inside the frame's single top-layer window,
    // so it stays a standalone window (which resolves itself onto the overlay layer) even in connected mode.
    function frameHostsBarForConfig(screenOrName, barConfig) {
        return frameHostsSurfacesForScreen(screenOrName) && !(barConfig?.useOverlayLayer ?? false);
    }

    function frameHostsDockForConfig(screenOrName, dockConfig) {
        return !!dockConfig && frameHostsSurfacesForScreen(screenOrName) && !dockConfig.useOverlayLayer;
    }

    function frameHostsDockForScreen(screenOrName) {
        return SettingsData.dockConfigsForScreen(screenOrName).some(config => frameHostsDockForConfig(screenOrName, config));
    }

    function framePeerSurfacesUseOverlayForScreen(screenOrName) {
        return frameWindowVisibleForScreen(screenOrName);
    }

    function hyprlandToplevelOverlapsDockEdge(hyprToplevel, screenName, dockPosition, dockThickness, screenWidth, screenHeight) {
        if (!hyprToplevel?.lastIpcObject || !screenName)
            return false;
        const monName = hyprToplevel.monitor?.name ?? hyprToplevel.lastIpcObject?.monitor ?? "";
        if (monName && monName !== screenName)
            return false;
        const ipc = hyprToplevel.lastIpcObject;
        const at = ipc.at;
        const size = ipc.size;
        if (!at || !size)
            return false;
        const monX = hyprToplevel.monitor?.x ?? 0;
        const monY = hyprToplevel.monitor?.y ?? 0;
        const winX = at[0] - monX;
        const winY = at[1] - monY;
        const winW = size[0];
        const winH = size[1];
        switch (dockPosition) {
        case SettingsData.Position.Top:
            return winY < dockThickness;
        case SettingsData.Position.Bottom:
            return winY + winH > screenHeight - dockThickness;
        case SettingsData.Position.Left:
            return winX < dockThickness;
        case SettingsData.Position.Right:
            return winX + winW > screenWidth - dockThickness;
        default:
            return false;
        }
    }

    function _hyprlandDockOverlap(screenName, dockPosition, dockThickness, screenWidth, screenHeight) {
        if (!isHyprland || !screenName || !Hyprland.toplevels?.values)
            return false;

        const filtered = filterCurrentWorkspace(sortedToplevels, screenName);
        for (let i = 0; i < filtered.length; i++) {
            const toplevel = filtered[i];
            let hyprToplevel = null;
            for (const t of Hyprland.toplevels.values) {
                if (t.wayland === toplevel) {
                    hyprToplevel = t;
                    break;
                }
            }
            if (hyprlandToplevelOverlapsDockEdge(hyprToplevel, screenName, dockPosition, dockThickness, screenWidth, screenHeight))
                return true;
        }

        const visibleSpecialWorkspace = hyprlandVisibleSpecialWorkspaceOnScreen(screenName);
        if (!visibleSpecialWorkspace)
            return false;

        for (const hyprToplevel of Hyprland.toplevels.values) {
            const wsName = _normalizeSpecialWorkspaceName(hyprToplevel.workspace?.name ?? hyprToplevel.lastIpcObject?.workspace?.name ?? "");
            if (wsName !== visibleSpecialWorkspace)
                continue;
            if (!_hyprlandToplevelMapped(hyprToplevel))
                continue;
            if (hyprlandToplevelOverlapsDockEdge(hyprToplevel, screenName, dockPosition, dockThickness, screenWidth, screenHeight))
                return true;
        }
        return false;
    }

    function _windowAlive(toplevel) {
        if (!toplevel)
            return false;
        const alive = ToplevelManager.toplevels?.values;
        return !!alive && Array.from(alive).some(t => t === toplevel);
    }

    function _fallbackActiveWindow(screenName, includeLastFocused) {
        switch (compositor) {
        case "niri":
            return WindowModel.niriActiveWindow(NiriService.windows, NiriService.allWorkspaces, sortedToplevels || [], Array.from(ToplevelManager.toplevels?.values || []), screenName ?? "", NiriService.lastFocusedWindowId, includeLastFocused);
        default:
            return null;
        }
    }

    function _retainedWindow(screenName, previous) {
        if (!_windowAlive(previous))
            return null;
        switch (compositor) {
        case "niri":
            return WindowModel.niriActiveWorkspaceOccupied(NiriService.windows, NiriService.allWorkspaces, screenName ?? "") ? previous : null;
        default:
            return previous;
        }
    }

    function activeWindowForScreen(screenName, previous, includeLastFocused) {
        switch (compositor) {
        case "aqueous":
            if (AqueousService.available)
                return WindowModel.aqueousActiveWindow(AqueousService.focusedWindow, screenName);
            break;
        }
        const active = ToplevelManager.activeToplevel || _fallbackActiveWindow(screenName, includeLastFocused);
        if (!active)
            return _retainedWindow(screenName, previous);
        if (!screenName || filterCurrentDisplay([active], screenName)?.length > 0)
            return active;
        return _windowAlive(previous) ? previous : null;
    }

    function windowPid(toplevel) {
        if (!toplevel)
            return 0;
        switch (compositor) {
        case "niri":
            return WindowModel.niriWindowPid(NiriService.windows, WindowModel.sortedWindowFor(sortedToplevels || [], toplevel));
        case "hyprland":
            return WindowModel.hyprlandWindowPid(Array.from(Hyprland.toplevels?.values || []), toplevel);
        case "mango":
            return WindowModel.mangoWindowPid(MangoService.windows, WindowModel.sortedWindowFor(sortedToplevels || [], toplevel));
        default:
            return toplevel.pid || 0;
        }
    }

    function windowOnActiveWorkspace(screenName, toplevel, includeLastFocused) {
        switch (compositor) {
        case "niri":
            return WindowModel.niriWindowOnActiveWorkspace(NiriService.windows, NiriService.allWorkspaces, screenName, NiriService.currentOutput, WindowModel.niriFocusedWindow(NiriService.windows, NiriService.lastFocusedWindowId, includeLastFocused));
        case "hyprland":
            if (!Hyprland.toplevels)
                return false;
            try {
                return WindowModel.hyprlandWindowOnActiveWorkspace(Array.from(Hyprland.toplevels.values), Hyprland.focusedWorkspace, toplevel);
            } catch (e) {
                return false;
            }
        default:
            return true;
        }
    }

    function windowsHideBar(screenName, position, thickness, screenWidth, screenHeight) {
        switch (compositor) {
        case "niri":
            return WindowModel.niriBarHideForWindows(NiriService.windows, NiriService.allWorkspaces, screenName, position, thickness, screenWidth, screenHeight, _edgePositions);
        case "hyprland":
        case "mango":
        case "aqueous":
            return filterCurrentWorkspace(sortedToplevels, screenName).length > 0;
        default:
            return false;
        }
    }

    function windowsOverlapDock(screenName, position, thickness, screenWidth, screenHeight) {
        switch (compositor) {
        case "niri":
            return WindowModel.niriDockOverlap(NiriService.windows, NiriService.allWorkspaces, screenName, position, thickness, screenWidth, screenHeight, _edgePositions);
        case "hyprland":
            return _hyprlandDockOverlap(screenName, position, thickness, screenWidth, screenHeight);
        case "mango":
            if (!screenName || !MangoService.windows)
                return false;
            return WindowModel.mangoEdgeOverlap(MangoService.windows, MangoService.outputs[screenName], screenName, position, thickness, screenWidth, screenHeight, _edgePositions);
        case "aqueous":
            return AqueousService.available && AqueousService.overlapsDock(screenName, position, thickness, screenWidth, screenHeight);
        default:
            return false;
        }
    }

    function maximizedWindowOnScreen(screenName) {
        switch (compositor) {
        case "mango":
            return WindowModel.mangoMaximizedOnScreen(MangoService.windows || [], MangoService.outputs[screenName], screenName);
        case "hyprland":
        case "niri":
        case "aqueous":
            return filterCurrentWorkspace(sortedToplevels, screenName).some(t => t?.maximized);
        default:
            return false;
        }
    }

    function overviewFocusedToplevel(toplevels) {
        switch (compositor) {
        case "niri":
            if (!NiriService.inOverview || NiriService.lastFocusedWindowId === null)
                return null;
            return toplevels.find(t => t.niriWindowId === NiriService.lastFocusedWindowId) ?? null;
        default:
            return null;
        }
    }

    function specialWorkspaceName(toplevel) {
        switch (compositor) {
        case "hyprland":
            if (!toplevel || !Hyprland.toplevels)
                return "";
            return WindowModel.hyprlandSpecialWorkspaceName(Array.from(Hyprland.toplevels.values), toplevel);
        default:
            return "";
        }
    }

    function filterHyprlandCurrentDisplaySafe(toplevels, screenName) {
        if (!toplevels || toplevels.length === 0 || !Hyprland.toplevels)
            return toplevels;

        let monitorWindows = new Set();
        try {
            const hy = Array.from(Hyprland.toplevels.values);
            for (const t of hy) {
                const mon = _get(t, ["monitor", "name"], "");
                if (mon === screenName && t.wayland)
                    monitorWindows.add(t.wayland);
            }
        } catch (e) {}

        return toplevels.filter(w => monitorWindows.has(w));
    }

    function _workspaceKeyOf(ws) {
        return ws ? (WorkspaceModel.hyprlandKey(ws) || null) : null;
    }

    function filterHyprlandCurrentWorkspaceSafe(toplevels, screenName) {
        if (!toplevels || toplevels.length === 0 || !Hyprland.toplevels)
            return toplevels;

        let currentWorkspaceId = null;
        try {
            if (Hyprland.monitors) {
                const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
                if (monitor)
                    currentWorkspaceId = _workspaceKeyOf(_get(monitor, ["activeWorkspace"], null));
            }

            if (currentWorkspaceId === null) {
                const hy = Array.from(Hyprland.toplevels.values);
                for (const t of hy) {
                    const mon = _get(t, ["monitor", "name"], "");
                    const wsId = _workspaceKeyOf(_get(t, ["workspace"], null));
                    const active = !!_get(t, ["activated"], false);
                    if (mon === screenName && wsId !== null) {
                        if (active) {
                            currentWorkspaceId = wsId;
                            break;
                        }
                        if (currentWorkspaceId === null)
                            currentWorkspaceId = wsId;
                    }
                }
            }

            if (currentWorkspaceId === null && Hyprland.workspaces) {
                const wss = Array.from(Hyprland.workspaces.values);
                const focusedId = _workspaceKeyOf(Hyprland.focusedWorkspace);
                for (const ws of wss) {
                    const monName = _get(ws, ["monitor", "name"], "");
                    const wsId = _workspaceKeyOf(ws);
                    if (monName === screenName && wsId !== null) {
                        if (focusedId !== null && wsId === focusedId) {
                            currentWorkspaceId = wsId;
                            break;
                        }
                        if (currentWorkspaceId === null)
                            currentWorkspaceId = wsId;
                    }
                }
            }
        } catch (e) {
            log.warn("workspace snapshot failed:", e);
        }

        if (currentWorkspaceId === null)
            return toplevels;

        let map = new Map();
        try {
            const hy = Array.from(Hyprland.toplevels.values);
            for (const t of hy) {
                const wsId = _workspaceKeyOf(_get(t, ["workspace"], null));
                if (t && t.wayland && wsId !== null)
                    map.set(t.wayland, wsId);
            }
        } catch (e) {}

        return toplevels.filter(w => map.get(w) === currentWorkspaceId);
    }

    // Primary detection asks the kernel which process owns the $WAYLAND_DISPLAY
    // socket — the compositor quickshell is actually connected to. Env vars like
    // HYPRLAND_INSTANCE_SIGNATURE / MANGO_INSTANCE_SIGNATURE can leak into the
    // systemd user environment from previous sessions and lie. Unset
    // WAYLAND_DISPLAY falls back to "wayland-0", mirroring wl_display_connect.
    // /proc/net/unix: field 6 is state (01 = listening), 7 inode, 8 bound path.
    // The BSDs have no /proc/net; sockstat(1) -l -u lists listening unix
    // sockets as USER COMMAND PID FD PROTO LOCAL-ADDRESS.
    function detectCompositor() {
        const procScript = 'sock="${WAYLAND_DISPLAY:-wayland-0}"; case "$sock" in /*) ;; *) sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$sock" ;; esac; inode=$(awk -v p="$sock" \'$8 == p && $6 == 1 {print $7; exit}\' /proc/net/unix); [ -n "$inode" ] || exit 1; fd=$(find /proc/[0-9]*/fd/ -mindepth 1 -maxdepth 1 -lname "socket:\\[$inode\\]" 2>/dev/null | head -n1); [ -n "$fd" ] || exit 1; pid="${fd#/proc/}"; cat "/proc/${pid%%/*}/comm"';
        const sockstatScript = 'sock="${WAYLAND_DISPLAY:-wayland-0}"; case "$sock" in /*) ;; *) sock="${XDG_RUNTIME_DIR:-/var/run/user/$(id -u)}/$sock" ;; esac; sockstat -l -u | awk -v p="$sock" \'$6 == p {print $2; exit}\'';
        const script = Qt.platform.os === "unix" ? sockstatScript : procScript;
        Proc.runCommand("waylandSocketOwner", ["sh", "-c", script], (output, exitCode) => {
            const comm = (exitCode === 0 && output) ? output.trim().toLowerCase() : "";
            const name = _compositorNameFromComm(comm);
            if (name) {
                _applyCompositor(name);
                log.info("Detected", name, "from Wayland socket owner:", comm);
                return;
            }
            if (comm)
                log.info("Unrecognized Wayland socket owner:", comm, "- falling back to env detection");
            _detectFromEnv(0);
        }, 0, 3000);
    }

    function _compositorNameFromComm(comm) {
        switch (comm) {
        case "niri":
            return "niri";
        case "hyprland":
            return "hyprland";
        case "sway":
            return "sway";
        case "scroll":
            return "scroll";
        case "mango":
            return "mango";
        case "miracle-wm":
            return "miracle";
        case "labwc":
            return "labwc";
        case "aqueous":
            return "aqueous";
        case "umbriel":
            return "umbriel";
        case "kwin_wayland":
            return "kwin";
        default:
            return "";
        }
    }

    function _applyCompositor(name) {
        isHyprland = name === "hyprland";
        isNiri = name === "niri";
        isMango = name === "mango";
        isSway = name === "sway";
        isScroll = name === "scroll";
        isMiracle = name === "miracle";
        isLabwc = name === "labwc";
        isAqueous = name === "aqueous";
        isUmbriel = name === "umbriel";
        isKwin = name === "kwin";
        compositor = name;
        compositorDetected = true;
        if (isNiri)
            NiriService.generateNiriBlurrule();
        Qt.callLater(seedDmsWindowFloatingRule);
    }

    function seedDmsWindowFloatingRule() {
        if (!supportsWindowRules)
            return;
        if (SettingsData.dmsWindowsFloatingSeeded.includes(compositor)) {
            refreshDmsWindowFloatingRule(true);
            return;
        }
        const seeded = compositor;
        setDmsWindowFloatingRule(true, () => {
            SettingsData.set("dmsWindowsFloatingSeeded", SettingsData.dmsWindowsFloatingSeeded.concat([seeded]));
            refreshDmsWindowFloatingRule(true);
        });
    }

    function refreshDmsWindowFloatingRule(ensureOpaque) {
        if (!supportsWindowRules)
            return;
        const procId = ensureOpaque ? "dms-windowrule-startup-list" : "dms-windowrule-float-list";
        Proc.runCommand(procId, [Proc.dmsBin, "config", "windowrules", "list", compositor], (output, exitCode) => {
            if (exitCode !== 0) {
                if (ensureOpaque)
                    log.warn("failed to list window rules:", exitCode, output);
                return;
            }
            let rules;
            try {
                rules = JSON.parse(output.trim()).rules || [];
            } catch (e) {
                log.warn("failed to parse window rules", e);
                return;
            }
            // Each rule write rewrites the whole rules file, so writes must not overlap.
            syncDmsWindowFloatingRule(rules, () => {
                if (ensureOpaque)
                    ensureDmsOpaqueRule(rules);
            });
        });
    }

    function dmsRuleMatchesCurrentAppId(rule) {
        return (rule.matchCriteria?.appId || "").includes("duxlabs");
    }

    function syncDmsWindowFloatingRule(rules, onDone) {
        const rule = rules.find(rule => rule.id === dmsFloatingRuleId && rule.enabled !== false && rule.actions?.openFloating === true);
        dmsWindowFloatingActive = rule !== undefined;
        if (!rule || dmsRuleMatchesCurrentAppId(rule)) {
            onDone?.();
            return;
        }
        setDmsWindowFloatingRule(true, onDone);
    }

    function reloadAfterWindowRuleWrite() {
        if (isNiri)
            NiriService.validate();
        else if (isMango)
            MangoService.reloadConfig();
        else if (isHyprland)
            HyprlandService.reloadConfig();
    }

    function setDmsRule(id, rule, onDone) {
        if (!supportsWindowRules)
            return;
        const args = rule ? ["add", compositor, JSON.stringify(Object.assign({
                "id": id,
                "enabled": true
            }, rule))] : ["remove", compositor, id];
        Proc.runCommand("dms-windowrule-" + id, [Proc.dmsBin, "config", "windowrules", ...args], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("failed to update DMS window rule", id, exitCode, output);
                return;
            }
            reloadAfterWindowRuleWrite();
            onDone?.();
        });
    }

    function setDmsWindowFloatingRule(enabled, onDone) {
        setDmsRule(dmsFloatingRuleId, enabled ? {
            "name": "DMS Floating Windows",
            "matchCriteria": {
                "appId": "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$"
            },
            "actions": {
                "openFloating": true
            }
        } : null, () => {
            dmsWindowFloatingActive = enabled;
            onDone?.();
        });
    }

    function ensureDmsOpaqueRule(rules) {
        if (rules.some(rule => rule.id === dmsOpaqueRuleId && dmsRuleMatchesCurrentAppId(rule)))
            return;
        // DMS windows are translucent via client alpha; Hyprland's opaque keeps that alpha, force_rgbx would drop it.
        let actions;
        if (isHyprland)
            actions = {
                "opaque": true
            };
        else if (isNiri)
            actions = {
                "opacity": 1.0
            };
        else
            return;
        setDmsRule(dmsOpaqueRuleId, {
            "name": "DMS Window Opaque",
            "matchCriteria": {
                "appId": "^(dev\\.duxlabs\\.shell|com\\.danklinux\\.dms)$"
            },
            "actions": actions
        });
    }

    // Fallback when the socket owner can't be resolved (no ss, unrecognized
    // comm). Same priority order as before, but every candidate must prove
    // liveness; a dead socket/PID falls through to the next candidate instead
    // of winning on a stale env var.
    function _envDetectionCandidates() {
        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "";
        const aqueousSocket = Quickshell.env("AQUEOUS_SOCKET") || "";
        const umbrielSocket = Quickshell.env("UMBRIEL_SOCKET") || "";
        return [
            {
                name: "aqueous",
                present: !!aqueousSocket,
                test: ["test", "-S", aqueousSocket],
                detail: "AQUEOUS_SOCKET " + aqueousSocket
            },
            {
                name: "mango",
                present: !!mangoSignature,
                test: ["test", "-S", mangoSignature],
                detail: "MANGO_INSTANCE_SIGNATURE " + mangoSignature
            },
            {
                name: "umbriel",
                present: !!umbrielSocket,
                test: ["test", "-S", umbrielSocket],
                detail: "UMBRIEL_SOCKET " + umbrielSocket
            },
            {
                name: "niri",
                present: !!niriSocket,
                test: ["test", "-S", niriSocket],
                detail: "NIRI_SOCKET " + niriSocket
            },
            {
                name: "miracle",
                present: !!miracleSocket,
                test: ["test", "-S", miracleSocket],
                detail: "MIRACLESOCK " + miracleSocket
            },
            {
                name: "sway",
                present: !!swaySocket,
                test: ["test", "-S", swaySocket],
                resolve: () => {
                    const desktop = String(Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase();
                    return desktop.includes("sway") ? "sway" : "scroll";
                },
                detail: "SWAYSOCK " + swaySocket
            },
            {
                name: "labwc",
                present: !!labwcPid,
                test: ["sh", "-c", "[ \"$(ps -p \"$LABWC_PID\" -o comm= 2>/dev/null)\" = labwc ]"],
                detail: "LABWC_PID " + labwcPid
            },
            {
                name: "hyprland",
                present: !!hyprlandSignature,
                test: ["test", "-S", runtimeDir + "/hypr/" + hyprlandSignature + "/.socket.sock"],
                detail: "HYPRLAND_INSTANCE_SIGNATURE " + hyprlandSignature
            },
            {
                name: "kwin",
                present: !!Quickshell.env("KDE_FULL_SESSION"),
                test: ["pgrep", "-x", "kwin_wayland"],
                detail: "KDE_FULL_SESSION"
            }
        ];
    }

    function _detectFromEnv(index) {
        const candidates = _envDetectionCandidates();
        for (let i = index; i < candidates.length; i++) {
            const c = candidates[i];
            if (!c.present)
                continue;
            const next = i + 1;
            Proc.runCommand(c.name + "SocketCheck", c.test, (output, exitCode) => {
                if (exitCode !== 0) {
                    log.warn(c.detail, "is set but not alive, skipping");
                    _detectFromEnv(next);
                    return;
                }
                const name = c.resolve ? c.resolve() : c.name;
                _applyCompositor(name);
                log.info("Detected", name, "via", c.detail);
            }, 0);
            return;
        }
        _applyCompositor("unknown");
        log.warn("No compositor detected");
    }

    function powerOffMonitors() {
        if (isNiri)
            return NiriService.powerOffMonitors();
        if (isHyprland)
            return HyprlandService.dpmsOff();
        if (isMango)
            return MangoService.powerOffMonitors();
        if (isSway || isScroll || isMiracle) {
            try {
                I3.dispatch("output * dpms off");
            } catch (_) {}
            return;
        }
        if (isLabwc) {
            Quickshell.execDetached(["dms", "dpms", "off"]);
            return;
        }
        if (isUmbriel)
            return UmbrielService.action("dpms-off");
        if (outputPowerAvailable) {
            setOutputPower(false);
            return;
        }
        log.warn("Cannot power off monitors, unknown compositor");
    }

    function powerOnMonitors() {
        if (isNiri)
            return NiriService.powerOnMonitors();
        if (isHyprland)
            return HyprlandService.dpmsOn();
        if (isMango)
            return MangoService.powerOnMonitors();
        if (isSway || isScroll || isMiracle) {
            try {
                I3.dispatch("output * dpms on");
            } catch (_) {}
            return;
        }
        if (isLabwc) {
            Quickshell.execDetached(["dms", "dpms", "on"]);
            return;
        }
        if (isUmbriel)
            return UmbrielService.action("dpms-on");
        if (outputPowerAvailable) {
            setOutputPower(true);
            return;
        }
        log.warn("Cannot power on monitors, unknown compositor");
    }
    function escapeSwayWorkspaceName(name) {
        return String(name ?? "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
    }

    function dispatchSwayWorkspace(ws) {
        if (!ws)
            return;
        try {
            if (ws.num !== undefined && ws.num !== -1) {
                I3.dispatch(`workspace number ${ws.num}`);
            } else if (ws.name) {
                I3.dispatch(`workspace "${escapeSwayWorkspaceName(ws.name)}"`);
            }
        } catch (_) {}
    }

    function _niriWorkspaceState() {
        return {
            get allWorkspaces() {
                return NiriService.allWorkspaces;
            },
            get currentOutputWorkspaces() {
                return NiriService.getCurrentOutputWorkspaces();
            },
            get focusedIdx() {
                return NiriService.getCurrentWorkspaceNumber();
            },
            get windows() {
                return NiriService.windows;
            }
        };
    }

    function _hyprlandWorkspaceState() {
        return {
            get workspaces() {
                return Hyprland.workspaces?.values || [];
            },
            get monitors() {
                return Hyprland.monitors?.values || [];
            },
            get focusedWorkspace() {
                return Hyprland.focusedWorkspace;
            },
            get toplevels() {
                return Array.from(Hyprland.toplevels?.values || []);
            },
            get workspaceRules() {
                return HyprlandService.workspaceRules;
            },
            get visibleSpecials() {
                return root.hyprlandVisibleSpecialWorkspaces;
            }
        };
    }

    function _mangoWorkspaceState(screenName) {
        return {
            get available() {
                return MangoService.available;
            },
            get tagCount() {
                return MangoService.tagCount;
            },
            get output() {
                return MangoService.getOutputState(screenName);
            },
            get visibleTags() {
                return MangoService.getVisibleTags(screenName);
            },
            get activeTags() {
                return MangoService.getActiveTags(screenName);
            }
        };
    }

    function _i3WorkspaceState() {
        return {
            get workspaces() {
                return I3.workspaces?.values || [];
            }
        };
    }

    function _aqueousWorkspaceState(screenName) {
        return {
            get workspaces() {
                return AqueousService.workspacesForOutput(screenName);
            },
            get toplevels() {
                return AqueousService.toplevels;
            }
        };
    }

    function _followedScreen(screenName, followFocus) {
        return followFocus ? (getFocusedScreenName() || screenName) : screenName;
    }

    function _workspaceKey(record) {
        switch (compositor) {
        case "niri":
            return record.idx;
        case "hyprland":
            return WorkspaceModel.hyprlandKey(record);
        default:
            return record.id;
        }
    }

    function workspacesForScreen(screenName, followFocus, options) {
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriWorkspacesForScreen(_niriWorkspaceState(), screenName, followFocus, options.occupiedOnly, _workspaceRecords);
        case "hyprland":
            return WorkspaceModel.hyprlandWorkspacesForScreen(_hyprlandWorkspaceState(), screenName, followFocus, options.occupiedOnly, options.minCount, options.showSpecial);
        case "mango":
            {
                const name = _followedScreen(screenName, followFocus);
                return WorkspaceModel.mangoWorkspacesForScreen(_mangoWorkspaceState(name), name, options.showAllTags, options.minCount);
            }
        case "sway":
        case "scroll":
        case "miracle":
            return WorkspaceModel.i3WorkspacesForScreen(_i3WorkspaceState(), screenName, followFocus, options.minCount);
        case "aqueous":
            {
                const name = _followedScreen(screenName, followFocus);
                return WorkspaceModel.aqueousWorkspacesForScreen(_aqueousWorkspaceState(name), name, options.occupiedOnly, _workspaceRecords);
            }
        case "umbriel":
            return WorkspaceModel.umbrielWorkspacesForScreen(UmbrielService.workspaces, _followedScreen(screenName, followFocus), options.occupiedOnly, _workspaceRecords);
        default:
            return [];
        }
    }

    function currentWorkspaceKey(screenName, followFocus) {
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriCurrentIdx(_niriWorkspaceState(), screenName, followFocus);
        case "hyprland":
            return WorkspaceModel.hyprlandCurrentId(_hyprlandWorkspaceState(), screenName, followFocus);
        case "mango":
            return WorkspaceModel.mangoCurrentTag(_mangoWorkspaceState(_followedScreen(screenName, followFocus)));
        case "sway":
        case "scroll":
        case "miracle":
            return WorkspaceModel.i3CurrentKey(_i3WorkspaceState(), screenName, followFocus);
        case "aqueous":
            return WorkspaceModel.aqueousCurrentId(_aqueousWorkspaceState(_followedScreen(screenName, followFocus)));
        case "umbriel":
            return WorkspaceModel.umbrielCurrentId(UmbrielService.workspaces, _followedScreen(screenName, followFocus));
        default:
            return 1;
        }
    }

    function isCurrentWorkspace(record, currentKey) {
        if (!record)
            return false;
        switch (compositor) {
        case "mango":
        case "aqueous":
            return record.active === true;
        case "hyprland":
            return record.special === true ? record.active === true : WorkspaceModel.hyprlandKey(record) === currentKey;
        default:
            return _workspaceKey(record) === currentKey;
        }
    }

    function activeWorkspaceForScreen(screenName) {
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriActiveWorkspace(_niriWorkspaceState(), screenName);
        case "hyprland":
            return WorkspaceModel.hyprlandActiveWorkspace(_hyprlandWorkspaceState(), screenName);
        case "mango":
            return WorkspaceModel.mangoActiveWorkspace(_mangoWorkspaceState(screenName), screenName);
        case "sway":
        case "scroll":
        case "miracle":
            return WorkspaceModel.i3ActiveWorkspace(_i3WorkspaceState(), screenName);
        case "aqueous":
            return WorkspaceModel.aqueousActiveWorkspace(_aqueousWorkspaceState(screenName), screenName);
        case "umbriel":
            return WorkspaceModel.umbrielActiveWorkspace(UmbrielService.workspaces, screenName);
        default:
            return null;
        }
    }

    function windowsOnWorkspace(record) {
        if (!record || record.placeholder)
            return [];
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriWindowsOnWorkspace(NiriService.windows || [], record);
        case "hyprland":
            return WorkspaceModel.hyprlandWindowsOnWorkspace(sortedToplevels, record, Array.from(Hyprland.toplevels?.values || []));
        case "mango":
            return WorkspaceModel.mangoWindowsOnWorkspace(sortedToplevels, record);
        case "sway":
        case "scroll":
        case "miracle":
            return WorkspaceModel.i3WindowsOnWorkspace(sortedToplevels, record);
        case "aqueous":
            return WorkspaceModel.aqueousWindowsOnWorkspace(sortedToplevels, record);
        case "umbriel":
            return WorkspaceModel.umbrielWindowsOnWorkspace(UmbrielService.windows, record);
        default:
            return [];
        }
    }

    function workspaceOccupied(record) {
        if (!record || record.placeholder)
            return false;
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriWorkspaceOccupied(NiriService.windows, record);
        case "hyprland":
            return WorkspaceModel.hyprlandWorkspaceOccupied(Array.from(Hyprland.toplevels?.values || []), record);
        case "mango":
        case "umbriel":
            return record.occupied === true;
        case "aqueous":
            return AqueousService.available && WorkspaceModel.aqueousWorkspaceOccupied(AqueousService.toplevels, record);
        default:
            return false;
        }
    }

    function workspaceAppsActive(record, currentKey) {
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriWorkspaceActive(NiriService.allWorkspaces, record);
        case "mango":
            return record.active === true;
        case "sway":
        case "scroll":
        case "miracle":
            return WorkspaceModel.i3WorkspaceFocused(_i3WorkspaceState(), record);
        case "hyprland":
            return isCurrentWorkspace(record, currentKey);
        default:
            return record.id === currentKey;
        }
    }

    function workspaceUrgent(record, loadedUrgent) {
        switch (compositor) {
        case "niri":
        case "sway":
        case "scroll":
        case "miracle":
        case "umbriel":
            return loadedUrgent;
        default:
            return record?.urgent === true;
        }
    }

    function loadWorkspaceUrgent(record) {
        switch (compositor) {
        case "niri":
            return WorkspaceModel.niriWorkspaceUrgent(NiriService.windows, record);
        case "umbriel":
            return WorkspaceModel.umbrielWorkspaceUrgent(UmbrielService.windows, record);
        default:
            return record?.urgent ?? false;
        }
    }

    function switchToWorkspace(record, screenName) {
        if (!record || record.placeholder)
            return;
        switch (compositor) {
        case "niri":
            NiriService.switchToWorkspace(record.id);
            return;
        case "hyprland":
            if (record.special === true) {
                // togglespecialworkspace acts on the focused monitor, so a pill on another monitor's bar focuses that monitor first
                if (screenName && screenName !== Hyprland.focusedMonitor?.name)
                    HyprlandService.focusMonitor(screenName);
                HyprlandService.toggleSpecial(record.name === "special" ? "" : record.name);
                return;
            }
            HyprlandService.focusWorkspace(WorkspaceModel.hyprlandSelector(record));
            return;
        case "mango":
            MangoService.switchToTag(record.output, record.id);
            return;
        case "sway":
        case "scroll":
        case "miracle":
            dispatchSwayWorkspace(typeof record.id === "number" ? {
                "num": record.id
            } : {
                "name": record.id
            });
            return;
        case "aqueous":
            AqueousService.activateWorkspace({
                "id": record.id,
                "aqueousSession": record.session
            });
            return;
        case "umbriel":
            UmbrielService.action(`workspace-switch:${record.idx}/${record.output}`);
            return;
        }
    }

    function stepWorkspace(workspaces, currentKey, direction) {
        if (workspaces.length < 2)
            return;
        const index = workspaces.findIndex(ws => ws && _workspaceKey(ws) === currentKey);
        switchToWorkspace(WorkspaceModel.neighbor(workspaces, Math.max(index, 0), direction));
    }

    function scrollWorkspace(screenName, followFocus, showAllTags, direction) {
        switch (compositor) {
        case "niri":
            {
                const state = _niriWorkspaceState();
                stepWorkspace(WorkspaceModel.niriWorkspacesForScreen(state, screenName, followFocus, false, _workspaceRecords), WorkspaceModel.niriCurrentIdx(state, screenName, followFocus), direction);
                return;
            }
        case "hyprland":
            {
                const state = _hyprlandWorkspaceState();
                stepWorkspace(WorkspaceModel.hyprlandScrollWorkspaces(state, screenName, followFocus), WorkspaceModel.hyprlandScrollCurrentId(state, screenName), direction);
                return;
            }
        case "mango":
            {
                const state = _mangoWorkspaceState(screenName);
                stepWorkspace(WorkspaceModel.mangoScrollWorkspaces(state, screenName, showAllTags), WorkspaceModel.mangoScrollCurrentTag(state), direction);
                return;
            }
        case "sway":
        case "scroll":
        case "miracle":
            {
                const state = _i3WorkspaceState();
                stepWorkspace(WorkspaceModel.i3ScrollWorkspaces(state, screenName, followFocus), WorkspaceModel.i3CurrentKey(state, screenName, followFocus), direction);
                return;
            }
        case "aqueous":
            _scrollAqueousWorkspace(followFocus ? AqueousService.focusedOutput : screenName, direction);
            return;
        case "umbriel":
            {
                const name = _followedScreen(screenName, followFocus);
                stepWorkspace(WorkspaceModel.umbrielWorkspacesForScreen(UmbrielService.workspaces, name, false, _workspaceRecords), WorkspaceModel.umbrielCurrentId(UmbrielService.workspaces, name), direction);
                return;
            }
        }
    }

    function _scrollAqueousWorkspace(screenName, direction) {
        if (!AqueousService.available)
            return;
        const state = _aqueousWorkspaceState(screenName);
        const workspaces = WorkspaceModel.aqueousWorkspacesForScreen(state, screenName, false, _workspaceRecords);
        if (workspaces.length < 2)
            return;
        const currentId = WorkspaceModel.aqueousCurrentId(state);
        const index = workspaces.findIndex(ws => ws.id === currentId);
        if (index < 0)
            return;
        switchToWorkspace(WorkspaceModel.neighbor(workspaces, index, direction));
    }

    function overviewActiveForScreen(screenName) {
        switch (compositor) {
        case "niri":
            return NiriService.inOverview;
        case "mango":
            return MangoService.isOutputInOverview(screenName);
        case "aqueous":
            return overviewActiveOnScreen(screenName);
        default:
            return false;
        }
    }

    function workspacesHiddenByOverview(screenName) {
        switch (compositor) {
        case "mango":
            return MangoService.isOutputInOverview(screenName);
        default:
            return false;
        }
    }

    function toggleOverview(screenName) {
        switch (compositor) {
        case "aqueous":
            AqueousService.toggleOverview(screenName);
            return;
        case "niri":
            NiriService.toggleOverview();
            return;
        case "mango":
            if (MangoService.getOutputState(screenName))
                MangoService.dispatchOnOutput(screenName, "toggleoverview");
            else
                MangoService.dispatch("toggleoverview");
            return;
        }
    }

    function workspaceSecondaryAction(record, screenName) {
        switch (compositor) {
        case "aqueous":
        case "niri":
            toggleOverview(screenName);
            return;
        case "mango":
            if (record)
                MangoService.toggleTag(screenName, record.id);
            return;
        }
    }

    readonly property bool canStepWindowFocus: compositor === "niri" || compositor === "hyprland" || compositor === "mango"

    function stepWindowFocus(screenName, direction) {
        switch (compositor) {
        case "niri":
            if (direction > 0)
                NiriService.focusColumnRight(screenName);
            else
                NiriService.focusColumnLeft(screenName);
            return true;
        case "hyprland":
            if (screenName && screenName !== Hyprland.focusedMonitor?.name)
                HyprlandService.focusMonitor(screenName);
            HyprlandService.cycleWindow(direction > 0);
            return true;
        case "mango":
            {
                const command = direction > 0 ? "focusstack,next" : "focusstack,prev";
                if (screenName)
                    MangoService.dispatchOnOutput(screenName, command);
                else
                    MangoService.dispatch(command);
                return true;
            }
        default:
            return false;
        }
    }

    function focusWindow(windowId) {
        switch (compositor) {
        case "aqueous":
            AqueousService.command("window.activate", windowId);
            return true;
        case "hyprland":
            HyprlandService.focusWindow(windowId);
            return true;
        case "niri":
            NiriService.focusWindow(windowId);
            return true;
        case "umbriel":
            UmbrielService.action("window-focus:" + windowId);
            return true;
        default:
            return false;
        }
    }

    function moveWorkspace(record, target) {
        switch (compositor) {
        case "niri":
            NiriService.moveWorkspaceToIndex(record.id, target.idx);
            return;
        }
    }

    Binding {
        target: SettingsData
        property: "activeCompositor"
        value: root.compositor
    }

    Connections {
        target: SettingsData

        function onCompositorLayoutRefreshNeeded(frame) {
            if (root.isNiri && typeof NiriService !== "undefined")
                NiriService.generateNiriLayoutConfig(frame);
            if (root.isHyprland && typeof HyprlandService !== "undefined")
                HyprlandService.generateLayoutConfig(frame);
            if (!frame && root.isMango && typeof MangoService !== "undefined")
                MangoService.generateLayoutConfig();
        }

        function onBlurStrengthRefreshNeeded() {
            if (root.isAqueous && typeof AqueousConfigService !== "undefined") {
                AqueousConfigService.applyBlurStrength();
                return;
            }
            onCompositorLayoutRefreshNeeded(false);
        }

        function onCompositorInputRefreshNeeded() {
            if (root.isNiri && typeof NiriService !== "undefined")
                NiriService.generateNiriInputConfig();
            if (root.isHyprland && typeof HyprlandService !== "undefined")
                HyprlandService.generateInputConfig();
            if (root.isMango && typeof MangoService !== "undefined")
                MangoService.generateInputConfig();
        }

        function onCompositorCursorRefreshNeeded() {
            if (root.isNiri && typeof NiriService !== "undefined") {
                NiriService.generateNiriCursorConfig();
                return;
            }
            if (root.isHyprland && typeof HyprlandService !== "undefined") {
                HyprlandService.generateCursorConfig();
                return;
            }
            if (root.isMango && typeof MangoService !== "undefined") {
                MangoService.generateCursorConfig();
                return;
            }
        }
    }
}
