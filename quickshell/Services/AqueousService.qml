pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Common as DCommon
import "../Common/AqueousIpc.js" as Ipc

Singleton {
    id: root
    readonly property var log: Log.scoped("AqueousService")
    property var state: ({})
    property string seatName: ""
    readonly property bool enabled: CompositorService.isAqueous
    readonly property bool available: enabled && requestConnection.ready && eventConnection.ready && state.available === true
    property var discoveredCapabilities: ({})
    property var pendingProcesses: []
    property int lifecycle: 0
    readonly property string socketPath: Quickshell.env("AQUEOUS_SOCKET")
    readonly property string runtimePath: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property bool validSocketPath: Ipc.socketPath(socketPath, runtimePath)
    property bool watching: false
    property bool recovering: false
    property bool reconnecting: false
    property int reconnectAttempt: 0
    property var commandQueue: []
    property var currentCommand: null
    readonly property bool commandPending: currentCommand !== null
    readonly property int maxBatchBytes: 4 * 1024 * 1024
    readonly property int maxModelBytes: 2 * 1024 * 1024
    readonly property var capabilities: discoveredCapabilities
    readonly property string session: available ? state.batch.session : ""
    readonly property string sequence: available ? state.batch.sequence : ""
    readonly property var entities: available ? state.batch.upsert : []
    readonly property var outputs: entities.filter(e => e.kind === "output")
    readonly property var workspaces: entities.filter(e => e.kind === "workspace").map(w => Object.assign({}, w, {
            aqueousSession: session
        }))
    readonly property var windows: entities.filter(e => e.kind === "window")
    readonly property var seats: entities.filter(e => e.kind === "seat")
    readonly property var sessionState: entities.find(e => e.kind === "session") || ({})
    readonly property bool locked: sessionState.locked === true
    readonly property var seat: seatName ? seats.find(s => s.id === seatName) : (seats.length === 1 ? seats[0] : null)
    readonly property var keyboard: entities.find(e => e.kind === "keyboard" && e.id === seat?.keyboard)
    readonly property var keyboardLayouts: keyboard?.layouts || []
    readonly property string keyboardLayout: keyboardLayouts[keyboard?.index] || ""
    readonly property string focusedOutput: outputs.find(o => o.id === seat?.output)?.name || ""
    readonly property bool inOverview: !!sessionState.overview_output
    readonly property var focusedWindow: {
        const window = windows.find(w => w.id === seat?.window);
        return window ? windowFacade(window) : null;
    }
    readonly property var toplevels: windows.filter(w => taskbarEligible(w)).map(w => windowFacade(w))

    function taskbarEligible(window) {
        return !window.skip_taskbar && (window.visible || window.minimized || !workspaces.find(ws => ws.id === window.workspace)?.active);
    }

    function outputId(name) {
        return outputs.find(o => o.name === name)?.id || "";
    }

    function workspacesForOutput(name) {
        const id = outputId(name || focusedOutput);
        return workspaces.filter(w => w.output === id).sort((a, b) => a.number - b.number);
    }

    function parseJson(text) {
        if (Ipc.byteLength(text) > maxBatchBytes + (text.endsWith("\n") ? 1 : 0))
            throw new Error("JSON exceeds 4 MiB");
        return JSON.parse(text);
    }

    function validateEntity(entity) {
        const fields = {
            output: "id:s name:s bounds:r usable_bounds:r scale:n transform:s active_workspace:? enabled:b powered:b",
            workspace: "id:s output:s name:s number:i active:b urgent:b",
            window: "id:s backend:s app_id:? class:? title:? workspace:? output:? geometry:r outer_geometry:r layout:s focused:b visible:b floating:b minimized:b maximized:b fullscreen:b skip_taskbar:b skip_switcher:b always_above:b always_below:b snapped:b fixed_position:b can_minimize:b can_maximize:b can_activate:b",
            seat: "id:s output:? window:? focus_kind:s keyboard:?",
            keyboard: "id:s seat:s layouts:a index:i",
            keyboard_device: "id:s name:? seat:s group:? virtual:b",
            session: "id:s locked:b default_seat:? overview_output:? overview_window:?"
        };
        if (!entity || !Object.prototype.hasOwnProperty.call(fields, entity.kind) || typeof entity.id !== "string" || !entity.id)
            throw new Error("invalid entity kind or ID");
        for (const field of fields[entity.kind].split(" ")) {
            const [name, type] = field.split(":");
            const value = entity[name];
            let valid = false;
            switch (type) {
            case "s":
                valid = typeof value === "string";
                break;
            case "?":
                valid = value === null || typeof value === "string";
                break;
            case "b":
                valid = typeof value === "boolean";
                break;
            case "i":
                valid = Number.isSafeInteger(value);
                break;
            case "n":
                valid = typeof value === "number" && Number.isFinite(value);
                break;
            case "a":
                valid = value instanceof Array && value.every(v => typeof v === "string");
                break;
            case "r":
                valid = value && ["x", "y", "width", "height"].every(k => Number.isSafeInteger(value[k]));
                break;
            }
            if (!valid)
                throw new Error("invalid " + entity.kind + "." + name);
        }
        if ((entity.kind === "session" && entity.id !== "session") || (entity.kind === "workspace" && entity.number < 1) || (entity.kind === "output" && entity.scale <= 0) || (entity.kind === "keyboard" && (entity.index < 0 || (entity.layouts.length && entity.index >= entity.layouts.length))) || (entity.kind === "window" && !["xdg", "xwayland"].includes(entity.backend)) || (entity.kind === "seat" && !["window", "shell_surface", "layer_surface", "override_redirect", "lock_surface", "none"].includes(entity.focus_kind)))
            throw new Error("invalid " + entity.kind);
    }

    function reduceBatch(previous, batch) {
        if (!batch || batch.schema !== 1 || typeof batch.session !== "string" || !/^[0-9a-f]{32}$/.test(batch.session) || typeof batch.sequence !== "string" || !/^[0-9]+$/.test(batch.sequence) || !Array.isArray(batch.upsert) || !Array.isArray(batch.removed))
            throw new Error("invalid shell batch envelope");
        if (batch.type !== "snapshot" && batch.type !== "delta")
            throw new Error("invalid shell batch type");
        if (batch.type === "snapshot" && (batch.base_sequence !== null || batch.removed.length))
            throw new Error("invalid snapshot baseline");
        if (batch.type === "delta" && (!previous || batch.session !== previous.session || batch.base_sequence !== previous.sequence || batch.sequence === previous.sequence))
            throw new Error("shell delta continuity mismatch");
        const model = Object.assign({}, batch.type === "delta" ? previous.model : {});
        const entityBytes = Object.assign({}, batch.type === "delta" ? previous.entityBytes : {});
        let modelBytes = batch.type === "delta" ? previous.modelBytes : 1;
        const seen = new Set();
        for (const entity of batch.upsert) {
            validateEntity(entity);
            const key = entity.kind + ":" + entity.id;
            if (seen.has(key))
                throw new Error("duplicate entity key");
            seen.add(key);
            const size = Ipc.byteLength(JSON.stringify(key) + ":" + JSON.stringify(entity)) + 1;
            modelBytes += size - (entityBytes[key] || 0);
            entityBytes[key] = size;
            model[key] = entity;
        }
        for (const key of batch.removed) {
            if (typeof key !== "string" || !/^(output|workspace|window|seat|keyboard|keyboard_device|session):.+$/.test(key) || seen.has(key))
                throw new Error("invalid or duplicate removal");
            seen.add(key);
            modelBytes -= entityBytes[key] || 0;
            delete entityBytes[key];
            delete model[key];
        }
        if (!model["session:session"])
            throw new Error("missing session entity");
        const references = {
            output: {
                active_workspace: "workspace"
            },
            workspace: {
                output: "output"
            },
            window: {
                output: "output",
                workspace: "workspace"
            },
            seat: {
                output: "output",
                window: "window",
                keyboard: "keyboard"
            },
            keyboard: {
                seat: "seat"
            },
            keyboard_device: {
                seat: "seat",
                group: "keyboard"
            },
            session: {
                default_seat: "seat",
                overview_output: "output",
                overview_window: "window"
            }
        };
        for (const entity of Object.values(model)) {
            for (const [field, kind] of Object.entries(references[entity.kind])) {
                if (entity[field] !== null && !model[kind + ":" + entity[field]])
                    throw new Error("dangling " + entity.kind + "." + field);
            }
        }
        if (modelBytes > maxModelBytes)
            throw new Error("shell model exceeds size bound");
        return {
            session: batch.session,
            sequence: batch.sequence,
            model: model,
            entityBytes: entityBytes,
            modelBytes: modelBytes,
            upsert: Object.values(model)
        };
    }

    function acceptBatch(batch) {
        if (batch.session !== capabilities.session)
            throw new Error("shell session changed after discovery");
        const next = reduceBatch(state.available ? state.batch : null, batch);
        reconnectAttempt = 0;
        state = {
            available: true,
            batch: next
        };
    }

    function commandPayload(action, fields) {
        const request = Object.assign({
            session: session,
            seat: seat?.id || ""
        }, fields || {});
        if (!available || request.session !== session)
            throw new Error("unavailable: stale session");
        if (locked)
            throw new Error("locked");
        const [kind, operation] = action.split(".");
        const capability = kind === "keyboard" ? "keyboard" : kind === "overview" ? "overview" : "commands";
        if (!capabilities[capability])
            throw new Error("unsupported: " + capability);
        for (const key of ["id", "seat", "group", "output", "workspace", "name"]) {
            if (request[key] !== undefined && (typeof request[key] !== "string" || Ipc.byteLength(request[key]) > 1024))
                throw new Error("invalid: command string");
        }
        const target = entities.find(e => e.kind === kind && e.id === request.id);
        if ((kind === "window" || kind === "workspace") && !target)
            throw new Error("not_found");
        const selectedSeat = request.seat ? seats.find(s => s.id === request.seat) : (seats.length === 1 ? seats[0] : null);
        const output = outputs.find(o => o.id === request.output);
        let payload;
        switch (action) {
        case "window.activate":
        case "workspace.activate":
            if (!selectedSeat)
                throw new Error(request.seat ? "not_found: seat" : "ambiguous_seat");
            if (kind === "window" && !target.can_activate)
                throw new Error("unavailable: window activation");
            payload = {
                id: target.id,
                seat: selectedSeat.id
            };
            break;
        case "window.close":
            payload = {
                id: target.id
            };
            break;
        case "window.minimized":
        case "window.maximized":
        case "window.fullscreen":
            if (typeof request.value !== "boolean")
                throw new Error("invalid: missing state");
            if (operation !== "fullscreen" && !target["can_" + operation.slice(0, -1)])
                throw new Error("unavailable: window state");
            payload = {
                id: target.id,
                value: request.value
            };
            break;
        case "window.move":
            if (!!request.workspace === !!request.output)
                throw new Error("invalid: move destination");
            if (request.workspace && !workspaces.some(w => w.id === request.workspace))
                throw new Error("not_found: workspace");
            if (request.output && !output)
                throw new Error("not_found: output");
            payload = {
                id: target.id
            };
            payload[request.workspace ? "workspace" : "output"] = request.workspace || output.id;
            break;
        case "workspace.rename":
            if (typeof request.name !== "string" || /[\r\n]/.test(request.name))
                throw new Error("invalid: workspace name");
            payload = {
                id: target.id,
                name: request.name
            };
            break;
        case "keyboard.set":
        case "keyboard.next":
            {
                if (!selectedSeat)
                    throw new Error(request.seat ? "not_found: seat" : "ambiguous_seat");
                const group = entities.find(e => e.kind === "keyboard" && e.id === (request.group || selectedSeat.keyboard) && e.seat === selectedSeat.id);
                if (!group)
                    throw new Error("not_found: keyboard group");
                payload = {
                    seat: selectedSeat.id,
                    group: group.id
                };
                if (operation === "set") {
                    if (!Number.isInteger(request.index) || request.index < 0 || request.index >= group.layouts.length)
                        throw new Error("invalid: keyboard index");
                    payload.index = request.index;
                }
                break;
            }
        case "overview.show":
        case "overview.toggle":
        case "overview.hide":
            payload = {};
            if (operation !== "hide") {
                if (!output)
                    throw new Error("not_found: output");
                payload.output = output.id;
            }
            break;
        case "session.exit":
            payload = {};
            break;
        default:
            throw new Error("unsupported: action");
        }
        return {
            action: action,
            fields: payload
        };
    }

    function commandResult(action, result, error) {
        if (error)
            return error;
        const status = action === "window.close" || action === "session.exit" ? "accepted" : "applied";
        if (result?.status !== status || (status === "applied" || result.sequence !== undefined) && (typeof result.sequence !== "string" || !/^[0-9]{1,20}$/.test(result.sequence)))
            return result?.status || "missing command acknowledgement";
        return "";
    }

    function reportCommand(action, result, error, callback) {
        const failure = commandResult(action, result, error);
        if (failure) {
            log.warn("command failed:", action, failure);
            ToastService.showError(I18n.tr("Error"), errorMessage(failure), failure);
        }
        if (callback)
            callback(!failure, failure || result.status);
    }

    function errorMessage(error) {
        const code = String(error).replace(/^Error: /, "").split(":")[0];
        switch (code) {
        case "busy":
            return I18n.tr("Another Aqueous operation is in progress.", "Aqueous request rejected because another operation is running");
        case "locked":
        case "unavailable":
        case "not_found":
            return I18n.tr("Unavailable");
        case "unsupported":
            return I18n.tr("This operation is not supported by the installed Aqueous version.", "Aqueous compositor or configuration helper lacks a required capability");
        case "conflict":
        case "external_change":
        case "stale_session":
            return I18n.tr("Configuration changed. Refresh to continue.", "Aqueous configuration or compositor session changed while editing");
        case "uncertain":
        case "command completion uncertain":
            return I18n.tr("The result is unknown. Refresh before trying again.", "An Aqueous operation may have completed without a reply");
        default:
            return I18n.tr("The Aqueous operation failed.", "Fallback error for an Aqueous compositor or configuration request");
        }
    }

    function command(action, fields, callback) {
        try {
            commandPayload(action, fields);
            if (commandQueue.length >= 32)
                throw new Error("busy: command queue full");
        } catch (e) {
            reportCommand(action, null, String(e), callback);
            return;
        }
        commandQueue = commandQueue.concat([
            {
                action: action,
                fields: Object.assign({
                    session: session,
                    seat: seat?.id || ""
                }, fields || {}),
                callback: callback,
                generation: lifecycle,
                queuedAt: Date.now()
            }
        ]);
        drainCommands();
    }

    function drainCommands() {
        if (currentCommand || recovering)
            return;
        while (commandQueue.length) {
            const next = commandQueue[0];
            commandQueue = commandQueue.slice(1);
            try {
                if (next.generation !== lifecycle || Date.now() - next.queuedAt >= 5000)
                    throw new Error("unavailable: queued command expired before sending");
                const payload = commandPayload(next.action, next.fields);
                currentCommand = next;
                requestConnection.request("command", payload);
                return;
            } catch (e) {
                currentCommand = null;
                reportCommand(next.action, null, String(e), next.callback);
            }
        }
    }

    function completeCommand(result, error) {
        const current = currentCommand;
        currentCommand = null;
        if (!current || current.generation !== lifecycle)
            return;
        if (!error && commandResult(current.action, result, "")) {
            reportCommand(current.action, null, "command completion uncertain: invalid acknowledgement", current.callback);
            disconnected("invalid command acknowledgement");
            return;
        }
        reportCommand(current.action, result, error, current.callback);
        if (error.startsWith("stale_session:")) {
            disconnected(error);
            return;
        }
        drainCommands();
    }

    function failCommands(error) {
        const current = currentCommand;
        const queued = commandQueue;
        currentCommand = null;
        commandQueue = [];
        if (current)
            reportCommand(current.action, null, "command completion uncertain: " + error, current.callback);
        for (const command of queued)
            reportCommand(command.action, null, "unavailable: command not sent: " + error, command.callback);
    }

    function runJson(args, input, callback) {
        if (!enabled) {
            callback(null, "unavailable");
            return;
        }
        if (input !== null && Ipc.byteLength(input) > maxBatchBytes) {
            callback(null, "request exceeds 4 MiB");
            return;
        }
        const process = jsonProcessComponent.createObject(root, {
            command: args,
            input: input,
            callback: callback
        });
        pendingProcesses = pendingProcesses.concat([process]);
        process.running = true;
        process.deadline.start();
    }

    function startWatching() {
        if (!enabled)
            return;
        if (!validSocketPath) {
            state = {
                error: "unavailable: missing or invalid AQUEOUS_SOCKET"
            };
            return;
        }
        state = {
            error: "unavailable: connecting to Aqueous IPC"
        };
        watching = true;
    }

    function handshakesReady() {
        if (!requestConnection.ready || !eventConnection.ready)
            return;
        const first = requestConnection.handshake;
        const second = eventConnection.handshake;
        if (first.session !== second.session || Object.keys(first.capabilities).some(key => first.capabilities[key] !== second.capabilities[key]) || first.schema !== second.schema) {
            disconnected("IPC connection sessions or capabilities disagree");
            return;
        }
        discoveredCapabilities = Object.assign({}, first.capabilities, {
            session: first.session,
            schema: first.schema,
            max_batch_bytes: Math.min(first.max_batch_bytes, second.max_batch_bytes)
        });
        try {
            eventConnection.subscribe();
        } catch (e) {
            disconnected(String(e));
        }
    }

    function disconnected(error) {
        if (recovering || !watching)
            return;
        recovering = true;
        lifecycle++;
        state = {
            error: error
        };
        discoveredCapabilities = ({});
        reconnecting = true;
        requestConnection.clear();
        eventConnection.clear();
        const delay = Math.min(400 * Math.pow(2, Math.min(reconnectAttempt++, 6)), 15000);
        reconnectTimer.interval = delay + Math.floor(Math.random() * delay / 4);
        reconnectTimer.restart();
        failCommands(error);
        recovering = false;
    }

    function stopWatching() {
        recovering = true;
        lifecycle++;
        watching = false;
        reconnectTimer.stop();
        reconnecting = false;
        reconnectAttempt = 0;
        requestConnection.clear();
        eventConnection.clear();
        state = ({});
        discoveredCapabilities = ({});
        failCommands("backend changed or shell stopped");
        for (const process of pendingProcesses.slice())
            process.finish(null, "unavailable: backend changed or shell stopped");
        recovering = false;
    }

    onEnabledChanged: {
        stopWatching();
        startWatching();
    }
    Component.onCompleted: startWatching()
    Component.onDestruction: stopWatching()

    IpcConnection {
        id: requestConnection
        path: root.socketPath
        connected: root.watching && !root.reconnecting
        onHelloReceived: root.handshakesReady()
        onReply: (result, error) => root.completeCommand(result, error)
        onFailed: error => root.disconnected(error)
    }

    IpcConnection {
        id: eventConnection
        path: root.socketPath
        connected: root.watching && !root.reconnecting
        events: true
        onHelloReceived: root.handshakesReady()
        onBatchReceived: batch => {
            try {
                root.acceptBatch(batch);
            } catch (e) {
                root.disconnected(String(e));
            }
        }
        onFailed: error => root.disconnected(error)
    }

    Timer {
        id: reconnectTimer
        onTriggered: root.reconnecting = false
    }

    component IpcConnection: DCommon.DSocket {
        id: connection
        property bool events: false
        property var handshake: null
        property var pending: null
        property string lastId: "0"
        property bool subscribed: false
        property bool installed: false
        property string lastDelivery: ""
        property var frameParser: null
        readonly property bool ready: linkUp && handshake !== null

        signal helloReceived
        signal batchReceived(var batch)
        signal reply(var result, string error)
        signal failed(string error)

        function clear() {
            const previousParser = frameParser;
            frameParser = null;
            if (previousParser)
                previousParser.destroy();
            deadline.stop();
            initialDeadline.stop();
            pending = null;
            handshake = null;
            subscribed = false;
            installed = false;
            lastId = "0";
            lastDelivery = "";
        }

        function fail(error) {
            if (connected && !root.recovering)
                failed(error);
        }

        function request(op, params) {
            if (!linkUp || pending || (op !== "hello" && !handshake))
                throw new Error("unavailable: IPC connection");
            const id = Ipc.nextId(lastId);
            const message = {
                ipc: 1,
                id: id,
                op: op,
                params: params
            };
            if (op !== "hello")
                message.session = handshake.session;
            const text = JSON.stringify(message);
            if (Ipc.byteLength(text) > (handshake?.max_request_bytes || 65536))
                throw new Error("invalid: IPC request exceeds size bound");
            lastId = id;
            pending = {
                id: id,
                op: op,
                params: params
            };
            deadline.restart();
            send(text);
        }

        function receive(line) {
            try {
                const value = Ipc.envelope(line, handshake?.max_frame_bytes || 4259840);
                if (value.event !== undefined) {
                    if (!events || !subscribed || pending || value.event !== "state" || !Ipc.decimal(value.delivery) || value.delivery === lastDelivery || value.id !== undefined || value.ok !== undefined || !Ipc.object(value.batch))
                        throw new Error("unexpected IPC state event");
                    if (!installed && value.batch.type !== "snapshot")
                        throw new Error("missing initial snapshot");
                    if (value.batch.session !== handshake.session || Ipc.byteLength(JSON.stringify(value.batch)) > handshake.max_batch_bytes)
                        throw new Error("invalid IPC batch identity or size");
                    batchReceived(value.batch);
                    if (!ready || root.recovering)
                        return;
                    installed = true;
                    initialDeadline.stop();
                    lastDelivery = value.delivery;
                    request("ack", {
                        delivery: value.delivery
                    });
                    return;
                }
                if (!pending)
                    throw new Error("unsolicited IPC response");
                const error = Ipc.response(value, pending.id);
                const operation = pending;
                pending = null;
                deadline.stop();
                if (operation.op === "command") {
                    reply(value.result || null, error);
                    return;
                }
                if (error)
                    throw new Error(error);
                switch (operation.op) {
                case "hello":
                    handshake = Ipc.hello(value.result);
                    helloReceived();
                    break;
                case "subscribe":
                    if (value.result.subscribed !== true)
                        throw new Error("invalid subscription response");
                    subscribed = true;
                    break;
                case "ack":
                    if (value.result.acked !== operation.params.delivery)
                        throw new Error("invalid ack response");
                    break;
                default:
                    throw new Error("unexpected IPC operation");
                }
            } catch (e) {
                fail(String(e));
            }
        }

        function subscribe() {
            initialDeadline.restart();
            request("subscribe", {});
        }

        onConnectionStateChanged: {
            clear();
            if (root.recovering)
                return;
            if (!linkUp) {
                fail("IPC stream disconnected");
                return;
            }
            frameParser = parserComponent.createObject(connection);
            try {
                request("hello", {});
            } catch (e) {
                fail(String(e));
            }
        }
        parser: frameParser

        Component {
            id: parserComponent
            SplitParser {
                id: lineParser
                onRead: line => {
                    if (connection.frameParser === lineParser)
                        connection.receive(line);
                }
            }
        }

        Timer {
            id: deadline
            interval: 5000
            onTriggered: connection.fail("IPC request timed out")
        }
        Timer {
            id: initialDeadline
            interval: 8000
            onTriggered: connection.fail("IPC initial snapshot timed out")
        }
    }

    function windowFacade(window) {
        const windowSession = session;
        const output = outputs.find(o => o.id === window.output);
        return {
            id: window.id,
            aqueousWindowId: window.id,
            aqueousKey: windowSession + ":window:" + window.id,
            aqueousSession: windowSession,
            aqueousWorkspaceId: window.workspace,
            aqueousOutputId: window.output,
            appId: window.app_id || window.class || "",
            title: window.title || "",
            activated: root.seat?.window === window.id,
            get fullscreen() {
                return window.fullscreen;
            },
            set fullscreen(value) {
                root.command("window.fullscreen", {
                    id: window.id,
                    session: windowSession,
                    value: value
                });
            },
            get maximized() {
                return window.maximized;
            },
            set maximized(value) {
                root.command("window.maximized", {
                    id: window.id,
                    session: windowSession,
                    value: value
                });
            },
            visible: window.visible,
            skipSwitcher: window.skip_switcher,
            canMinimize: window.can_minimize,
            canMaximize: window.can_maximize,
            canActivate: window.can_activate,
            screens: Quickshell.screens.filter(s => s.name === output?.name),
            get minimized() {
                return window.minimized;
            },
            set minimized(value) {
                root.command("window.minimized", {
                    id: window.id,
                    session: windowSession,
                    value: value
                });
            },
            activate: function () {
                root.command("window.activate", {
                    id: window.id,
                    session: windowSession
                });
            },
            close: function () {
                root.command("window.close", {
                    id: window.id,
                    session: windowSession
                });
            }
        };
    }

    function activateWorkspace(workspace) {
        if (!seat || !workspace)
            return;
        command("workspace.activate", {
            id: workspace.id,
            session: workspace.aqueousSession
        });
    }

    function cycleKeyboardLayout() {
        if (!seat || !keyboard || !capabilities.keyboard)
            return;
        command("keyboard.next", {
            group: keyboard.id
        });
    }

    function toggleOverview(screenName) {
        if (!capabilities.overview)
            return;
        command("overview.toggle", {
            output: outputId(screenName || focusedOutput)
        });
    }

    function quit() {
        command("session.exit");
    }

    function snapshot(path) {
        if (!available || path !== socketPath)
            return JSON.stringify({
                error: "unavailable"
            });
        return JSON.stringify({
            schema: 1,
            session: session,
            sequence: sequence,
            type: "snapshot",
            base_sequence: null,
            upsert: entities,
            removed: []
        });
    }

    IpcHandler {
        target: "aqueous"
        function snapshot(path: string): string {
            return root.snapshot(path);
        }
        function status(): string {
            return JSON.stringify({
                available: root.available,
                session: root.session,
                sequence: root.sequence,
                focusedOutput: root.focusedOutput,
                outputs: root.outputs.length,
                windows: root.windows.length,
                workspaces: root.workspaces.length,
                keyboardLayout: root.keyboardLayout,
                overviewOutput: root.sessionState.overview_output || null,
                overviewWindow: root.sessionState.overview_window || null,
                error: root.state.error || ""
            });
        }
        function overview(action: string, output: string): string {
            if (!["show", "hide", "toggle"].includes(action))
                return "INVALID_ACTION";
            if (!root.available || root.locked || !root.capabilities.overview)
                return "UNAVAILABLE";
            root.command("overview." + action, {
                output: root.outputId(output || root.focusedOutput)
            });
            return "OVERVIEW_REQUESTED";
        }
        function selectSeat(name: string): string {
            if (name && !root.seats.some(s => s.id === name))
                return "SEAT_NOT_FOUND";
            root.seatName = name;
            return "SEAT_SELECTED";
        }
    }

    function overlapsDock(screenName, position, thickness, width, height) {
        const output = outputs.find(o => o.name === screenName);
        if (!output)
            return false;
        return windows.some(w => {
            if (w.output !== output.id || !w.visible || w.minimized)
                return false;
            const box = w.outer_geometry;
            const x = box.x - output.bounds.x;
            const y = box.y - output.bounds.y;
            switch (position) {
            case SettingsData.Position.Top:
                return y < thickness && y + box.height > 0;
            case SettingsData.Position.Left:
                return x < thickness && x + box.width > 0;
            case SettingsData.Position.Right:
                return x < width && x + box.width > width - thickness;
            default:
                return y < height && y + box.height > height - thickness;
            }
        });
    }

    Component {
        id: jsonProcessComponent
        Process {
            id: jsonProcess
            property var input: null
            property var callback: null
            property bool finished: false
            property Timer deadline: Timer {
                id: jsonDeadline
                interval: 8000
                onTriggered: jsonProcess.finish(null, "command completion uncertain: timeout")
            }
            stdinEnabled: input !== null

            function finish(result, error) {
                if (finished)
                    return;
                finished = true;
                jsonDeadline.stop();
                if (running)
                    signal(9);
                root.pendingProcesses = root.pendingProcesses.filter(p => p !== jsonProcess);
                const complete = callback;
                callback = null;
                if (complete)
                    complete(result, error);
                Qt.callLater(() => jsonProcess.destroy());
            }

            onStarted: {
                if (input !== null) {
                    write(input);
                    stdinEnabled = false;
                }
            }
            stdout: StdioCollector {
                waitForEnd: false
                onDataChanged: {
                    if (data.byteLength > root.maxBatchBytes + 1)
                        jsonProcess.finish(null, "process output exceeds 4 MiB");
                }
            }
            stderr: SplitParser {
                splitMarker: ""
            }
            onExited: (code, status) => {
                if (finished)
                    return;
                let result = null;
                let error = "";
                try {
                    result = root.parseJson(stdout.text);
                    if (code !== 0 || status !== 0)
                        error = result?.code ? result.code + ": " + (result.message || "") : (result?.status || "command failed (" + code + ")");
                } catch (e) {
                    error = String(e);
                }
                finish(result, error);
            }
            onRunningChanged: {
                if (!running)
                    Qt.callLater(() => {
                        if (!jsonProcess.finished)
                            jsonProcess.finish(null, "command could not start");
                    });
            }
        }
    }
}
