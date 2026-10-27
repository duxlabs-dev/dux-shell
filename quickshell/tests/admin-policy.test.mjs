import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

function functionSource(file, name) {
    const source = readFileSync(new URL(file, import.meta.url), "utf8");
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\)(?:: \\w+)? \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in ${file}`);
    return found[0];
}

test("the lock IPC switch drops the lock demo keybind action and keeps the others", () => {
    const getDmsActions = functionSource("../Services/KeybindsService.qml", "getDmsActions");
    const Actions = loadScript(new URL("../Common/KeybindActions.js", import.meta.url));
    for (const disableLockIpcUnlock of [false, true]) {
        const context = vm.createContext({ Actions, CompositorService: { isNiri: false, isHyprland: false }, AdminPolicy: { disableLockIpcUnlock } });
        vm.runInContext(getDmsActions, context);
        const ids = context.getDmsActions().map(action => action.id);
        assert.equal(ids.includes("spawn dms ipc call lock demo"), !disableLockIpcUnlock);
        assert.ok(ids.includes("spawn dms ipc call lock lock"));
        assert.equal(ids.length, Actions.getDmsActions(false, false).length - (disableLockIpcUnlock ? 1 : 0));
    }
});

test("the user plugin switch keeps the user tree out of a scan and a resync", () => {
    const user = "/home/user/.config/DankMaterialShell/plugins";
    const system = "/etc/xdg/quickshell/dms-plugins";
    const folder = dirs => ({ folder: "", count: dirs.length, get: (i, role) => role === "filePath" ? "file://" + dirs[i] : 0 });
    for (const disableUserPlugins of [false, true]) {
        const loaded = [];
        const context = vm.createContext({
            Date,
            AdminPolicy: { disableUserPlugins },
            Paths: { toFileUrl: path => "file://" + path },
            pluginDirectory: user,
            systemPluginDirectory: system,
            userWatcher: folder([user + "/probe"]),
            systemWatcher: folder([system + "/admitted"]),
            resyncDebounce: { restart() {} },
            checkPluginDirectoryExists() {},
            knownManifests: {},
            pathToPluginId: {},
            directoryModifiedTimes: {},
            loadPluginManifestFile: (path, source) => loaded.push([path, source])
        });
        context.root = context;
        for (const name of ["snapshotModel", "resyncAll", "scanPlugins"])
            vm.runInContext(functionSource("../Services/PluginService.qml", name), context);
        context.scanPlugins();
        assert.equal(context.userWatcher.folder, disableUserPlugins ? "" : "file://" + user);
        assert.equal(context.systemWatcher.folder, "file://" + system);
        context.resyncAll();
        const userManifests = disableUserPlugins ? [] : [[user + "/probe/plugin.json", "user"]];
        assert.deepEqual(loaded, [...userManifests, [system + "/admitted/plugin.json", "system"]]);
    }
});

function settingsIpcHandlers() {
    const source = readFileSync(new URL("../DMSShellIPC.qml", import.meta.url), "utf8");
    const block = source.slice(source.indexOf("        function get(key: string)"), source.indexOf('        target: "settings"'));
    return [...block.matchAll(/^ {8}function \w+\([^)]*\)(?:: \w+)? \{\n[\s\S]*?^ {8}\}$/gm)].map(match => match[0].replace(/\((.*?)\)(?:: \w+)? \{/, (_, params) => "(" + params.replace(/: \w+/g, "") + ") {"));
}

test("the settings IPC switch refuses set and keeps get", () => {
    const handlers = settingsIpcHandlers();
    for (const disableSettingsIpcSet of [false, true]) {
        const SettingsData = { lockBeforeSuspend: false, saveSettings() {}, isManaged: () => false };
        const context = vm.createContext({ AdminPolicy: { disableSettingsIpcSet }, SettingsData, log: { warn() {} } });
        for (const handler of handlers)
            vm.runInContext(handler, context);
        assert.equal(context.set("lockBeforeSuspend", "true"), disableSettingsIpcSet ? "SETTINGS_SET_DISABLED" : "SETTINGS_SET_SUCCESS");
        assert.equal(SettingsData.lockBeforeSuspend, !disableSettingsIpcSet);
        assert.equal(context.get("lockBeforeSuspend"), String(!disableSettingsIpcSet));
    }
});

const ManagedSettings = loadScript(new URL("../Common/settings/ManagedSettings.js", import.meta.url));
const SettingsStore = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
const SPEC = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC;

function settingsDataContext(globals, names) {
    const context = vm.createContext(globals);
    context.root = context;
    for (const name of names)
        vm.runInContext(functionSource("../Common/SettingsData.qml", name), context);
    return context;
}

test("managed lock settings keep only values of the default's type", () => {
    const warnings = [];
    const settings = ManagedSettings.parse(JSON.stringify({
        lockBeforeSuspend: true,
        customPowerActionLock: "",
        acLockTimeout: 300,
        u2fMode: null,
        enableFprint: "yes",
        maxFprintTries: [3],
        notASetting: true
    }), (...args) => warnings.push(args[1]));
    assert.deepEqual({ ...settings }, { lockBeforeSuspend: true, customPowerActionLock: "", acLockTimeout: 300 });
    assert.deepEqual(warnings.sort(), ["enableFprint", "maxFprintTries", "notASetting", "u2fMode"]);
    assert.deepEqual({ ...ManagedSettings.parse("", () => assert.fail("no policy, no warning")) }, {});
});

test("managed settings win over every settings file, on the first load and on each reload", () => {
    const version = Number(readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8").match(/settingsConfigVersion: (\d+)/)[1]);
    let files = { configVersion: version, lockBeforeSuspend: false, customPowerActionLock: "true", acLockTimeout: 60 };
    const context = settingsDataContext({
        AdminPolicy: { lockSettings: { lockBeforeSuspend: true, customPowerActionLock: "" } },
        SettingsData: { Stage: { Partial: 2, Ready: 3 } },
        Store: SettingsStore,
        settingsConfigVersion: version,
        _hasLoaded: false,
        _settingsStage: 3,
        _parseError: false,
        frameEnabled: false,
        frameMode: "",
        _getSettingsObjectFromFiles: () => JSON.parse(JSON.stringify(files)),
        _mergeSessionState() {},
        Qt: { callLater() {} },
        checkIconThemeDrift() {},
        applyStoredTheme() {},
        updateCompositorCursor() {},
        updateFrameCompositorLayout() {},
        loadPluginSettings() {},
        clearIslandBars() {}
    }, ["_loadSettings"]);
    for (const userValue of [false, true]) {
        files = Object.assign({}, files, { lockBeforeSuspend: userValue, acLockTimeout: files.acLockTimeout * 2 });
        assert.equal(context._loadSettings(), false, "managed values are no unsaved change");
        assert.equal(context.lockBeforeSuspend, true);
        assert.equal(context.customPowerActionLock, "");
        assert.equal(context.acLockTimeout, files.acLockTimeout);
    }
});

test("a save leaves managed keys out of the settings files, and a user's own value in place", () => {
    const main = "/home/u/.config/dms/settings.json";
    const overlay = "/home/u/.config/dms/config.d/lock.json";
    const fileSettings = { [main]: { lockBeforeSuspend: false, acLockTimeout: 60 }, [overlay]: { customPowerActionLock: "true", fadeToLockEnabled: false } };
    const context = settingsDataContext({
        AdminPolicy: { lockSettings: { lockBeforeSuspend: true, customPowerActionLock: "", batteryLockTimeout: 300 } },
        _settingsFilesPaths: [main, overlay],
        _settingsFiles: new Map(Object.keys(fileSettings).map(path => [path, { getSettings: () => Object.assign({}, fileSettings[path]) }])),
        defaultSettingsFile: { filePath: main }
    }, ["isManaged", "_splitSettingsByFile"]);
    const split = context._splitSettingsByFile({ configVersion: 42, lockBeforeSuspend: true, customPowerActionLock: "", batteryLockTimeout: 300, acLockTimeout: 120, fadeToLockEnabled: true, lockAtStartup: true });
    assert.deepEqual(JSON.parse(JSON.stringify(split)), {
        [main]: { lockBeforeSuspend: false, acLockTimeout: 120, configVersion: 42, lockAtStartup: true },
        [overlay]: { customPowerActionLock: "true", fadeToLockEnabled: true }
    });
});

test("set and reset refuse managed keys and change the others", () => {
    const changes = [];
    const warnings = [];
    const context = settingsDataContext({
        AdminPolicy: { lockSettings: { lockBeforeSuspend: true } },
        Spec: { SPEC, set: (root, key, value) => changes.push([key, value]) },
        log: { warn: (...args) => warnings.push(args.at(-1)) },
        saveSettings() {},
        _hooks: {},
        lockBeforeSuspend: true
    }, ["isManaged", "set", "resetToDefault"]);
    context.set("lockBeforeSuspend", false);
    context.set("lockAtStartup", true);
    context.resetToDefault(["lockBeforeSuspend", "acLockTimeout"]);
    assert.deepEqual(changes, [["lockAtStartup", true], ["acLockTimeout", null]]);
    assert.deepEqual(warnings, ["lockBeforeSuspend"]);
});

test("settings IPC set refuses a managed key, also with the settings IPC switch off", () => {
    const handlers = settingsIpcHandlers();
    const managed = new Set(["lockBeforeSuspend"]);
    for (const disableSettingsIpcSet of [false, true]) {
        const SettingsData = { lockBeforeSuspend: true, lockAtStartup: false, saveSettings() {}, isManaged: key => managed.has(key) };
        const context = vm.createContext({ AdminPolicy: { disableSettingsIpcSet }, SettingsData, log: { warn() {} } });
        for (const handler of handlers)
            vm.runInContext(handler, context);
        assert.equal(context.set("lockBeforeSuspend", "false"), disableSettingsIpcSet ? "SETTINGS_SET_DISABLED" : "SETTINGS_SET_MANAGED");
        assert.equal(SettingsData.lockBeforeSuspend, true);
        assert.equal(context.set("lockAtStartup", "true"), disableSettingsIpcSet ? "SETTINGS_SET_DISABLED" : "SETTINGS_SET_SUCCESS");
        assert.equal(SettingsData.lockAtStartup, !disableSettingsIpcSet);
    }
});

test("the legacy session migration leaves managed lock settings alone", () => {
    const managed = new Set(["acLockTimeout", "lockBeforeSuspend"]);
    const changes = [];
    const context = vm.createContext({ SettingsData: { isManaged: key => managed.has(key), set: (key, value) => changes.push([key, value]) } });
    vm.runInContext(functionSource("../Common/SessionData.qml", "migrateFromUndefinedToV1"), context);
    context.migrateFromUndefinedToV1({ acMonitorTimeout: 30, acLockTimeout: 60, lockBeforeSuspend: false, loginctlLockIntegration: false, launchPrefix: "uwsm app --" });
    assert.deepEqual(changes, [["acMonitorTimeout", 30], ["loginctlLockIntegration", false], ["launchPrefix", "uwsm app --"]]);
});
