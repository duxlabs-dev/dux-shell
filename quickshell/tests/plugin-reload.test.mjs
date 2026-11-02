import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Services/PluginService.qml", import.meta.url), "utf8");

function service({ enabled = true, type = "widget" } = {}) {
    const compiled = new Map();
    const files = new Map();
    const requests = [];
    const pending = [];
    const failures = [];
    const destroyed = [];
    const manifest = { id: "fixture", name: "Fixture", type, component: "./Widget.qml", settings: "./Settings.qml" };
    const context = vm.createContext({
        Date, Object,
        availablePlugins: {}, loadedPlugins: {}, knownManifests: {}, pathToPluginId: {},
        pluginWidgetComponents: {}, pluginDesktopComponents: {}, pluginDaemonComponents: {},
        pluginLauncherComponents: {}, pluginDashComponents: {}, pluginDashCardComponents: {},
        pluginInstances: {}, pluginDaemonInstances: {}, installingPlugins: {}, _componentRevisions: {},
        _daemonSpawnQueue: [], _daemonSpawnTimer: { restart() {} },
        pluginSurfaceKeys: ["widget", "desktop", "daemon", "launcher", "dash", "dashCard"],
        log: { error() {}, warn() {} },
        Paths: { toFileUrl: path => path.startsWith("file://") ? path : "file://" + path },
        SettingsData: { getPluginSetting: () => enabled },
        DMSService: { update: (id, callback) => requests.push(callback), installedPlugins: [] },
        ShellVersionService: { checkVersionRequirement: requirement => !requirement.startsWith(">=99"), getParsedShellVersion: () => ({}) },
        Component: { Error: 3, PreferSynchronous: 0 },
        I18n: { tr: text => Object.assign(new String(text), { arg: value => text.replace("%1", value) }) },
        ToastService: { showError() {} },
        // Like Qt's type loader, a URL keeps whatever it first compiled to, errors included.
        Qt: { createComponent(url) {
            if (!compiled.has(url)) {
                const value = files.get(url.split("?")[0]);
                compiled.set(url, value instanceof Error
                    ? { status: 3, errorString: () => value.message, destroy() {} }
                    : { value, createObject() { return this.value; }, destroy() { destroyed.push(url); } });
            }
            return compiled.get(url);
        } },
        pluginLoaded() {}, pluginUnloaded() {}, pluginListUpdated() {},
        pluginLoadFailed: (id, error) => failures.push(error),
        _clearLoadError() {}, _setLoadError() {}, _updateAvailablePluginsList() {},
        _loadPluginTranslations() {}, _cleanupPluginStateWriter() {},
        isPluginLoaded: id => !!context.loadedPlugins[id],
        loadPluginManifestFile: (path, source, time) => pending.push(() => context._onManifestParsed(path, manifest, source, time))
    });
    context.root = context;
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^    \}/gm)) {
        if (match[1] in context)
            continue;
        vm.runInContext(match[0], context);
    }
    files.set("file:///plugins/fixture/Widget.qml", 12);
    context._onManifestParsed("/plugins/fixture/plugin.json", manifest, "user", 1);
    return { context, files, requests, pending, failures, manifest, destroyed };
}

test("successful updates replace cached components and reread the manifest", () => {
    const { context, files, requests, pending, manifest } = service();
    assert.equal(context.pluginWidgetComponents.fixture.value, 12);
    files.set("file:///plugins/fixture/Widget.qml", 16);
    manifest.version = "2.0.0";
    let response;
    context.updatePlugin("fixture", value => response = value);
    const result = { result: { success: true } };
    requests.shift()(result);
    assert.equal(response, result);
    assert.equal(pending.length, 1);
    pending.shift()();
    assert.equal(context.pluginWidgetComponents.fixture.value, 16);
    assert.equal(context.availablePlugins.fixture.version, "2.0.0");
});

