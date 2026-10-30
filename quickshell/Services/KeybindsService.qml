pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/ConfigIncludeResolve.js" as ConfigIncludeResolve
import "../Common/KeybindActions.js" as Actions

Singleton {
    id: root
    readonly property var log: Log.scoped("KeybindsService")

    property bool available: CompositorService.isAqueous || CompositorService.isNiri || CompositorService.isHyprland || CompositorService.isMango
    property string currentProvider: {
        if (CompositorService.isAqueous)
            return "aqueous";
        if (CompositorService.isNiri)
            return "niri";
        if (CompositorService.isHyprland)
            return "hyprland";
        if (CompositorService.isMango)
            return "mangowc";
        return "";
    }

    readonly property string cheatsheetProvider: {
        if (CompositorService.isAqueous)
            return "aqueous";
        if (CompositorService.isNiri)
            return "niri";
        if (CompositorService.isHyprland)
            return "hyprland";
        if (CompositorService.isMango)
            return "mangowc";
        return "";
    }
    property bool cheatsheetAvailable: cheatsheetProvider !== ""
    property bool cheatsheetLoading: false
    property var cheatsheet: ({})

    property bool loading: false
    property bool saving: false
    property bool fixing: false
    property string lastError: ""
    property string modKey: "Super"
    property string modSymbol: ""
    property bool dmsBindsIncluded: true

    property var dmsStatus: ({
            "exists": true,
            "included": true,
            "includePosition": -1,
            "totalIncludes": 0,
            "bindsAfterDms": 0,
            "effective": true,
            "overriddenBy": 0,
            "statusMessage": ""
        })

    // What the active layout puts on the first level of every physical key,
    // plus the keysym vocabulary that answer is drawn from. See
    // `dms keybinds keymap`. Empty until something asks for it.
    property var firstLevelKeymap: ({})

    property var _rawData: null
    property var keybinds: ({})
    property var _allBinds: ({})
    property var _categories: []
    property var _flatCache: []
    property var displayList: []
    property int _dataVersion: 0
    property string _pendingSavedKey: ""
    readonly property bool requiresBindReview: currentProvider === "aqueous"
    readonly property string bindEditSession: requiresBindReview ? aqueousSession : currentProvider
    readonly property bool bindMutationBusy: aqueousBusy || saving || removeProcess.running
    property bool aqueousBusy: false
    property bool _aqueousLoading: false
    property bool _loadPending: false
    property int _aqueousRequest: 0
    readonly property string aqueousSession: currentProvider === "aqueous" ? AqueousService.session : ""
    onCurrentProviderChanged: _pendingSavedKey = ""

    onAqueousSessionChanged: {
        _aqueousRequest++;
        aqueousBusy = false;
        _pendingSavedKey = "";
        if (aqueousSession)
            Qt.callLater(root.loadBinds, false);
    }

    readonly property var categoryOrder: Actions.getCategoryOrder()
    readonly property string configDir: Paths.strip(StandardPaths.writableLocation(StandardPaths.ConfigLocation))
    readonly property string compositorConfigDir: {
        switch (currentProvider) {
        case "niri":
            return configDir + "/niri";
        case "hyprland":
            return configDir + "/hypr";
        case "mangowc":
            return MangoService.configDir + "/mango";
        default:
            return "";
        }
    }
    readonly property string includeCompositor: currentProvider === "mangowc" ? "mango" : currentProvider
    readonly property var includePaths: ConfigIncludeResolve.includePaths("binds", includeCompositor, includeCompositor === "mango" ? MangoService.configDir : configDir)
    readonly property string dmsBindsPath: includePaths?.fragmentFiles[0] ?? ""
    readonly property string mainConfigPath: includePaths?.configFile ?? ""
    readonly property bool readOnly: currentProvider === "hyprland" && CompositorService.isHyprland && !HyprlandService.luaConfigActive
    readonly property var actionTypes: Actions.getActionTypes()
    readonly property var dmsActions: getDmsActions()

    signal bindsLoaded
    signal bindSaved(string key)
    signal bindSaveCompleted(bool success)
    signal bindRemoved(string key)
    signal dmsBindsFixed
    signal cheatsheetLoaded

    Connections {
        target: CompositorService
        function onCompositorChanged() {
            if (!CompositorService.isNiri && !CompositorService.isMango && !CompositorService.isAqueous)
                return;
            Qt.callLater(root.loadBinds);
        }
    }

    property int _consumers: 0
    property bool _bindsStale: false

    function addRef() {
        _consumers++;
        if (!_bindsStale)
            return;
        _bindsStale = false;
        loadBinds(false);
    }

    function removeRef() {
        _consumers = Math.max(0, _consumers - 1);
    }

    Connections {
        target: NiriService
        enabled: CompositorService.isNiri
        function onConfigReloaded() {
            if (root._consumers === 0) {
                root._bindsStale = true;
                return;
            }
            Qt.callLater(root.loadBinds, false);
        }
    }

    Process {
        id: cheatsheetProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.cheatsheet = JSON.parse(text);
                } catch (e) {
                    log.error("Failed to parse cheatsheet:", e);
                    root.cheatsheet = {};
                }
                root.cheatsheetLoading = false;
                root.cheatsheetLoaded();
            }
        }

        onExited: exitCode => {
            if (exitCode === 0)
                return;
            log.warn("Cheatsheet load failed with code:", exitCode);
            root.cheatsheetLoading = false;
        }
    }

    Process {
        id: keymapProcess
        running: false
        command: ["dms", "keybinds", "keymap"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.firstLevelKeymap = JSON.parse(text);
                } catch (e) {
                    log.warn("Failed to parse keymap:", e);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                log.warn("Keymap load failed with code:", exitCode);
        }
    }

    Process {
        id: loadProcess
        running: false
        property string provider: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (loadProcess.provider !== root.currentProvider)
                    return;
                try {
                    root._rawData = JSON.parse(text);
                    root._processData();
                } catch (e) {
                    log.error("Failed to parse binds:", e);
                }
                root.loading = false;
            }
        }

        onExited: exitCode => {
            if (provider !== root.currentProvider)
                return;
            if (exitCode !== 0) {
                log.warn("Load process failed with code:", exitCode);
                root.loading = false;
            }
        }
    }

    Process {
        id: saveProcess
        running: false
        property string savedKey: ""
        property string provider: ""

        stderr: StdioCollector {
            onStreamFinished: {
                if (saveProcess.provider !== root.currentProvider)
                    return;
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to save keybind"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            root.saving = false;
            if (provider !== root.currentProvider) {
                savedKey = "";
                return;
            }
            if (exitCode !== 0) {
                root._pendingSavedKey = "";
                savedKey = "";
                log.error("Save failed with code:", exitCode);
                root.bindSaveCompleted(false);
                return;
            }
            root.lastError = "";
            root._pendingSavedKey = savedKey;
            savedKey = "";
            root.bindSaveCompleted(true);
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            root.loadBinds(false);
        }
    }

    Process {
        id: removeProcess
        running: false
        property string provider: ""

        stderr: StdioCollector {
            onStreamFinished: {
                if (removeProcess.provider !== root.currentProvider)
                    return;
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to remove keybind"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            if (provider !== root.currentProvider)
                return;
            if (exitCode !== 0) {
                log.error("Remove failed with code:", exitCode);
                return;
            }
            root.lastError = "";
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            root.loadBinds(false);
        }
    }

    Process {
        id: fixProcess
        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                if (!text.trim())
                    return;
                root.lastError = text.trim();
                ToastService.showError(I18n.tr("Failed to add binds include"), "", root.lastError, "keybinds");
            }
        }

        onExited: exitCode => {
            root.fixing = false;
            if (exitCode !== 0) {
                log.error("Fix failed with code:", exitCode);
                return;
            }
            root.lastError = "";
            root.dmsBindsIncluded = true;
            root.dmsBindsFixed();
            ToastService.showInfo(I18n.tr("Binds include added"), I18n.tr("%1 is now included in config", "keybinds toast, %1 is the binds file path").arg("dms/" + root.includePaths.fragmentFiles[0].split("/").pop()), "", "keybinds");
            if (CompositorService.isMango)
                MangoService.reloadConfig();
            Qt.callLater(root.forceReload);
        }
    }

    function fixDmsBindsInclude() {
        if (fixing || dmsBindsIncluded || !compositorConfigDir)
            return;
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        const timestamp = Math.floor(Date.now() / 1000);
        const backupPath = `${mainConfigPath}.dmsbackup${timestamp}`;
        const script = ConfigIncludeResolve.repairScriptFor("binds", includeCompositor, configDir, backupPath);
        if (!script)
            return;
        fixing = true;
        fixProcess.command = ["sh", "-c", script];
        fixProcess.running = true;
    }

    function forceReload() {
        _allBinds = {};
        _flatCache = [];
        _categories = [];
        loadBinds(true);
    }

    function loadCheatsheet(provider) {
        if (cheatsheetProcess.running)
            return;
        const target = provider || cheatsheetProvider;
        if (!target)
            return;
        cheatsheetLoading = true;
        cheatsheetProcess.command = ["dms", "keybinds", "show", target];
        cheatsheetProcess.running = true;
    }

    function canExecuteAction(action, luaAction) {
        if (!action)
            return false;
        if (action.startsWith("spawn ") || action.startsWith("spawn_shell ") || action.startsWith("spawn-sh ") || action.startsWith("exec "))
            return true;
        const provider = currentProvider || cheatsheetProvider;
        const base = action.trim().split(/\s+/)[0];
        if (provider === "niri" && (base === "next-window" || base === "previous-window"))
            return false;
        // Mouse-drag dispatchers do nothing without a pointer, and exit would end the session.
        if (provider === "hyprland" && (action.trim() === "movewindow" || action.trim() === "resizewindow" || base === "exit"))
            return false;
        if (provider === "hyprland" && (!luaAction || !HyprlandService.luaConfigActive))
            return false;
        return provider === "niri" || provider === "hyprland" || provider === "mangowc";
    }

    function executeAction(action, luaAction) {
        if (!action)
            return false;
        log.info("Executing keybind action:", action);

        if (action.startsWith("spawn ") || action.startsWith("spawn_shell ") || action.startsWith("spawn-sh ") || action.startsWith("exec ")) {
            let cmd = action;
            if (cmd.startsWith("spawn "))
                cmd = cmd.slice(6).trim();
            else if (cmd.startsWith("spawn_shell "))
                cmd = cmd.slice(12).trim();
            else if (cmd.startsWith("spawn-sh ")) {
                cmd = cmd.slice(9).trim();
                if ((cmd.startsWith('"') && cmd.endsWith('"')) || (cmd.startsWith("'") && cmd.endsWith("'")))
                    cmd = cmd.slice(1, -1);
            } else if (cmd.startsWith("exec "))
                cmd = cmd.slice(5).trim();

            Quickshell.execDetached(["sh", "-c", cmd]);
            return true;
        }

        const provider = currentProvider || cheatsheetProvider;
        if (provider === "niri") {
            const parts = action.trim().split(/\s+/);
            if (parts.length === 0 || parts[0] === "next-window" || parts[0] === "previous-window")
                return false;

            const cmdParts = [];
            for (let i = 0; i < parts.length; i++) {
                const part = parts[i];
                const eqIdx = part.indexOf("=");
                if (eqIdx !== -1) {
                    const key = part.slice(0, eqIdx);
                    const val = part.slice(eqIdx + 1).replace(/^["']|["']$/g, "");
                    if (key === "skip-confirmation") {
                        if (val === "true")
                            cmdParts.push("--skip-confirmation");
                    } else {
                        cmdParts.push("--" + key + "=" + val);
                    }
                } else {
                    cmdParts.push(part);
                }
            }
            Quickshell.execDetached(["sh", "-c", "niri msg action " + cmdParts.join(" ")]);
            return true;
        }
        if (provider === "hyprland") {
            if (!luaAction || !HyprlandService.luaConfigActive)
                return false;
            Quickshell.execDetached(["hyprctl", "dispatch", luaAction]);
            return true;
        }
        if (provider === "mangowc") {
            const trimmed = action.trim();
            const space = trimmed.indexOf(" ");
            MangoService.dispatch(space < 0 ? trimmed : trimmed.slice(0, space) + "," + trimmed.slice(space + 1).trim());
            return true;
        }

        return false;
    }

    // Cheap enough to re-read every time the editor opens, and the layout may
    // have changed since the last look.
    function loadFirstLevelKeymap() {
        if (keymapProcess.running)
            return;
        keymapProcess.running = true;
    }

    function loadBinds(showLoading) {
        if (currentProvider === "aqueous") {
            _loadPending = true;
            if (_aqueousLoading || aqueousBusy)
                return;
            _loadPending = false;
            _aqueousLoading = true;
            loading = true;
            readAqueousBinds((snapshot, error) => {
                root._aqueousLoading = false;
                root.loading = false;
                if (snapshot) {
                    root.lastError = "";
                    root._rawData = snapshot;
                    root._processData();
                } else {
                    root.lastError = error;
                    root._pendingSavedKey = "";
                }
                if (root._loadPending) {
                    root._loadPending = false;
                    Qt.callLater(root.loadBinds, false);
                }
            });
            return;
        }
        if (loadProcess.running || !available)
            return;
        const hasData = Object.keys(_allBinds).length > 0;
        loading = showLoading !== false && !hasData;
        loadProcess.command = ["dms", "keybinds", "show", currentProvider];
        loadProcess.provider = currentProvider;
        loadProcess.running = true;
    }

    function readAqueousBinds(callback) {
        const session = aqueousSession;
        if (!session) {
            callback(null, I18n.tr("Unavailable"));
            return;
        }
        AqueousService.runJson(["dms", "keybinds", "show", "aqueous"], null, (snapshot, error) => {
            if (session !== root.aqueousSession) {
                callback(null, I18n.tr("Configuration changed. Refresh to continue.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings"));
                return;
            }
            try {
                if (error)
                    throw new Error(error);
                bindInventory(snapshot);
            } catch (e) {
                log.warn("Failed to read Aqueous keybindings:", e);
                callback(null, AqueousService.errorMessage(String(e)));
                return;
            }
            callback(snapshot, "");
        });
    }

    function bindInventory(snapshot) {
        if (snapshot?.provider !== "aqueous" || typeof snapshot.generation !== "string" || !snapshot.generation || !snapshot.binds || Array.isArray(snapshot.binds))
            throw new Error("invalid Aqueous keybind snapshot");
        if (!Array.isArray(snapshot.binds.Compositor) || !Array.isArray(snapshot.binds.Custom))
            throw new Error("missing Aqueous keybind inventory");
        return Object.keys(snapshot.binds).sort().map(category => {
            if (!Array.isArray(snapshot.binds[category]))
                throw new Error("invalid Aqueous keybind category");
            return [category, snapshot.binds[category].map(bind => {
                    if (typeof bind.key !== "string" || typeof bind.action !== "string")
                        throw new Error("invalid Aqueous binding");
                    return [bind.key, bind.action, bind.source || ""];
                })];
        });
    }

    function bindInventoryChanges(baseline, current) {
        const flatten = snapshot => bindInventory(snapshot).reduce((all, group) => all.concat(group[1].map(bind => [group[0], bind])), []);
        const before = flatten(baseline);
        const after = flatten(current);
        const differences = [];
        for (let i = 0; i < Math.max(before.length, after.length); i++) {
            if (JSON.stringify(before[i]) === JSON.stringify(after[i]))
                continue;
            differences.push({
                before: before[i]?.[1] || null,
                after: after[i]?.[1] || null
            });
        }
        return differences;
    }

    function bindingsForKey(snapshot, key) {
        if (!key)
            return [];
        bindInventory(snapshot);
        return Object.values(snapshot.binds).reduce((matches, category) => matches.concat(category.filter(bind => bind.key === key)), []);
    }

    function bindEditIssue(draft, current, reviewing) {
        bindInventory(current);
        if (!["set", "remove", "reset"].includes(draft.operation))
            return "invalid_binding";
        const original = bindingsForKey(current, draft.originalKey);
        if (draft.originalKey && original.length !== 1)
            return original.length ? "ambiguous_target" : "target_removed";
        if (!reviewing && draft.originalKey && original[0].action !== draft.originalAction)
            return "target_changed";
        if (draft.operation !== "set")
            return draft.originalKey ? "" : "target_removed";
        const data = draft.data;
        if (!data?.key || !data.action)
            return "invalid_binding";
        if (data.key !== draft.originalKey && bindingsForKey(current, data.key).length)
            return "destination_occupied";
        if (!data.action.startsWith("spawn ") && !current.binds.Compositor.some(bind => bind.action === data.action))
            return "invalid_action";
        return "";
    }

    function captureBindEdit(binding, key) {
        if (!requiresBindReview)
            return null;
        bindInventory(_rawData);
        if (!bindEditSession)
            throw new Error(I18n.tr("Unavailable"));
        return {
            provider: currentProvider,
            session: bindEditSession,
            action: binding.action || "",
            binding: JSON.parse(JSON.stringify(binding)),
            baseline: JSON.parse(JSON.stringify(_rawData)),
            originalKey: key || "",
            originalAction: binding.action || "",
            operation: "set",
            data: {
                key: key || "",
                action: binding.action || "",
                desc: binding.desc || ""
            }
        };
    }

    function updateBindEdit(draft, key, data, operation) {
        const originals = bindingsForKey(draft.baseline, key);
        return Object.assign({}, draft, {
            operation: operation || draft.operation,
            originalKey: key,
            originalAction: originals.length ? originals[0].action : "",
            data: JSON.parse(JSON.stringify(data || draft.data))
        });
    }

    function loadBindReview(callback) {
        if (requiresBindReview) {
            readAqueousBinds(callback);
            return;
        }
        callback(null, I18n.tr("Unavailable"));
    }

    function reconcileBindEdit(draft, snapshot) {
        const issue = bindEditIssue(draft, snapshot, true);
        if (issue)
            return {
                code: issue
            };
        const originals = bindingsForKey(snapshot, draft.originalKey);
        return {
            draft: Object.assign({}, draft, {
                baseline: JSON.parse(JSON.stringify(snapshot)),
                originalAction: originals.length ? originals[0].action : ""
            })
        };
    }

    function bindEditError(code) {
        switch (code) {
        case "external_change":
            return I18n.tr("Keybindings changed. Refresh and review your edit before saving.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "target_removed":
            return I18n.tr("The original shortcut was removed. Discard this edit or add a new shortcut.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "ambiguous_target":
            return I18n.tr("Multiple bindings use the original shortcut. Resolve the duplicate bindings first.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "destination_occupied":
            return I18n.tr("The new shortcut is already in use. Choose another shortcut.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "target_changed":
            return I18n.tr("The original shortcut changed. Refresh and review your edit.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "invalidated":
            return I18n.tr("The compositor session changed. Discard this edit before starting a new one.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "uncertain":
            return I18n.tr("The save result is unknown. Refresh and check the current bindings.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        case "invalid_action":
            return I18n.tr("The selected action is no longer available.", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings");
        default:
            return I18n.tr("Failed to save keybind");
        }
    }

    function describeBindReview(draft, current) {
        if (!draft || !current)
            return "";
        const describe = (snapshot, key) => {
            const matches = bindingsForKey(snapshot, key);
            return matches.length ? matches.map(bind => bind.key + " → " + bind.action).join("\n") : I18n.tr("None");
        };
        const original = describe(draft.baseline, draft.originalKey);
        const currentBind = describe(current, draft.originalKey);
        const proposed = draft.operation === "set" ? draft.data.key + " → " + draft.data.action : I18n.tr("Remove");
        const destination = draft.operation === "set" ? describe(current, draft.data.key) : I18n.tr("None");
        const describeChange = bind => bind ? (bind[0] || I18n.tr("Not bound")) + " → " + bind[1] : I18n.tr("None");
        const changes = bindInventoryChanges(draft.baseline, current).map(change => I18n.tr("Previous: %1\nCurrent: %2", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings").arg(describeChange(change.before)).arg(describeChange(change.after))).join("\n\n");
        return I18n.tr("Original: %1\nCurrent: %2\nProposed: %3\nCurrent destination: %4", "Aqueous keyboard shortcut editor, explaining a conflict or comparing an unsaved edit with current bindings").arg(original).arg(currentBind).arg(proposed).arg(destination) + (changes ? "\n\n" + changes : "");
    }

    function _mutateAqueous(draft, callback) {
        if (aqueousBusy || saving || removeProcess.running) {
            callback({
                success: false,
                code: "busy"
            });
            return;
        }
        if (!draft?.baseline || !aqueousSession || draft.session !== aqueousSession) {
            callback({
                success: false,
                code: "invalidated"
            });
            return;
        }
        const edit = JSON.parse(JSON.stringify(draft));
        const request = ++_aqueousRequest;
        aqueousBusy = true;
        const complete = result => {
            if (request !== root._aqueousRequest)
                return;
            root.aqueousBusy = false;
            callback(result);
            if (result.success || root._loadPending) {
                root._loadPending = false;
                Qt.callLater(root.loadBinds, false);
            }
        };
        readAqueousBinds((snapshot, error) => {
            if (request !== root._aqueousRequest)
                return;
            if (error) {
                complete({
                    success: false,
                    code: "load_failed",
                    message: error
                });
                return;
            }
            try {
                if (JSON.stringify(bindInventory(edit.baseline)) !== JSON.stringify(bindInventory(snapshot))) {
                    complete({
                        success: false,
                        code: "external_change",
                        snapshot: snapshot
                    });
                    return;
                }
                const issue = bindEditIssue(edit, snapshot, false);
                if (issue) {
                    complete({
                        success: false,
                        code: issue,
                        snapshot: snapshot
                    });
                    return;
                }
            } catch (e) {
                complete({
                    success: false,
                    code: "invalid_snapshot",
                    message: String(e)
                });
                return;
            }
            const args = ["dms", "keybinds", edit.operation, currentProvider, edit.operation === "set" ? edit.data.key : edit.originalKey];
            if (edit.operation === "set") {
                args.push(edit.data.action);
                if (edit.originalKey && edit.originalKey !== edit.data.key)
                    args.push("--replace-key", edit.originalKey);
            }
            args.push("--expected-generation", snapshot.generation, "--json");
            AqueousService.runJson(args, null, (result, error) => {
                if (request !== root._aqueousRequest)
                    return;
                if (error || result?.success !== true || !result.generation) {
                    complete({
                        success: false,
                        code: result?.success === false && result.code ? result.code : "uncertain",
                        message: result?.message || error
                    });
                    return;
                }
                if (edit.operation === "set")
                    root._pendingSavedKey = edit.data.key;
                complete(result);
                if (edit.operation === "set")
                    root.bindSaveCompleted(true);
                else
                    root.bindRemoved(edit.originalKey);
            });
        });
    }

    function _processData() {
        keybinds = _rawData || {};
        modKey = _rawData?.mod?.resolved || _rawData?.modKey || "Super";
        modSymbol = _rawData?.mod?.symbol || "";
        dmsBindsIncluded = _rawData?.dmsBindsIncluded ?? true;
        const status = _rawData?.dmsStatus;
        if (status) {
            dmsStatus = {
                "exists": status.exists ?? true,
                "included": status.included ?? true,
                "includePosition": status.includePosition ?? -1,
                "totalIncludes": status.totalIncludes ?? 0,
                "bindsAfterDms": status.bindsAfterDms ?? 0,
                "effective": status.effective ?? true,
                "overriddenBy": status.overriddenBy ?? 0,
                "statusMessage": status.statusMessage ?? ""
            };
        }
        _maybeWarnHyprlandLegacyConf();

        if (!_rawData?.binds) {
            _allBinds = {};
            _categories = [];
            _flatCache = [];
            displayList = [];
            _dataVersion++;
            bindsLoaded();
            if (_pendingSavedKey) {
                bindSaved(_pendingSavedKey);
                _pendingSavedKey = "";
            }
            return;
        }

        const processed = {};
        const bindsData = _rawData.binds;
        for (const cat in bindsData) {
            const binds = bindsData[cat];
            for (var i = 0; i < binds.length; i++) {
                const bind = binds[i];
                if (currentProvider === "hyprland" && bind.action && bind.action.startsWith("exec "))
                    bind.action = "spawn " + bind.action.slice(5);
                const targetCat = Actions.isDmsAction(bind.action) ? "DMS" : cat;
                if (!processed[targetCat])
                    processed[targetCat] = [];
                processed[targetCat].push(bind);
            }
        }

        const sortedCats = Object.keys(processed).sort((a, b) => {
            const ai = categoryOrder.indexOf(a);
            const bi = categoryOrder.indexOf(b);
            return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
        });

        const grouped = [];
        const actionMap = {};
        for (var ci = 0; ci < sortedCats.length; ci++) {
            const category = sortedCats[ci];
            const binds = processed[category];
            if (!binds)
                continue;
            for (var i = 0; i < binds.length; i++) {
                const bind = binds[i];
                const action = bind.action || "";
                const sourceStr = bind.source || "config";
                const keyData = {
                    "key": bind.key || "",
                    "desc": bind.desc || "",
                    "source": sourceStr,
                    "isOverride": sourceStr === "dms",
                    "isDMSManaged": sourceStr === "dms" || sourceStr === "dms-default",
                    "hasDefault": bind.hasDefault === true,
                    "cooldownMs": bind.cooldownMs || 0,
                    "flags": bind.flags || "",
                    "allowWhenLocked": bind.allowWhenLocked || false,
                    "allowInhibiting": bind.allowInhibiting,
                    "repeat": bind.repeat
                };
                if (actionMap[action]) {
                    actionMap[action].keys.push(keyData);
                    if (!actionMap[action].desc && bind.desc)
                        actionMap[action].desc = bind.desc;
                    if (!actionMap[action].conflict && bind.conflict)
                        actionMap[action].conflict = bind.conflict;
                } else {
                    const entry = {
                        "category": category,
                        "action": action,
                        "desc": bind.desc || "",
                        "keys": [keyData],
                        "conflict": bind.conflict || null
                    };
                    actionMap[action] = entry;
                    grouped.push(entry);
                }
            }
        }

        const list = [];
        for (const cat of sortedCats) {
            list.push({
                "id": "cat:" + cat,
                "type": "category",
                "name": cat
            });
            const binds = processed[cat];
            if (!binds)
                continue;
            for (const bind of binds)
                list.push({
                    "id": "bind:" + bind.key,
                    "type": "bind",
                    "key": bind.key,
                    "desc": bind.desc
                });
        }

        _allBinds = processed;
        _categories = sortedCats;
        _flatCache = grouped;
        displayList = list;
        _dataVersion++;
        bindsLoaded();
        if (_pendingSavedKey) {
            bindSaved(_pendingSavedKey);
            _pendingSavedKey = "";
        }
    }

    function getCategories() {
        return _categories;
    }

    function getFlatBinds() {
        return _flatCache;
    }

    function keysForAction(actionId) {
        if (!actionId)
            return [];
        for (let i = 0; i < _flatCache.length; i++) {
            const group = _flatCache[i];
            if (!group || group.action !== actionId || !Array.isArray(group.keys))
                continue;
            const keys = [];
            for (let k = 0; k < group.keys.length; k++) {
                const key = group.keys[k]?.key || "";
                if (key)
                    keys.push(key);
            }
            return keys;
        }
        return [];
    }

    function saveBind(originalKey, bindData, draft, callback) {
        if (currentProvider === "aqueous") {
            _mutateAqueous(draft, callback || (() => {}));
            return;
        }
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!bindData.key || !Actions.isValidAction(bindData.action))
            return;
        saving = true;
        const cmd = ["dms", "keybinds", "set", currentProvider, bindData.key, bindData.action];
        cmd.push("--desc", bindData.desc || "");
        if (originalKey && originalKey !== bindData.key)
            cmd.push("--replace-key", originalKey);
        if (bindData.cooldownMs > 0)
            cmd.push("--cooldown-ms", String(bindData.cooldownMs));
        if (bindData.allowWhenLocked)
            cmd.push("--allow-when-locked");
        if (bindData.repeat === false)
            cmd.push("--no-repeat");
        if (bindData.allowInhibiting === false)
            cmd.push("--no-inhibiting");
        if (bindData.flags)
            cmd.push("--flags", bindData.flags);
        saveProcess.command = cmd;
        saveProcess.provider = currentProvider;
        saveProcess.savedKey = bindData.key;
        saveProcess.running = true;
    }

    property bool _hyprlandLegacyWarnShown: false

    function _maybeWarnHyprlandLegacyConf() {
        if (_hyprlandLegacyWarnShown)
            return;
        if (currentProvider !== "hyprland" || !HyprlandService.luaConfigStatusReady)
            return;
        if (readOnly) {
            _hyprlandLegacyWarnShown = true;
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!dmsStatus.exists || dmsStatus.included)
            return;
        _hyprlandLegacyWarnShown = true;
        ToastService.showWarning(I18n.tr("Hyprland config include missing"), I18n.tr("DMS Settings writes Lua keybinds. Add the DMS include so edits apply."), "dms setup", "hyprland-migration");
    }

    function showHyprlandReadOnlyWarning() {
        ToastService.showWarning(I18n.tr("%1 not found").arg("hyprland.lua"), I18n.tr("Run %1 to create it before changing these settings.", "hyprland.lua missing warning, %1 is a command").arg("dms setup"), "dms setup", "hyprland-migration");
    }

    function removeBind(key, draft, callback) {
        if (currentProvider === "aqueous") {
            _mutateAqueous(draft, callback || (() => {}));
            return;
        }
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!key)
            return;
        removeProcess.command = ["dms", "keybinds", "remove", currentProvider, key];
        removeProcess.provider = currentProvider;
        removeProcess.running = true;
        bindRemoved(key);
    }

    function resetBind(key, draft, callback) {
        if (currentProvider === "aqueous") {
            _mutateAqueous(draft, callback || (() => {}));
            return;
        }
        if (readOnly) {
            showHyprlandReadOnlyWarning();
            return;
        }
        if (!key)
            return;
        removeProcess.command = ["dms", "keybinds", "reset", currentProvider, key];
        removeProcess.provider = currentProvider;
        removeProcess.running = true;
        bindRemoved(key);
    }

    function getActionLabel(action) {
        if (currentProvider === "aqueous")
            return (_rawData?.binds?.Compositor || []).find(b => b.action === action)?.desc || Actions.getActionLabel(action, currentProvider);
        return Actions.getActionLabel(action, currentProvider);
    }

    function isKnownCompositorAction(action) {
        if (currentProvider === "aqueous")
            return (_rawData?.binds?.Compositor || []).some(b => b.action === action);
        return Actions.isKnownCompositorAction(currentProvider, action);
    }

    function getCompositorCategories() {
        if (currentProvider === "aqueous")
            return ["Compositor"];
        return Actions.getCompositorCategories(currentProvider);
    }

    function getCompositorActions(category) {
        if (currentProvider === "aqueous") {
            const seen = new Set();
            return (_rawData?.binds?.Compositor || []).filter(b => {
                if (seen.has(b.action))
                    return false;
                seen.add(b.action);
                return true;
            }).map(b => ({
                        id: b.action,
                        label: b.desc
                    }));
        }
        return Actions.getCompositorActions(currentProvider, category);
    }

    function getDmsActions() {
        const actions = Actions.getDmsActions(CompositorService.isNiri, CompositorService.isHyprland);
        if (!AdminPolicy.disableLockIpcUnlock)
            return actions;
        return actions.filter(action => action.id !== "spawn dms ipc call lock demo");
    }
}
