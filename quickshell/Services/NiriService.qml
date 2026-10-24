pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon
import "../Common/OutputModel.js" as OutputModel
import "../Common/BlurStrength.js" as BlurStrength

Singleton {
    id: root
    readonly property var log: Log.scoped("NiriService")

    readonly property string socketPath: Quickshell.env("NIRI_SOCKET")

    property var workspaces: ({})
    property var allWorkspaces: []
    property int focusedWorkspaceIndex: 0
    property string focusedWorkspaceId: ""
    property var currentOutputWorkspaces: []
    property string currentOutput: ""

    property var outputs: ({})
    property var windows: []
    property bool titleOnlyWindowsUpdate: false
    property var displayScales: ({})
    property var lastFocusedWindowId: null

    property var _realOutputs: ({})

    property bool inOverview: false

    property var casts: []
    property bool hasCasts: casts.length > 0
    property bool hasActiveCast: casts.some(c => c.is_active)

    property int currentKeyboardLayoutIndex: 0
    property var keyboardLayoutNames: []

    property bool touchpadEnabled: true
    property bool _touchpadStateInitialized: false
    signal touchpadToggled

    property string configValidationOutput: ""
    property bool hasInitialConnection: false
    property bool suppressConfigToast: true
    property bool suppressNextConfigToast: false
    property bool matugenSuppression: false
    property bool configGenerationPending: false
    property int _layoutRequestRevision: 0
    property int _layoutAppliedRevision: 0
    property int _frameTransitionRevision: 0
    property int _awaitingLayoutReloadRevision: 0
    property string _lastGeneratedAlttabContent: ""
    readonly property bool frameLayoutReady: _layoutAppliedRevision >= _frameTransitionRevision
    readonly property string overviewBackdropConfig: niriOverviewBlock()
    onOverviewBackdropConfigChanged: generateNiriLayoutConfig()
    readonly property string activeWindowColor: SettingsData.niriActiveWindowColorEnabled ? niriColor(Theme.primary) : ""
    onActiveWindowColorChanged: generateNiriLayoutConfig()

    // dms/layout.kdl is the source of truth for xray; parsed once before the first regeneration
    property bool layoutXrayEnabled: true
    property bool layoutBarXrayEnabled: true
    property bool _layoutXrayLoaded: false
    property bool _layoutXrayLoading: false

    readonly property string screenshotsDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.PicturesLocation)) + "/Screenshots"
    property string pendingScreenshotPath: ""

    signal windowUrgentChanged
    signal configReloaded

    function setWorkspaces(newMap) {
        root.workspaces = newMap;
        root.allWorkspaces = Object.values(newMap).sort((a, b) => a.idx - b.idx);
    }

    function updateWorkspace(workspaceId, changes) {
        const ws = root.workspaces[workspaceId];
        if (!ws)
            return;
        if (Object.keys(changes).every(key => ws[key] === changes[key]))
            return;
        const updatedWorkspaces = Object.assign({}, root.workspaces);
        updatedWorkspaces[workspaceId] = Object.assign({}, ws, changes);
        setWorkspaces(updatedWorkspaces);
    }

    function validate() {
        validateProcess.running = true;
    }

    Component.onCompleted: {
        fetchOutputs();
        generateNiriInputConfig();
    }

    Connections {
        target: Theme
        enabled: CompositorService.isNiri

        function onScreenTransitionNeeded() {
            root.doScreenTransition();
        }

        function onThemeGenerationStarting() {
            root.suppressNextToast();
        }
    }

    Binding {
        target: Theme
        property: "matugenToastSuppressed"
        value: root.matugenSuppression
    }

    Timer {
        id: suppressToastTimer
        interval: 3000
        onTriggered: root.suppressConfigToast = false
    }

    Timer {
        id: suppressResetTimer
        interval: 5000
        onTriggered: root.matugenSuppression = false
    }

    DeferredAction {
        id: configGenerationAction
        onTriggered: root.doGenerateNiriLayoutConfig()
    }

    property int _lastGapValue: -1

    Connections {
        target: SettingsData
        enabled: CompositorService.isNiri
        function onBarConfigsChanged() {
            const newGaps = Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4));
            if (newGaps === root._lastGapValue)
                return;
            root._lastGapValue = newGaps;
            generateNiriLayoutConfig();
        }
    }

    Connections {
        target: CompositorService
        function onIsNiriChanged() {
            if (!CompositorService.isNiri)
                return;
            generateNiriInputConfig();
            generateNiriLayoutConfig();
        }
    }

    Process {
        id: validateProcess
        command: ["niri", "validate"]
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const lines = text.split('\n');
                const trimmedLines = lines.map(line => line.replace(/\s+$/, '')).filter(line => line.length > 0);
                configValidationOutput = trimmedLines.join('\n').trim();
            }
        }

        onExited: exitCode => {
            if (exitCode === 0) {
                configValidationOutput = "";
            } else if (hasInitialConnection && configValidationOutput.length > 0) {
                ToastService.showError(I18n.tr("niri: failed to load config"), configValidationOutput, "", "niri-config");
            }
        }
    }

    Process {
        id: writeConfigProcess
        property string configContent: ""
        property string configPath: ""
        property int requestRevision: 0

        onExited: exitCode => {
            if (exitCode === 0) {
                log.info("Generated layout config at", configPath);
            } else {
                if (root._awaitingLayoutReloadRevision === requestRevision)
                    root._awaitingLayoutReloadRevision = 0;
                // Best-effort ack so a failed write can't wedge frame transitions
                root._layoutAppliedRevision = Math.max(root._layoutAppliedRevision, requestRevision);
                log.warn("Failed to write layout config, exit code:", exitCode);
            }
            if (root.configGenerationPending && root._awaitingLayoutReloadRevision <= root._layoutAppliedRevision)
                configGenerationAction.schedule();
        }
    }

    Process {
        id: writeAlttabProcess
        property string alttabContent: ""
        property string alttabPath: ""

        onExited: exitCode => {
            if (exitCode === 0) {
                log.info("Generated alttab config at", alttabPath);
                return;
            }
            log.warn("Failed to write alttab config, exit code:", exitCode);
        }
    }

    Process {
        id: writeBlurruleProcess
        property string blurrulePath: ""

        onExited: exitCode => {
            if (exitCode === 0) {
                log.info("Generated wpblur config at", blurrulePath);
                return;
            }
            log.warn("Failed to write wpblur config, exit code:", exitCode);
        }
    }

    Process {
        id: writeInputProcess
        property string inputContent: ""
        property string inputPath: ""

        onExited: exitCode => {
            if (exitCode === 0) {
                log.info("Generated input config at", inputPath);
                return;
            }
            log.warn("Failed to write input config, exit code:", exitCode);
        }
    }

    Process {
        id: writeCursorProcess
        property string cursorContent: ""
        property string cursorPath: ""

        onExited: exitCode => {
            if (exitCode === 0) {
                log.info("Generated cursor config at", cursorPath);
                return;
            }
            log.warn("Failed to write cursor config, exit code:", exitCode);
        }
    }

    DCommon.DSocket {
        id: eventStreamSocket
        path: root.socketPath
        connected: CompositorService.isNiri

        onConnectionStateChanged: {
            root._touchpadStateInitialized = false;
            if (linkUp) {
                send('"EventStream"');
                fetchOutputs();
            }
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line);
                    handleNiriEvent(event);
                } catch (e) {
                    log.warn("Failed to parse event:", line, e);
                }
            }
        }
    }

    DCommon.DSocket {
        id: requestSocket
        path: root.socketPath
        connected: CompositorService.isNiri
    }

    Loader {
        id: outputCycleLoader
        active: CompositorService.isNiri
        sourceComponent: NiriOutputCycle {
            wlrOutputService: WlrOutputService
            socket: requestSocket
            isNiri: CompositorService.isNiri
            currentOutput: root.currentOutput
        }
    }

    function fetchOutputs() {
        if (!CompositorService.isNiri)
            return;
        Proc.runCommand("niri-fetch-outputs", ["niri", "msg", "-j", "outputs"], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to fetch outputs, exit code:", exitCode);
                return;
            }
            try {
                const outputsData = JSON.parse(output);
                outputs = outputsData;
                log.info("Loaded", Object.keys(outputsData).length, "outputs");
                updateDisplayScales();
                if (windows.length > 0) {
                    windows = sortWindowsByLayout(windows);
                }
            } catch (e) {
                log.warn("Failed to parse outputs:", e);
            }
        });
    }

    function cycleSingleOutput() {
        if (!outputCycleLoader.item)
            return "OUTPUT_CYCLE_UNSUPPORTED";
        return outputCycleLoader.item.cycleSingleOutput();
    }

    function updateDisplayScales() {
        if (!outputs || Object.keys(outputs).length === 0)
            return;
        const scales = {};
        for (const outputName in outputs) {
            const output = outputs[outputName];
            if (output.logical && output.logical.scale !== undefined) {
                scales[outputName] = output.logical.scale;
            }
        }

        if (sameScales(displayScales, scales))
            return;
        displayScales = scales;
    }

    function sameScales(a, b) {
        const names = Object.keys(a);
        if (names.length !== Object.keys(b).length)
            return false;
        return names.every(name => a[name] === b[name]);
    }

    function sortWindowsByLayout(windowList) {
        const enriched = windowList.map(w => {
            const ws = workspaces[w.workspace_id];
            if (!ws) {
                return {
                    "window": w,
                    "outputX": 999999,
                    "outputY": 999999,
                    "wsIdx": 999999,
                    "col": 999999,
                    "row": 999999
                };
            }

            const outputInfo = outputs[ws.output];
            const outputX = (outputInfo && outputInfo.logical) ? outputInfo.logical.x : 999999;
            const outputY = (outputInfo && outputInfo.logical) ? outputInfo.logical.y : 999999;

            const pos = w.layout?.pos_in_scrolling_layout;
            const col = (pos && pos.length >= 2) ? pos[0] : 999999;
            const row = (pos && pos.length >= 2) ? pos[1] : 999999;

            return {
                "window": w,
                "outputX": outputX,
                "outputY": outputY,
                "wsIdx": ws.idx,
                "col": col,
                "row": row
            };
        });

        enriched.sort((a, b) => {
            if (a.outputX !== b.outputX)
                return a.outputX - b.outputX;
            if (a.outputY !== b.outputY)
                return a.outputY - b.outputY;
            if (a.wsIdx !== b.wsIdx)
                return a.wsIdx - b.wsIdx;
            if (a.col !== b.col)
                return a.col - b.col;
            if (a.row !== b.row)
                return a.row - b.row;
            return a.window.id - b.window.id;
        });

        return enriched.map(e => e.window);
    }

    function handleNiriEvent(event) {
        const eventType = Object.keys(event)[0];

        switch (eventType) {
        case 'WorkspacesChanged':
            handleWorkspacesChanged(event.WorkspacesChanged);
            break;
        case 'WorkspaceActivated':
            handleWorkspaceActivated(event.WorkspaceActivated);
            break;
        case 'WorkspaceActiveWindowChanged':
            handleWorkspaceActiveWindowChanged(event.WorkspaceActiveWindowChanged);
            break;
        case 'WindowFocusChanged':
            handleWindowFocusChanged(event.WindowFocusChanged);
            break;
        case 'WindowsChanged':
            handleWindowsChanged(event.WindowsChanged);
            break;
        case 'WindowClosed':
            handleWindowClosed(event.WindowClosed);
            break;
        case 'WindowOpenedOrChanged':
            handleWindowOpenedOrChanged(event.WindowOpenedOrChanged);
            break;
        case 'WindowLayoutsChanged':
            handleWindowLayoutsChanged(event.WindowLayoutsChanged);
            break;
        case 'OutputsChanged':
            handleOutputsChanged(event.OutputsChanged);
            break;
        case 'OverviewOpenedOrClosed':
            handleOverviewChanged(event.OverviewOpenedOrClosed);
            break;
        case 'ConfigLoaded':
            handleConfigLoaded(event.ConfigLoaded);
            break;
        case 'KeyboardLayoutsChanged':
            handleKeyboardLayoutsChanged(event.KeyboardLayoutsChanged);
            break;
        case 'KeyboardLayoutSwitched':
            handleKeyboardLayoutSwitched(event.KeyboardLayoutSwitched);
            break;
        case 'TouchpadToggled':
            handleTouchpadToggled(event.TouchpadToggled);
            break;
        case 'WorkspaceUrgencyChanged':
            handleWorkspaceUrgencyChanged(event.WorkspaceUrgencyChanged);
            break;
        case 'WindowUrgencyChanged':
            handleWindowUrgencyChanged(event.WindowUrgencyChanged);
            break;
        case 'ScreenshotCaptured':
            handleScreenshotCaptured(event.ScreenshotCaptured);
            break;
        case 'CastsChanged':
            handleCastsChanged(event.CastsChanged);
            break;
        case 'CastStartedOrChanged':
            handleCastStartedOrChanged(event.CastStartedOrChanged);
            break;
        case 'CastStopped':
            handleCastStopped(event.CastStopped);
            break;
        }
    }

    function handleTouchpadToggled(data) {
        // Each subscription starts with a snapshot; only later changes show the OSD.
        const showOsd = _touchpadStateInitialized && touchpadEnabled !== data.on;
        touchpadEnabled = data.on;
        _touchpadStateInitialized = true;
        if (showOsd)
            touchpadToggled();
    }

    function handleWorkspacesChanged(data) {
        const newWorkspaces = {};

        for (const ws of data.workspaces) {
            const oldWs = root.workspaces[ws.id];
            newWorkspaces[ws.id] = ws;
            if (oldWs && oldWs.active_window_id !== undefined) {
                newWorkspaces[ws.id].active_window_id = oldWs.active_window_id;
            }
        }

        setWorkspaces(newWorkspaces);

        focusedWorkspaceIndex = allWorkspaces.findIndex(w => w.is_focused);
        if (focusedWorkspaceIndex >= 0) {
            const focusedWs = allWorkspaces[focusedWorkspaceIndex];
            focusedWorkspaceId = focusedWs.id;
            currentOutput = focusedWs.output || "";
        } else {
            focusedWorkspaceIndex = 0;
            focusedWorkspaceId = "";
        }

        updateCurrentOutputWorkspaces();
    }

    function handleWorkspaceActivated(data) {
        const ws = root.workspaces[data.id];
        if (!ws) {
            return;
        }
        const output = ws.output;

        const updatedWorkspaces = {};

        for (const id in root.workspaces) {
            const workspace = root.workspaces[id];
            const got_activated = workspace.id === data.id;

            const updatedWs = {};
            for (let prop in workspace) {
                updatedWs[prop] = workspace[prop];
            }

            if (workspace.output === output) {
                updatedWs.is_active = got_activated;
            }

            if (data.focused) {
                updatedWs.is_focused = got_activated;
            }

            updatedWorkspaces[id] = updatedWs;
        }

        setWorkspaces(updatedWorkspaces);

        if (!data.focused) {
            updateCurrentOutputWorkspaces();
            return;
        }

        focusedWorkspaceId = data.id;
        focusedWorkspaceIndex = allWorkspaces.findIndex(w => w.id === data.id);

        if (focusedWorkspaceIndex >= 0) {
            currentOutput = allWorkspaces[focusedWorkspaceIndex].output || "";
        }

        updateCurrentOutputWorkspaces();
    }

    function handleWindowFocusChanged(data) {
        const focusedWindowId = data.id;
        if (focusedWindowId !== null && focusedWindowId !== undefined)
            lastFocusedWindowId = focusedWindowId;

        // Only clone windows whose focus flag changes; skip reassignment if nothing changed.
        let focusedWindow = null;
        let changed = false;
        const updatedWindows = new Array(windows.length);

        for (var i = 0; i < windows.length; i++) {
            const w = windows[i];
            const isFocused = w.id === focusedWindowId;
            if (!!w.is_focused === isFocused) {
                updatedWindows[i] = w;
                if (isFocused)
                    focusedWindow = w;
                continue;
            }
            const updatedWindow = Object.assign({}, w, {
                "is_focused": isFocused
            });
            if (isFocused)
                focusedWindow = updatedWindow;
            updatedWindows[i] = updatedWindow;
            changed = true;
        }

        if (changed)
            windows = updatedWindows;

        if (!focusedWindow)
            return;
        updateWorkspace(focusedWindow.workspace_id, {
            "active_window_id": focusedWindowId
        });
    }

    function handleWorkspaceActiveWindowChanged(data) {
        if (root.workspaces[data.workspace_id]) {
            if (data.active_window_id !== null && data.active_window_id !== undefined)
                lastFocusedWindowId = data.active_window_id;
            updateWorkspace(data.workspace_id, {
                "active_window_id": data.active_window_id
            });
        }

        let changed = false;
        const updatedWindows = new Array(windows.length);

        for (var i = 0; i < windows.length; i++) {
            const w = windows[i];
            let isFocused;
            if (data.active_window_id !== null && data.active_window_id !== undefined) {
                isFocused = (w.id == data.active_window_id);
            } else {
                isFocused = w.workspace_id == data.workspace_id ? false : !!w.is_focused;
            }
            if (!!w.is_focused === isFocused) {
                updatedWindows[i] = w;
                continue;
            }
            updatedWindows[i] = Object.assign({}, w, {
                "is_focused": isFocused
            });
            changed = true;
        }

        if (changed)
            windows = updatedWindows;
    }

    function handleWindowsChanged(data) {
        windows = sortWindowsByLayout(data.windows);
    }

    function handleWindowClosed(data) {
        windows = windows.filter(w => w.id !== data.id);
    }

    function differsOnlyInTitle(previous, next) {
        if (previous.title === next.title)
            return false;
        const keys = new Set([...Object.keys(previous), ...Object.keys(next)]);
        for (const key of keys) {
            if (key !== "title" && JSON.stringify(previous[key]) !== JSON.stringify(next[key]))
                return false;
        }
        return true;
    }

    function handleWindowOpenedOrChanged(data) {
        if (!data.window)
            return;
        const window = data.window;
        const existingIndex = windows.findIndex(w => w.id === window.id);
        if (existingIndex < 0) {
            windows = sortWindowsByLayout([...windows, window]);
            return;
        }

        const updatedWindows = [...windows];
        updatedWindows[existingIndex] = window;
        if (!differsOnlyInTitle(windows[existingIndex], window)) {
            windows = sortWindowsByLayout(updatedWindows);
            return;
        }
        titleOnlyWindowsUpdate = true;
        windows = updatedWindows;
        titleOnlyWindowsUpdate = false;
    }

    function handleWindowLayoutsChanged(data) {
        if (!data.changes)
            return;
        const updatedWindows = [...windows];
        let hasChanges = false;

        for (const change of data.changes) {
            const windowId = change[0];
            const layoutData = change[1];

            const windowIndex = updatedWindows.findIndex(w => w.id === windowId);
            if (windowIndex < 0)
                continue;
            const updatedWindow = {};
            for (var prop in updatedWindows[windowIndex]) {
                updatedWindow[prop] = updatedWindows[windowIndex][prop];
            }
            updatedWindow.layout = layoutData;
            updatedWindows[windowIndex] = updatedWindow;
            hasChanges = true;
        }

        if (!hasChanges)
            return;
        windows = sortWindowsByLayout(updatedWindows);
    }

    function handleOutputsChanged(data) {
        if (!data.outputs)
            return;
        outputs = data.outputs;
        updateDisplayScales();
        windows = sortWindowsByLayout(windows);
    }

    function handleOverviewChanged(data) {
        inOverview = data.is_open;
    }

    function handleConfigLoaded(data) {
        if (data.failed) {
            validateProcess.running = true;
            // Best-effort ack: a rejected reload must not wedge frame transitions
            if (_awaitingLayoutReloadRevision > _layoutAppliedRevision) {
                _layoutAppliedRevision = _awaitingLayoutReloadRevision;
                _awaitingLayoutReloadRevision = 0;
            }
            if (configGenerationPending)
                configGenerationAction.schedule();
            return;
        }

        configValidationOutput = "";
        ToastService.dismissCategory("niri-config");
        fetchOutputs();
        if (_awaitingLayoutReloadRevision > _layoutAppliedRevision) {
            _layoutAppliedRevision = _awaitingLayoutReloadRevision;
            _awaitingLayoutReloadRevision = 0;
        }
        if (configGenerationPending)
            configGenerationAction.schedule();
        configReloaded();

        if (hasInitialConnection && !suppressConfigToast && !suppressNextConfigToast && !matugenSuppression && SessionData.showConfigReloadToast) {
            ToastService.showInfo(I18n.tr("niri: config reloaded"), "", "", "niri-config");
        } else if (suppressNextConfigToast) {
            suppressNextConfigToast = false;
            suppressResetTimer.stop();
        }

        if (!hasInitialConnection) {
            hasInitialConnection = true;
            suppressToastTimer.start();
        }
    }

    function handleKeyboardLayoutsChanged(data) {
        keyboardLayoutNames = data.keyboard_layouts.names;
        currentKeyboardLayoutIndex = data.keyboard_layouts.current_idx;
    }

    function handleKeyboardLayoutSwitched(data) {
        currentKeyboardLayoutIndex = data.idx;
    }

    function handleWorkspaceUrgencyChanged(data) {
        if (!root.workspaces[data.id])
            return;
        updateWorkspace(data.id, {
            "is_urgent": data.urgent
        });

        windowUrgentChanged();
    }

    function handleWindowUrgencyChanged(data) {
        const windowIndex = windows.findIndex(w => w.id === data.id);
        if (windowIndex < 0)
            return;
        const updatedWindows = [...windows];
        const updatedWindow = {};
        for (let prop in updatedWindows[windowIndex]) {
            updatedWindow[prop] = updatedWindows[windowIndex][prop];
        }
        updatedWindow.is_urgent = data.urgent;
        updatedWindows[windowIndex] = updatedWindow;
        windows = updatedWindows;

        windowUrgentChanged();
    }

    function handleScreenshotCaptured(data) {
        if (!data.path)
            return;
        if (pendingScreenshotPath && data.path === pendingScreenshotPath) {
            const editor = Quickshell.env("DMS_SCREENSHOT_EDITOR");
            let command;
            if (editor === "satty" || !editor) {
                command = ["satty", "-f", data.path];
            } else if (editor === "swappy") {
                command = ["swappy", "-f", data.path];
            } else {
                // Custom command with %path% placeholder
                command = editor.split(" ").map(arg => arg === "%path%" ? data.path : arg);
            }
            Quickshell.execDetached({
                "command": command
            });
            pendingScreenshotPath = "";
        }
    }

    function handleCastsChanged(data) {
        casts = data.casts || [];
    }

    function handleCastStartedOrChanged(data) {
        if (!data.cast)
            return;
        const cast = data.cast;
        const existingIndex = casts.findIndex(c => c.stream_id === cast.stream_id);
        if (existingIndex >= 0) {
            const updatedCasts = [...casts];
            updatedCasts[existingIndex] = cast;
            casts = updatedCasts;
        } else {
            casts = [...casts, cast];
        }
    }

    function handleCastStopped(data) {
        casts = casts.filter(c => c.stream_id !== data.stream_id);
    }

    function updateCurrentOutputWorkspaces() {
        if (!currentOutput) {
            currentOutputWorkspaces = allWorkspaces;
            return;
        }

        const outputWs = allWorkspaces.filter(w => w.output === currentOutput);
        currentOutputWorkspaces = outputWs;
    }

    function send(request) {
        if (!CompositorService.isNiri || !requestSocket.connected)
            return false;
        requestSocket.send(request);
        return true;
    }

    function doScreenTransition() {
        return send({
            "Action": {
                "DoScreenTransition": {
                    "delay_ms": 0
                }
            }
        });
    }

    function toggleOverview() {
        return send({
            "Action": {
                "ToggleOverview": {}
            }
        });
    }

    function closeOverview() {
        return send({
            "Action": {
                "CloseOverview": {}
            }
        });
    }

    function focusMonitor(outputName) {
        return send({
            "Action": {
                "FocusMonitor": {
                    "output": outputName
                }
            }
        });
    }

    function focusColumnLeft(outputName) {
        if (outputName && outputName !== currentOutput)
            focusMonitor(outputName);
        return send({
            "Action": {
                "FocusColumnLeft": {}
            }
        });
    }

    function focusColumnRight(outputName) {
        if (outputName && outputName !== currentOutput)
            focusMonitor(outputName);
        return send({
            "Action": {
                "FocusColumnRight": {}
            }
        });
    }

    function switchToWorkspace(workspaceId) {
        return send({
            "Action": {
                "FocusWorkspace": {
                    "reference": {
                        "Id": workspaceId
                    }
                }
            }
        });
    }

    function focusWindow(windowId) {
        return send({
            "Action": {
                "FocusWindow": {
                    "id": windowId
                }
            }
        });
    }

    function powerOffMonitors() {
        return send({
            "Action": {
                "PowerOffMonitors": {}
            }
        });
    }

    function powerOnMonitors() {
        return send({
            "Action": {
                "PowerOnMonitors": {}
            }
        });
    }

    function cycleKeyboardLayout() {
        return send({
            "Action": {
                "SwitchLayout": {
                    "layout": "Next"
                }
            }
        });
    }

    function quit() {
        return send({
            "Action": {
                "Quit": {
                    "skip_confirmation": true
                }
            }
        });
    }

    function screenshot() {
        Paths.mkdir(screenshotsDir);
        pendingScreenshotPath = "";
        const timestamp = Date.now();
        const path = `${screenshotsDir}/dms-screenshot-${timestamp}.png`;
        pendingScreenshotPath = path;

        return send({
            "Action": {
                "Screenshot": {
                    "show_pointer": true,
                    "path": path
                }
            }
        });
    }

    function screenshotScreen() {
        Paths.mkdir(screenshotsDir);
        pendingScreenshotPath = "";
        const timestamp = Date.now();
        const path = `${screenshotsDir}/dms-screenshot-${timestamp}.png`;
        pendingScreenshotPath = path;

        return send({
            "Action": {
                "ScreenshotScreen": {
                    "write_to_disk": true,
                    "show_pointer": true,
                    "path": path
                }
            }
        });
    }

    function screenshotWindow() {
        Paths.mkdir(screenshotsDir);
        pendingScreenshotPath = "";
        const timestamp = Date.now();
        const path = `${screenshotsDir}/dms-screenshot-${timestamp}.png`;
        pendingScreenshotPath = path;

        return send({
            "Action": {
                "ScreenshotWindow": {
                    "write_to_disk": true,
                    "show_pointer": true,
                    "path": path
                }
            }
        });
    }

    function getCurrentOutputWorkspaces() {
        return currentOutputWorkspaces.slice();
    }

    function getCurrentWorkspaceNumber() {
        if (focusedWorkspaceIndex >= 0 && focusedWorkspaceIndex < allWorkspaces.length) {
            return allWorkspaces[focusedWorkspaceIndex].idx;
        }
        return 1;
    }

    function getCurrentKeyboardLayoutName() {
        if (currentKeyboardLayoutIndex >= 0 && currentKeyboardLayoutIndex < keyboardLayoutNames.length) {
            return keyboardLayoutNames[currentKeyboardLayoutIndex];
        }
        return "";
    }

    function suppressNextToast() {
        matugenSuppression = true;
        suppressResetTimer.restart();
    }

    function sortToplevels(toplevels) {
        if (!toplevels || toplevels.length === 0 || !CompositorService.isNiri || windows.length === 0) {
            return [...toplevels];
        }

        const usedToplevels = new Set();
        const enrichedToplevels = [];

        for (const niriWindow of sortWindowsByLayout(windows)) {
            let bestMatch = null;
            let bestScore = -1;

            for (const toplevel of toplevels) {
                if (usedToplevels.has(toplevel))
                    continue;
                if (toplevel.appId === niriWindow.app_id) {
                    let score = 1;

                    if (niriWindow.title && toplevel.title) {
                        if (toplevel.title === niriWindow.title) {
                            score = 3;
                        } else if (toplevel.title.includes(niriWindow.title) || niriWindow.title.includes(toplevel.title)) {
                            score = 2;
                        }
                    }

                    if (score > bestScore) {
                        bestScore = score;
                        bestMatch = toplevel;
                        if (score === 3)
                            break;
                    }
                }
            }

            if (!bestMatch)
                continue;
            usedToplevels.add(bestMatch);

            const workspace = workspaces[niriWindow.workspace_id];
            const isFocused = niriWindow.is_focused ?? (workspace && workspace.active_window_id === niriWindow.id) ?? false;

            const enrichedToplevel = {
                "appId": bestMatch.appId,
                "title": bestMatch.title,
                "sourceToplevel": bestMatch,
                "activated": isFocused,
                "niriWindowId": niriWindow.id,
                "niriWorkspaceId": niriWindow.workspace_id,
                "activate": function () {
                    return NiriService.focusWindow(niriWindow.id);
                },
                "close": function () {
                    if (bestMatch.close) {
                        return bestMatch.close();
                    }
                    return false;
                }
            };

            for (let prop in bestMatch) {
                if (!(prop in enrichedToplevel)) {
                    enrichedToplevel[prop] = bestMatch[prop];
                }
            }

            enrichedToplevels.push(enrichedToplevel);
        }

        for (const toplevel of toplevels) {
            if (!usedToplevels.has(toplevel)) {
                enrichedToplevels.push(toplevel);
            }
        }

        return enrichedToplevels;
    }

    function _matchAndEnrichToplevels(toplevels, niriWindows) {
        const usedToplevels = new Set();
        const result = [];

        for (const niriWindow of niriWindows) {
            let bestMatch = null;
            let bestScore = -1;

            for (const toplevel of toplevels) {
                if (usedToplevels.has(toplevel))
                    continue;
                if (toplevel.appId !== niriWindow.app_id)
                    continue;

                let score = 1;
                if (niriWindow.title && toplevel.title) {
                    if (toplevel.title === niriWindow.title) {
                        score = 3;
                    } else if (toplevel.title.includes(niriWindow.title) || niriWindow.title.includes(toplevel.title)) {
                        score = 2;
                    }
                }

                if (score > bestScore) {
                    bestScore = score;
                    bestMatch = toplevel;
                    if (score === 3)
                        break;
                }
            }

            if (!bestMatch)
                continue;
            usedToplevels.add(bestMatch);

            const workspace = workspaces[niriWindow.workspace_id];
            const isFocused = niriWindow.is_focused ?? (workspace && workspace.active_window_id === niriWindow.id) ?? false;

            const enrichedToplevel = {
                "appId": bestMatch.appId,
                "title": bestMatch.title,
                "sourceToplevel": bestMatch,
                "activated": isFocused,
                "niriWindowId": niriWindow.id,
                "niriWorkspaceId": niriWindow.workspace_id,
                "activate": function () {
                    return NiriService.focusWindow(niriWindow.id);
                },
                "close": function () {
                    if (bestMatch.close)
                        return bestMatch.close();
                    return false;
                }
            };

            for (let prop in bestMatch) {
                if (!(prop in enrichedToplevel))
                    enrichedToplevel[prop] = bestMatch[prop];
            }

            result.push(enrichedToplevel);
        }

        return result;
    }

    function filterCurrentWorkspace(toplevels, screenName) {
        let currentWorkspaceId = null;

        for (var i = 0; i < allWorkspaces.length; i++) {
            const ws = allWorkspaces[i];
            if (ws.output === screenName && ws.is_active) {
                currentWorkspaceId = ws.id;
                break;
            }
        }

        if (currentWorkspaceId === null)
            return toplevels;

        if (toplevels.length > 0 && toplevels[0].niriWorkspaceId !== undefined)
            return toplevels.filter(t => t.niriWorkspaceId === currentWorkspaceId);

        return _matchAndEnrichToplevels(toplevels, windows.filter(nw => nw.workspace_id === currentWorkspaceId));
    }

    function filterCurrentDisplay(toplevels, screenName) {
        if (!toplevels || toplevels.length === 0 || !screenName)
            return toplevels;

        const outputWorkspaceIds = new Set();
        for (var i = 0; i < allWorkspaces.length; i++) {
            const ws = allWorkspaces[i];
            if (ws.output === screenName)
                outputWorkspaceIds.add(ws.id);
        }

        if (outputWorkspaceIds.size === 0)
            return toplevels;

        if (toplevels.length > 0 && toplevels[0].niriWorkspaceId !== undefined)
            return toplevels.filter(t => outputWorkspaceIds.has(t.niriWorkspaceId));

        return _matchAndEnrichToplevels(toplevels, windows.filter(nw => outputWorkspaceIds.has(nw.workspace_id)));
    }

    function setLayoutXray(enabled) {
        layoutXrayEnabled = enabled;
        _layoutXrayLoaded = true;
        generateNiriLayoutConfig();
    }

    function setLayoutBarXray(enabled) {
        layoutBarXrayEnabled = enabled;
        _layoutXrayLoaded = true;
        generateNiriLayoutConfig();
    }

    function loadLayoutXrayState() {
        if (_layoutXrayLoading)
            return;
        _layoutXrayLoading = true;
        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        Proc.runCommand("niri-read-layout-xray", ["cat", configDir + "/niri/dms/layout.kdl"], (output, exitCode) => {
            _layoutXrayLoading = false;
            if (!_layoutXrayLoaded) {
                const content = exitCode === 0 ? output : "";
                layoutXrayEnabled = !content.includes("xray false");
                layoutBarXrayEnabled = !content.includes("// bar-xray off");
                _layoutXrayLoaded = true;
            }
            if (configGenerationPending)
                configGenerationAction.schedule();
        });
    }

    function generateNiriLayoutConfig(frameTransition) {
        if (!CompositorService.isNiri)
            return;
        _layoutRequestRevision++;
        if (frameTransition === true)
            _frameTransitionRevision = _layoutRequestRevision;
        suppressNextToast();
        configGenerationPending = true;
        configGenerationAction.schedule();
    }

    // niri's own defaults stay untouched until the user moves the shell-wide slider
    function niriBlurBlock(strength) {
        if (!(strength > 0))
            return "";
        const blur = BlurStrength.niriBlur(strength);
        return `

blur {
    passes ${blur.passes}
    offset ${blur.offset}
}`;
    }

    function niriColor(color) {
        return Qt.rgba(color.r, color.g, color.b, 1).toString();
    }

    function niriOverviewBlock() {
        if (!SettingsData.niriOverviewBackgroundEnabled)
            return "";
        const color = niriColor(Theme.surfaceContainerHighest);
        return `

overview {
    backdrop-color "${color}"
}`;
    }

    function doGenerateNiriLayoutConfig() {
        if (writeConfigProcess.running || _awaitingLayoutReloadRevision > _layoutAppliedRevision)
            return;
        if (!_layoutXrayLoaded) {
            loadLayoutXrayState();
            return;
        }
        configGenerationPending = false;
        log.debug("Generating layout config...");

        const defaultGaps = typeof SettingsData !== "undefined" ? Math.max(4, (SettingsData.getPrimaryBarConfig()?.spacing ?? 4)) : 4;
        const defaultBorderSize = 2;

        const cornerRadius = Theme.windowRadius;
        const gapsOverride = typeof SettingsData !== "undefined" ? SettingsData.niriLayoutGapsOverride : -1;
        const manageGaps = gapsOverride !== -2;
        const gaps = gapsOverride >= 0 ? gapsOverride : defaultGaps;
        const borderSize = (typeof SettingsData !== "undefined" && SettingsData.niriLayoutBorderSize >= 0) ? SettingsData.niriLayoutBorderSize : defaultBorderSize;
        const frameEnabled = typeof SettingsData !== "undefined" && SettingsData.frameEnabled;
        // dms:frame only in separate mode — connected-mode frame blur overlaps windows via popouts/arcs
        const excludeNamespaces = ["dms:bar"];
        if (typeof SettingsData !== "undefined" && SettingsData.dankIslandEnabled)
            excludeNamespaces.push("dms:dankisland");
        if (frameEnabled && SettingsData.frameMode !== "connected")
            excludeNamespaces.push("dms:frame");

        let xrayRules = "";
        if (!layoutXrayEnabled) {
            const excludeLines = layoutBarXrayEnabled ? excludeNamespaces.map(ns => `\n    exclude namespace="^${ns}$"`).join("") : "";
            xrayRules += `

layer-rule {${excludeLines}
    background-effect {
        xray false
    }
}

window-rule {
    match app-id="^(dev.duxlabs.shell|com.danklinux.dms)$"
    background-effect {
        xray false
    }
}`;
        }
        // Marker persists the preference even while the rule has no target
        if (!layoutBarXrayEnabled)
            xrayRules += `

// bar-xray off`;

        const dmsWarning = `// ! DO NOT EDIT !
// ! AUTO-GENERATED BY DMS !
// ! CHANGES WILL BE OVERWRITTEN !
// ! PLACE YOUR CUSTOM CONFIGURATION ELSEWHERE !

`;

        const layoutLines = [];
        if (manageGaps)
            layoutLines.push(`    gaps ${gaps}`, "");
        const activeColorLines = root.activeWindowColor ? [`        active-color "${root.activeWindowColor}"`] : [];
        layoutLines.push("    border {", `        width ${borderSize}`, ...activeColorLines, "    }", "", "    focus-ring {", `        width ${borderSize}`, ...activeColorLines, "    }");

        const configContent = dmsWarning + `layout {
${layoutLines.join("\n")}
}

window-rule {
    geometry-corner-radius ${cornerRadius}
    clip-to-geometry true
    tiled-state true
    draw-border-with-background false
}` + niriBlurBlock(typeof SettingsData !== "undefined" ? SettingsData.blurStrength : 0) + xrayRules + root.overviewBackdropConfig;

        const alttabContent = dmsWarning + `recent-windows {
    highlight {
        corner-radius ${cornerRadius}
    }
}`;

        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const niriDmsDir = configDir + "/niri/dms";
        const configPath = niriDmsDir + "/layout.kdl";
        const alttabPath = niriDmsDir + "/alttab.kdl";

        writeConfigProcess.configContent = configContent;
        writeConfigProcess.configPath = configPath;
        writeConfigProcess.requestRevision = _layoutRequestRevision;
        writeConfigProcess.command = ["sh", "-c", replaceFileCommand(configPath, configContent)];
        _awaitingLayoutReloadRevision = Math.max(_awaitingLayoutReloadRevision, _layoutRequestRevision);
        writeConfigProcess.running = true;

        if (_lastGeneratedAlttabContent !== alttabContent) {
            _lastGeneratedAlttabContent = alttabContent;
            writeAlttabProcess.alttabContent = alttabContent;
            writeAlttabProcess.alttabPath = alttabPath;
            writeAlttabProcess.command = ["sh", "-c", replaceFileCommand(alttabPath, alttabContent)];
            writeAlttabProcess.running = true;
        }

        ensureDmsConfigFiles(niriDmsDir);
    }

    property bool _dmsConfigFilesEnsured: false

    function ensureDmsConfigFiles(niriDmsDir) {
        if (_dmsConfigFilesEnsured)
            return;
        _dmsConfigFilesEnsured = true;
        const script = `mkdir -p "${niriDmsDir}" && for f in outputs binds cursor windowrules colors alttab layout input; do [ -f "${niriDmsDir}/$f.kdl" ] || touch "${niriDmsDir}/$f.kdl"; done`;
        Proc.runCommand("niri-ensure-dms-configs", ["sh", "-c", script], (output, exitCode) => {
            if (exitCode !== 0)
                log.warn("Failed to ensure dms config files, exit code:", exitCode);
        });
    }

    function generateNiriBlurrule() {
        log.debug("Generating wpblur config...");

        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const niriDmsDir = configDir + "/niri/dms";
        const blurrulePath = niriDmsDir + "/wpblur.kdl";
        const sourceBlurrulePath = Paths.strip(Qt.resolvedUrl("niri-wpblur.kdl"));

        writeBlurruleProcess.blurrulePath = blurrulePath;
        writeBlurruleProcess.command = ["sh", "-c", `${targetFileCommand(blurrulePath)} && cp --no-preserve=mode "${sourceBlurrulePath}" "$target.$$.tmp" && mv -f "$target.$$.tmp" "$target"`];
        writeBlurruleProcess.running = true;
    }

    function generateNiriCursorConfig() {
        if (!CompositorService.isNiri)
            return;

        log.debug("Generating cursor config...");

        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const niriDmsDir = configDir + "/niri/dms";
        const cursorPath = niriDmsDir + "/cursor.kdl";

        const settings = typeof SettingsData !== "undefined" ? SettingsData.cursorSettings : null;
        if (!settings) {
            writeCursorProcess.cursorContent = "";
            writeCursorProcess.cursorPath = cursorPath;
            writeCursorProcess.command = ["sh", "-c", `mkdir -p "${niriDmsDir}" && : > "${cursorPath}"`];
            writeCursorProcess.running = true;
            return;
        }

        const themeName = settings.theme === "System Default" ? (SettingsData.systemDefaultCursorTheme || "") : settings.theme;
        const size = settings.size || 24;
        const hideWhenTyping = settings.niri?.hideWhenTyping || false;
        const hideAfterMs = settings.niri?.hideAfterInactiveMs || 0;

        const isDefaultConfig = !themeName && size === 24 && !hideWhenTyping && hideAfterMs === 0;
        if (isDefaultConfig) {
            writeCursorProcess.cursorContent = "";
            writeCursorProcess.cursorPath = cursorPath;
            writeCursorProcess.command = ["sh", "-c", `mkdir -p "${niriDmsDir}" && : > "${cursorPath}"`];
            writeCursorProcess.running = true;
            return;
        }

        const dmsWarning = `// ! DO NOT EDIT !
// ! AUTO-GENERATED BY DMS !
// ! CHANGES WILL BE OVERWRITTEN !
// ! PLACE YOUR CUSTOM CONFIGURATION ELSEWHERE !

`;

        let cursorContent = dmsWarning + `cursor {\n`;

        if (themeName)
            cursorContent += `    xcursor-theme "${themeName}"\n`;

        cursorContent += `    xcursor-size ${size}\n`;

        if (hideWhenTyping)
            cursorContent += `    hide-when-typing\n`;

        if (hideAfterMs > 0)
            cursorContent += `    hide-after-inactive-ms ${hideAfterMs}\n`;

        cursorContent += `}`;

        writeCursorProcess.cursorContent = cursorContent;
        writeCursorProcess.cursorPath = cursorPath;

        writeCursorProcess.command = ["sh", "-c", replaceFileCommand(cursorPath, cursorContent)];
        writeCursorProcess.running = true;
    }

    function targetFileCommand(path) {
        return `mkdir -p "$(dirname "${path}")" && target="$(readlink -f "${path}")"`;
    }

    function replaceFileCommand(path, content) {
        const body = content.endsWith("\n") ? content : content + "\n";
        return `${targetFileCommand(path)} && cat > "$target.$$.tmp" << 'EOF' && mv -f "$target.$$.tmp" "$target"\n${body}EOF`;
    }

    function applyOutputConfig(outputName, config, callback) {
        if (!CompositorService.isNiri || !outputName) {
            if (callback)
                callback(false, "Invalid config");
            return;
        }

        const commands = [];

        if (config.disabled !== undefined) {
            commands.push(`niri msg output "${outputName}" ${config.disabled ? "off" : "on"}`);
            if (config.disabled) {
                const fullDisableCommand = "{ " + commands.join(" && ") + "; } 2>&1";
                Proc.runCommand("niri-output-config-" + outputName, ["sh", "-c", fullDisableCommand], (output, exitCode) => {
                    if (exitCode !== 0) {
                        log.warn("Failed to apply output config:", outputName, "exit:", exitCode, output);
                        if (callback)
                            callback(false, output);
                        return;
                    }
                    fetchOutputs();
                    if (callback)
                        callback(true, "Success");
                });
                return;
            }
        }

        if (config.position !== undefined) {
            commands.push(`niri msg output "${outputName}" position set ${config.position.x} ${config.position.y}`);
        }

        if (config.mode !== undefined) {
            commands.push(`niri msg output "${outputName}" mode ${config.mode}`);
        }

        if (config.vrrOnDemand !== undefined) {
            commands.push(`niri msg output "${outputName}" vrr --on-demand ${config.vrrOnDemand ? "on" : "off"}`);
        } else if (config.vrr !== undefined) {
            commands.push(`niri msg output "${outputName}" vrr ${config.vrr ? "on" : "off"}`);
        }

        if (config.scale !== undefined) {
            commands.push(`niri msg output "${outputName}" scale ${config.scale}`);
        }

        if (config.transform !== undefined) {
            commands.push(`niri msg output "${outputName}" transform "${config.transform}"`);
        }

        if (commands.length === 0) {
            if (callback)
                callback(true, "No changes");
            return;
        }

        const fullCommand = "{ " + commands.join(" && ") + "; } 2>&1";
        Proc.runCommand("niri-output-config-" + outputName, ["sh", "-c", fullCommand], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to apply output config:", outputName, "exit:", exitCode, output);
                if (callback)
                    callback(false, output);
                return;
            }
            log.info("Applied output config for", outputName);
            fetchOutputs();
            if (callback)
                callback(true, "Success");
        });
    }

    function getOutputIdentifier(output, outputName) {
        if (output.explicitIdentifier)
            return outputName;
        return OutputModel.niriIdentifier(output, outputName, SettingsData.displayNameMode);
    }

    function outputSettingsFor(output, outputName, niriSettings) {
        const identifier = getOutputIdentifier(output, outputName);
        if (niriSettings)
            return niriSettings[identifier] || niriSettings[outputName] || {};
        return SessionData.getNiriOutputSettings(identifier);
    }

    function buildOutputsConfig(outputsData, niriSettings) {
        const data = outputsData || outputs;
        if (!data || Object.keys(data).length === 0)
            return "";

        let kdlContent = `// Auto-generated by DMS - do not edit manually\n\n`;

        const sortedNames = Object.keys(data).sort((a, b) => {
            const la = data[a].logical || {};
            const lb = data[b].logical || {};
            return (la.x ?? 0) - (lb.x ?? 0) || (la.y ?? 0) - (lb.y ?? 0);
        });
        for (const outputName of sortedNames) {
            const output = data[outputName];
            const identifier = getOutputIdentifier(output, outputName);
            const outputSettings = outputSettingsFor(output, outputName, niriSettings);

            kdlContent += `output "${identifier}" {\n`;

            if (outputSettings.disabled) {
                kdlContent += `    off\n`;
            }

            if (output.configured_mode) {
                kdlContent += `    mode "${output.configured_mode}"\n`;
            } else if (output.current_mode !== undefined && output.modes && output.modes[output.current_mode]) {
                const mode = output.modes[output.current_mode];
                kdlContent += `    mode "${mode.width}x${mode.height}@${(mode.refresh_rate / 1000).toFixed(3)}"\n`;
            }

            if (output.logical) {
                kdlContent += `    scale ${output.logical.scale || 1.0}\n`;

                if (output.logical.transform && output.logical.transform !== "Normal") {
                    kdlContent += `    transform "${OutputModel.niriTransform(output.logical.transform)}"\n`;
                }

                if (output.logical.x !== undefined && output.logical.y !== undefined) {
                    kdlContent += `    position x=${output.logical.x} y=${output.logical.y}\n`;
                }
            }

            if (output.vrr_enabled || outputSettings.vrrOnDemand) {
                const vrrOnDemand = outputSettings.vrrOnDemand ?? false;
                kdlContent += vrrOnDemand ? `    variable-refresh-rate on-demand=true\n` : `    variable-refresh-rate\n`;
            }

            if (outputSettings.focusAtStartup) {
                kdlContent += `    focus-at-startup\n`;
            }

            if (outputSettings.backdropColor) {
                kdlContent += `    backdrop-color "${outputSettings.backdropColor}"\n`;
            }

            kdlContent += generateHotCornersBlock(outputSettings);
            kdlContent += generateLayoutBlock(outputSettings);

            kdlContent += `}\n\n`;
        }

        return kdlContent;
    }

    function generateOutputsConfig(outputsData, settingsOrCallback, maybeCallback) {
        const niriSettings = typeof settingsOrCallback === "function" ? null : settingsOrCallback;
        const callback = typeof settingsOrCallback === "function" ? settingsOrCallback : maybeCallback;
        const kdlContent = buildOutputsConfig(outputsData, niriSettings);
        if (!kdlContent) {
            if (callback)
                callback(false);
            return;
        }

        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const niriDmsDir = configDir + "/niri/dms";
        const outputsPath = niriDmsDir + "/outputs.kdl";

        Proc.runCommand("niri-write-outputs", ["sh", "-c", replaceFileCommand(outputsPath, kdlContent)], (output, exitCode) => {
            if (exitCode !== 0) {
                log.warn("Failed to write outputs config:", output);
                if (callback)
                    callback(false, output);
                return;
            }
            log.info("Generated outputs config at", outputsPath);
            if (callback)
                callback(true, "");
        });
    }

    function generateHotCornersBlock(niriSettings) {
        if (!niriSettings.hotCorners)
            return "";
        const hc = niriSettings.hotCorners;
        if (hc.off)
            return `    hot-corners {\n        off\n    }\n`;
        const corners = hc.corners || [];
        if (corners.length === 0)
            return "";
        let block = `    hot-corners {\n`;
        for (const corner of corners) {
            block += `        ${corner}\n`;
        }
        block += `    }\n`;
        return block;
    }

    function generateLayoutBlock(niriSettings) {
        if (!niriSettings.layout)
            return "";
        const layout = niriSettings.layout;
        const hasSettings = layout.gaps !== undefined || layout.defaultColumnWidth || layout.presetColumnWidths || layout.alwaysCenterSingleColumn !== undefined;
        if (!hasSettings)
            return "";
        let block = `    layout {\n`;
        if (layout.gaps !== undefined)
            block += `        gaps ${layout.gaps}\n`;
        if (layout.defaultColumnWidth?.type === "proportion") {
            const val = layout.defaultColumnWidth.value;
            const formatted = Number.isInteger(val) ? val.toFixed(1) : val.toString();
            block += `        default-column-width { proportion ${formatted}; }\n`;
        }
        if (layout.presetColumnWidths && layout.presetColumnWidths.length > 0) {
            block += `        preset-column-widths {\n`;
            for (const preset of layout.presetColumnWidths) {
                if (preset.type === "proportion") {
                    const val = preset.value;
                    const formatted = Number.isInteger(val) ? val.toFixed(1) : val.toString();
                    block += `            proportion ${formatted}\n`;
                }
            }
            block += `        }\n`;
        }
        if (layout.alwaysCenterSingleColumn !== undefined)
            block += layout.alwaysCenterSingleColumn ? `        always-center-single-column\n` : `        always-center-single-column false\n`;
        block += `    }\n`;
        return block;
    }

    function renameWorkspace(name) {
        if (!name || name.trim() === "") {
            return send({
                "Action": {
                    "UnsetWorkspaceName": {
                        "workspace": null
                    }
                }
            });
        }
        return send({
            "Action": {
                "SetWorkspaceName": {
                    "name": name,
                    "workspace": null
                }
            }
        });
    }

    function moveWorkspaceToIndex(workspaceId, targetIndex) {
        return send({
            "Action": {
                "MoveWorkspaceToIndex": {
                    "index": targetIndex,
                    "reference": {
                        "Id": workspaceId
                    }
                }
            }
        });
    }

    function generateNiriInputConfig() {
        if (!CompositorService.isNiri)
            return;

        const defaultMouseLeftHanded = false;
        const defaultMouseMiddleEmulation = false;
        const defaultMouseNaturalScroll = false;
        const defaultMouseProfile = "default";
        const defaultMouseScrollFactor = 1.0;
        const defaultMouseScrollMethod = "default";
        const defaultMouseSpeed = 0.0;

        const defaultTouchpadClickMethod = "default";
        const defaultTouchpadDisableOnExternalMouse = false;
        const defaultTouchpadDisableWhileTyping = true;
        const defaultTouchpadDragLock = false;
        const defaultTouchpadMiddleEmulation = false;
        const defaultTouchpadNaturalScroll = true;
        const defaultTouchpadProfile = "default";
        const defaultTouchpadScrollFactor = 1.0;
        const defaultTouchpadScrollMethod = "default";
        const defaultTouchpadSpeed = 0.0;
        const defaultTouchpadTap = true;
        const defaultTouchpadTapAndDrag = true;

        const mouseLeftHanded = typeof SettingsData !== "undefined" ? SettingsData.mouseLeftHanded : defaultMouseLeftHanded;
        const mouseMiddleEmulation = typeof SettingsData !== "undefined" ? SettingsData.mouseMiddleEmulation : defaultMouseMiddleEmulation;
        const mouseNaturalScroll = typeof SettingsData !== "undefined" ? SettingsData.mouseNaturalScroll : defaultMouseNaturalScroll;
        const mouseProfile = typeof SettingsData !== "undefined" ? SettingsData.mouseAccelProfile : defaultMouseProfile;
        const mouseScrollFactor = typeof SettingsData !== "undefined" ? SettingsData.mouseScrollFactor : defaultMouseScrollFactor;
        const mouseScrollMethod = typeof SettingsData !== "undefined" ? SettingsData.mouseScrollMethod : defaultMouseScrollMethod;
        const mouseSpeed = typeof SettingsData !== "undefined" ? SettingsData.mouseAccelSpeed : defaultMouseSpeed;

        const touchpadClickMethod = typeof SettingsData !== "undefined" ? SettingsData.touchpadClickMethod : defaultTouchpadClickMethod;
        const touchpadDisableOnExternalMouse = typeof SettingsData !== "undefined" ? SettingsData.touchpadDisableOnExternalMouse : defaultTouchpadDisableOnExternalMouse;
        const touchpadDisableWhileTyping = typeof SettingsData !== "undefined" ? SettingsData.touchpadDisableWhileTyping : defaultTouchpadDisableWhileTyping;
        const touchpadDragLock = typeof SettingsData !== "undefined" ? SettingsData.touchpadDragLock : defaultTouchpadDragLock;
        const touchpadMiddleEmulation = typeof SettingsData !== "undefined" ? SettingsData.touchpadMiddleEmulation : defaultTouchpadMiddleEmulation;
        const touchpadNaturalScroll = typeof SettingsData !== "undefined" ? SettingsData.touchpadNaturalScroll : defaultTouchpadNaturalScroll;
        const touchpadProfile = typeof SettingsData !== "undefined" ? SettingsData.touchpadAccelProfile : defaultTouchpadProfile;
        const touchpadScrollFactor = typeof SettingsData !== "undefined" ? SettingsData.touchpadScrollFactor : defaultTouchpadScrollFactor;
        const touchpadScrollMethod = typeof SettingsData !== "undefined" ? SettingsData.touchpadScrollMethod : defaultTouchpadScrollMethod;
        const touchpadSpeed = typeof SettingsData !== "undefined" ? SettingsData.touchpadAccelSpeed : defaultTouchpadSpeed;
        const touchpadTap = typeof SettingsData !== "undefined" ? SettingsData.touchpadTapToClick : defaultTouchpadTap;
        const touchpadTapAndDrag = typeof SettingsData !== "undefined" ? SettingsData.touchpadTapAndDrag : defaultTouchpadTapAndDrag;

        const keyboardLayouts = typeof SettingsData !== "undefined" ? SettingsData.keyboardLayouts : "";
        const keyboardVariants = typeof SettingsData !== "undefined" ? SettingsData.keyboardVariants : "";
        const keyboardModel = typeof SettingsData !== "undefined" ? SettingsData.keyboardModel : "";
        const keyboardOptions = typeof SettingsData !== "undefined" ? SettingsData.keyboardOptions : "";
        const keyboardKeymapFile = typeof SettingsData !== "undefined" ? SettingsData.keyboardKeymapFile : "";
        const keyboardTrackLayout = typeof SettingsData !== "undefined" ? SettingsData.keyboardTrackLayout : "";
        const keyboardRepeatDelay = typeof SettingsData !== "undefined" ? SettingsData.keyboardRepeatDelay : 0;
        const keyboardRepeatRate = typeof SettingsData !== "undefined" ? SettingsData.keyboardRepeatRate : 0;
        const keyboardNumlock = typeof SettingsData !== "undefined" ? SettingsData.keyboardNumlock : false;

        const dmsWarning = `// ! DO NOT EDIT !
// ! AUTO-GENERATED BY DMS !
// ! CHANGES WILL BE OVERWRITTEN !
// ! PLACE YOUR CUSTOM CONFIGURATION ELSEWHERE !

`;

        let inputContent = dmsWarning + "input {\n";
        // Niri flags take no false, so off can only leave it out
        if (typeof SettingsData !== "undefined" && SettingsData.focusFollowsMouse === 1) {
            inputContent += "    focus-follows-mouse max-scroll-amount=\"0%\"\n";
        }

        // Mouse block
        inputContent += "    mouse {\n";
        inputContent += `        accel-speed ${mouseSpeed.toFixed(1)}\n`;
        if (mouseProfile !== "default") {
            inputContent += `        accel-profile "${mouseProfile}"\n`;
        }
        if (mouseNaturalScroll) {
            inputContent += "        natural-scroll\n";
        }
        if (mouseLeftHanded) {
            inputContent += "        left-handed\n";
        }
        if (mouseMiddleEmulation) {
            inputContent += "        middle-emulation\n";
        }
        if (mouseScrollFactor !== 1.0) {
            inputContent += `        scroll-factor ${mouseScrollFactor.toFixed(1)}\n`;
        }
        if (mouseScrollMethod !== "default") {
            inputContent += `        scroll-method "${mouseScrollMethod}"\n`;
        }
        inputContent += "    }\n";

        // Touchpad block
        inputContent += "    touchpad {\n";
        if (touchpadTap) {
            inputContent += "        tap\n";
        }
        inputContent += `        accel-speed ${touchpadSpeed.toFixed(1)}\n`;
        if (touchpadProfile !== "default") {
            inputContent += `        accel-profile "${touchpadProfile}"\n`;
        }
        if (touchpadClickMethod !== "default") {
            inputContent += `        click-method "${touchpadClickMethod}"\n`;
        }
        if (touchpadNaturalScroll) {
            inputContent += "        natural-scroll\n";
        }
        if (touchpadDisableOnExternalMouse) {
            inputContent += "        disabled-on-external-mouse\n";
        }
        if (touchpadDisableWhileTyping) {
            inputContent += "        dwt\n";
        }
        if (touchpadMiddleEmulation) {
            inputContent += "        middle-emulation\n";
        }
        if (touchpadScrollFactor !== 1.0) {
            inputContent += `        scroll-factor ${touchpadScrollFactor.toFixed(1)}\n`;
        }
        if (touchpadScrollMethod !== "default") {
            inputContent += `        scroll-method "${touchpadScrollMethod}"\n`;
        }
        if (!touchpadTapAndDrag) {
            inputContent += "        drag false\n";
        }
        if (touchpadDragLock) {
            inputContent += "        drag-lock\n";
        }
        inputContent += "    }\n";

        // Keyboard block — emitted only when configured so untouched settings keep
        // niri's locale1 fallback and any keyboard block in the user's own config.
        const kdlString = value => `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
        const keyboardConfigured = keyboardKeymapFile || keyboardLayouts || keyboardVariants || keyboardModel || keyboardOptions || keyboardTrackLayout || keyboardRepeatDelay > 0 || keyboardRepeatRate > 0 || keyboardNumlock;
        if (keyboardConfigured) {
            inputContent += "    keyboard {\n";
            if (keyboardKeymapFile) {
                inputContent += "        xkb {\n";
                inputContent += `            file ${kdlString(keyboardKeymapFile)}\n`;
                inputContent += "        }\n";
            } else if (keyboardLayouts || keyboardVariants || keyboardModel || keyboardOptions) {
                inputContent += "        xkb {\n";
                if (keyboardLayouts) {
                    inputContent += `            layout ${kdlString(keyboardLayouts)}\n`;
                }
                if (keyboardVariants) {
                    inputContent += `            variant ${kdlString(keyboardVariants)}\n`;
                }
                if (keyboardModel) {
                    inputContent += `            model ${kdlString(keyboardModel)}\n`;
                }
                if (keyboardOptions) {
                    inputContent += `            options ${kdlString(keyboardOptions)}\n`;
                }
                inputContent += "        }\n";
            }
            if (keyboardTrackLayout) {
                inputContent += `        track-layout "${keyboardTrackLayout}"\n`;
            }
            if (keyboardRepeatDelay > 0) {
                inputContent += `        repeat-delay ${keyboardRepeatDelay}\n`;
            }
            if (keyboardRepeatRate > 0) {
                inputContent += `        repeat-rate ${keyboardRepeatRate}\n`;
            }
            if (keyboardNumlock) {
                inputContent += "        numlock\n";
            }
            inputContent += "    }\n";
        }

        inputContent += "}\n";

        const configDir = Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
        const niriDmsDir = configDir + "/niri/dms";
        const inputPath = niriDmsDir + "/input.kdl";

        writeInputProcess.inputContent = inputContent;
        writeInputProcess.inputPath = inputPath;
        writeInputProcess.command = ["sh", "-c", replaceFileCommand(inputPath, inputContent)];
        writeInputProcess.running = true;
    }

    function hasNamedWorkspaces() {
        if (!CompositorService.isNiri)
            return false;

        for (var i = 0; i < allWorkspaces.length; i++) {
            var ws = allWorkspaces[i];
            if (ws.name && ws.name.trim() !== "")
                return true;
        }
        return false;
    }

    function getNamedWorkspaces() {
        var namedWorkspaces = [];
        if (!CompositorService.isNiri)
            return namedWorkspaces;

        for (const ws of allWorkspaces) {
            if (ws.name && ws.name.trim() !== "") {
                namedWorkspaces.push(ws.name);
            }
        }
        return namedWorkspaces;
    }

    IpcHandler {
        function screenshot(): string {
            if (!CompositorService.isNiri) {
                return "NIRI_NOT_AVAILABLE";
            }
            if (NiriService.screenshot()) {
                return "SCREENSHOT_SUCCESS";
            }
            return "SCREENSHOT_FAILED";
        }

        function screenshotScreen(): string {
            if (!CompositorService.isNiri) {
                return "NIRI_NOT_AVAILABLE";
            }
            if (NiriService.screenshotScreen()) {
                return "SCREENSHOT_SCREEN_SUCCESS";
            }
            return "SCREENSHOT_SCREEN_FAILED";
        }

        function screenshotWindow(): string {
            if (!CompositorService.isNiri) {
                return "NIRI_NOT_AVAILABLE";
            }
            if (NiriService.screenshotWindow()) {
                return "SCREENSHOT_WINDOW_SUCCESS";
            }
            return "SCREENSHOT_WINDOW_FAILED";
        }

        target: "niri"
    }
}