test("an update whose registry entry needs a newer shell is refused before the download", () => {
    const { context, requests, pending } = service();
    context.DMSService.installedPlugins = [{ id: "fixture", requires_dms: ">=99.0.0" }];
    let response;
    context.updatePlugin("fixture", value => response = value);
    assert.equal(requests.length, 0);
    assert.equal(pending.length, 0);
    assert.match(response.error, /99\.0\.0/);
    context.DMSService.installedPlugins = [{ id: "fixture", requires_dms: ">=1.0.0" }];
    context.updatePlugin("fixture");
    assert.equal(requests.length, 1);
});

test("failed updates preserve the running plugin and forward the error", () => {
    const { context, requests, pending } = service();
    const component = context.pluginWidgetComponents.fixture;
    let response;
    context.updatePlugin("fixture", value => response = value);
    requests.shift()({ error: "download failed" });
    assert.equal(response.error, "download failed");
    assert.equal(pending.length, 0);
    assert.equal(context.pluginWidgetComponents.fixture, component);
});

test("updating a disabled plugin keeps it disabled and its next load is fresh", () => {
    const { context, files, requests, pending } = service({ enabled: false });
    context.loadPlugin("fixture");
    context.unloadPlugin("fixture");
    files.set("file:///plugins/fixture/Widget.qml", 18);
    context.updatePlugin("fixture");
    requests.shift()({});
    pending.shift()();
    assert.equal(context.isPluginLoaded("fixture"), false);
    context.loadPlugin("fixture");
    assert.equal(context.pluginWidgetComponents.fixture.value, 18);
});

test("reload and rescan retain fresh components across disable and enable", () => {
    const { context, files, pending } = service();
    for (let value = 13; value <= 16; value++) {
        files.set("file:///plugins/fixture/Widget.qml", value);
        assert.equal(context.reloadPlugin("fixture"), true);
        assert.equal(context.pluginWidgetComponents.fixture.value, value);
        context.unloadPlugin("fixture");
        context.loadPlugin("fixture");
        assert.equal(context.pluginWidgetComponents.fixture.value, value);
    }
    files.set("file:///plugins/fixture/Widget.qml", 20);
    context.forceRescanPlugin("fixture");
    pending.shift()();
    assert.equal(context.pluginWidgetComponents.fixture.value, 20);
});

test("rescan picks up changed surfaces and preserves automatic desktop loading", () => {
    const { context, files, pending, manifest } = service({ enabled: false, type: "desktop" });
    assert.equal(context.pluginDesktopComponents.fixture.value, 12);
    manifest.component = "./Desktop.qml";
    files.set("file:///plugins/fixture/Desktop.qml", 24);
    context.forceRescanPlugin("fixture");
    pending.shift()();
    assert.equal(context.pluginDesktopComponents.fixture.value, 24);
});

test("single component dash plugins load onto their dash surface", () => {
    for (const [type, key] of [["dash", "pluginDashComponents"], ["dashCard", "pluginDashCardComponents"]]) {
        const { context } = service({ type });
        assert.deepEqual(context.availablePlugins.fixture.surfaces, [type]);
        assert.equal(context[key].fixture.value, 12);
        assert.equal(context.pluginWidgetComponents.fixture, undefined);
    }
});

test("unloading destroys the plugin's components", () => {
    const { context, destroyed } = service();
    assert.equal(context.unloadPlugin("fixture"), true);
    assert.deepEqual(destroyed, ["file:///plugins/fixture/Widget.qml"]);
    assert.equal(context.pluginWidgetComponents.fixture, undefined);
});

test("settings and startup checks use the current plugin revision", () => {
    const { context, files } = service();
    const path = "/plugins/fixture/Settings.qml";
    files.set("file://" + path, 12);
    const before = context.pluginComponentUrl("fixture", path);
    assert.equal(context.Qt.createComponent(before).value, 12);
    files.set("file://" + path, 18);
    context.reloadPlugin("fixture");
    const after = context.pluginComponentUrl("fixture", path);
    assert.equal(context.Qt.createComponent(after).value, 18);
    assert.equal(context.pluginComponentUrl("fixture", "file://" + path), after);
    assert.equal(context.pluginComponentUrl("fixture", null), "");
    assert.equal(context._makeStartupCheckObject("fixture", { startupCheckPath: path }), 18);
});

test("unload failures abort reload and rescan without discarding the manifest", () => {
    const { context, pending } = service();
    const plugin = context.availablePlugins.fixture;
    context.unloadPlugin = () => false;
    assert.equal(context.reloadPlugin("fixture"), false);
    context.forceRescanPlugin("fixture");
    assert.equal(context.availablePlugins.fixture, plugin);
    assert.equal(pending.length, 0);
});

test("updated startup checks still prevent activation on failure", () => {
    const { context, files, pending, manifest, failures } = service();
    manifest.startupCheck = "./Check.qml";
    files.set("file:///plugins/fixture/Check.qml", {
        check: () => "dependency unavailable",
        destroy() {}
    });
    context.forceRescanPlugin("fixture");
    pending.shift()();
    assert.equal(context.isPluginLoaded("fixture"), false);
    assert.equal(failures.at(-1), "dependency unavailable");
    files.set("file:///plugins/fixture/Check.qml", {
        check: () => null,
        destroy() {}
    });
    context.forceRescanPlugin("fixture");
    pending.shift()();
    assert.equal(context.isPluginLoaded("fixture"), true);
    files.set("file:///plugins/fixture/Check.qml", {
        check: () => "dependency removed",
        destroy() {}
    });
    context.reloadPlugin("fixture");
    assert.equal(context.isPluginLoaded("fixture"), false);
    assert.equal(failures.at(-1), "dependency removed");
});

test("startup checks that cannot run prevent activation", () => {
    const { context, files, pending, manifest, failures } = service();
    const createComponent = context.Qt.createComponent;
    context.Qt.createComponent = url => url.startsWith("file:///plugins/fixture/Broken.qml") ? { status: 3, errorString: () => "module missing" } : createComponent(url);
    const cases = [
        ["./Broken.qml", null, "module missing"],
        ["./Check.qml", { destroy() {} }, "startupCheck has no check function"],
        ["./Check.qml", { check() { throw new Error("sync throw"); }, destroy() {} }, "sync throw"],
        ["./Check.qml", { check(done) { throw new Error("async throw"); }, destroy() {} }, "async throw"]
    ];
    for (const [path, probe, error] of cases) {
        manifest.startupCheck = path;
        files.set("file:///plugins/fixture/Check.qml", probe);
        context.forceRescanPlugin("fixture");
        pending.shift()();
        assert.equal(context.isPluginLoaded("fixture"), false, error);
        assert.equal(failures.at(-1), error);
    }
});

test("composite updates refresh every surface without creating daemons synchronously", () => {
    const { context, files, pending, manifest } = service();
    delete manifest.component;
    manifest.components = Object.fromEntries(context.pluginSurfaceKeys.map(surface => [surface, "./" + surface + ".qml"]));
    for (const value of [12, 20]) {
        for (const surface of context.pluginSurfaceKeys)
            files.set("file:///plugins/fixture/" + surface + ".qml", value);
        context.forceRescanPlugin("fixture");
        pending.shift()();
        for (const key of ["pluginWidgetComponents", "pluginDesktopComponents", "pluginDaemonComponents", "pluginLauncherComponents", "pluginDashComponents", "pluginDashCardComponents"])
            assert.equal(context[key].fixture.value, value);
        assert.equal(context.pluginDaemonInstances.fixture, undefined);
    }
});

test("a stale directory listing explains that the shell needs a restart", () => {
    const cases = [
        ["Script file:///plugins/fixture/Helper.js unavailable\nfile:///plugins/fixture/Helper.js: File name case mismatch", /Restart DMS/],
        ["Widget.qml:3:1: Type Helper unavailable", /^$/]
    ];
    for (const [message, details] of cases) {
        const { context, files } = service({ enabled: false });
        const errors = [];
        context._setLoadError = (id, error) => errors.push(error);
        files.set("file:///plugins/fixture/Widget.qml", new Error(message));
        assert.equal(context.loadPlugin("fixture"), false);
        assert.equal(errors.at(-1).title, message);
        assert.match(String(errors.at(-1).details), details);
    }
});
