import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

// Services/IslandActivityService.qml's own logic, its functions run in a vm context over doubles of the services it reads
// (as plugin-reload.test.mjs runs PluginService): live scripts by prefix, a source replacing its own activity, refusals,
// do not disturb, and the activities a plugin loses when it is blocked.
const source = readFileSync(new URL("../Services/IslandActivityService.qml", import.meta.url), "utf8");

function service({ islands = ["DP-1"], dnd = false, bypass = [], allowCritical = false } = {}) {
    const signals = [];
    const blocked = [];
    const context = vm.createContext({
        Object, String, Array,
        requests: {}, revision: 0, nextSeq: 1,
        islandComponents: { weather: {} }, islandSystemComponents: {},
        log: { warn() {}, info() {} },
        Activities: loadScript(new URL("../Common/IslandActivities.js", import.meta.url)),
        Input: loadScript(new URL("../Common/IslandActivityInput.js", import.meta.url)),
        Quickshell: { screens: islands.map(name => ({ name })) },
        PopoutService: { dankIslandRouter: islands.length === 0 ? null : {
            hostForScreenName: name => islands.indexOf(name) === -1 ? null : { islandController: name },
            focusedHost: () => ({ screen: { name: islands[0] } })
        } },
        PluginService: {
            availablePlugins: { weather: { island: {} } },
            isPluginLoaded: id => id === "weather"
        },
        SessionData: { doNotDisturb: dnd },
        SettingsData: {
            islandPluginsBlocked: blocked,
            isAppDndBypassed: (app, entry) => bypass.indexOf(app) !== -1 || bypass.indexOf(entry) !== -1,
            notificationDndAllowCritical: allowCritical
        }
    });
    context.root = context;
    for (const name of ["shown", "interrupted", "resumed", "dropped", "action"])
        context[name] = (...args) => signals.push([name, ...args]);
    for (const match of source.matchAll(/^ {4}function (\w+)\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^ {4}\}/gm))
        vm.runInContext(match[0].replace(/\): \w+ \{/, ") {"), context); // QML return types are no JavaScript
    // The Connections handlers, run as Qt runs them: a blocked plugin's activities dropped, an unloaded plugin's surfaces.
    const handler = source.match(/^ {8}function onIslandPluginsBlockedChanged\(\) \{\n[\s\S]*?^ {8}\}/m);
    vm.runInContext(handler[0].replace("onIslandPluginsBlockedChanged", "blockedChanged"), context);
    vm.runInContext(source.match(/^ {8}function onPluginUnloaded\(pluginId\) \{\n[\s\S]*?^ {8}\}/m)[0], context);
    return { context, signals, blocked };
}

test("a script asking again replaces its own activity, and only its own", () => {
    const { context, signals } = service();
    const first = context.requestScript("backup", { "data": { "title": "Backup" } });
    const other = context.requestScript("sync", { "data": { "title": "Sync" } });
    assert.match(first, /^script:backup:\d+$/);
    const second = context.requestScript("backup", { "data": { "title": "Backup, again" } });
    assert.notEqual(second, first);
    assert.equal(context.entry(first), null, "the first token is gone");
    assert.deepEqual(signals.filter(s => s[0] === "dropped"), [["dropped", first, "replaced"]]);
    assert.equal(context.entry(other).pluginId, "script:sync", "the other script keeps its activity");
});

test("live scripts are counted by their prefix, never a plugin's", () => {
    const { context } = service();
    // The plugin first: counted among scripts, it would refuse the eighth.
    assert.match(context.request("weather", {}), /^weather:/);
    for (const name of ["a", "b", "c", "d", "e", "f", "g", "h"])
        assert.match(context.requestScript(name, {}), /^script:/, `script ${name}: a plugin does not count among scripts`);
    assert.equal(context.requestScript("i", {}), "ISLAND_ACTIVITY_TOO_MANY");
});

test("no island on the asked screen, or none at all, refuses", () => {
    assert.equal(service().context.requestScript("x", { "screen": "HDMI-A-1" }), "ISLAND_ACTIVITY_NO_ISLAND");
    assert.equal(service({ islands: [] }).context.requestScript("x", {}), "ISLAND_ACTIVITY_NO_ISLAND");
    assert.equal(service().context.request("unknown-plugin", {}), "", "a plugin that is not loaded is refused");
});

test("do not disturb holds an alert unless the user lets it through", () => {
    const alert = { "kind": "alert", "data": { "title": "Rain" } };
    let { context } = service({ dnd: true });
    context.request("weather", alert);
    assert.equal(context.nextFor("DP-1"), null);
    ({ context } = service({ dnd: true, allowCritical: true }));
    assert.equal(context.request("weather", alert), context.nextFor("DP-1").token, "as critical notifications may pass");
    ({ context } = service({ dnd: true, bypass: ["script:backup"] }));
    const token = context.requestScript("backup", { "data": { "title": "Backup" } });
    assert.equal(context.nextFor("DP-1").token, token, "a bypass rule on the script lets it through");
});

test("blocking a plugin drops its activities, and the shown one says so", () => {
    const { context, signals, blocked } = service();
    const token = context.request("weather", { "data": { "title": "Rain" } });
    context.markShown(token, "DP-1");
    assert.deepEqual(signals.at(-1), ["shown", token]);
    blocked.push("weather");
    context.blockedChanged();
    assert.equal(context.entry(token), null);
    assert.deepEqual(signals.at(-1), ["dropped", token, "disabled"]);
    assert.equal(context.request("weather", {}), "", "and it may not ask again");
});

test("a blocked plugin gives no system face; unblocked, the user's pick is back", () => {
    const { context, blocked } = service();
    context.PluginService.availablePlugins.weather.island.systemFaces = ["volume"];
    context.islandSystemComponents.weather = {};
    context.SettingsData.islandSystemFaces = { "volume": "weather" };
    assert.equal(context.systemFaceFor("volume").pluginId, "weather");
    assert.equal(context.systemFaceFor("brightness"), null, "a kind it was not picked for");
    blocked.push("weather");
    assert.equal(context.systemFaceFor("volume"), null, "the shell's face stands in");
    blocked.pop();
    assert.equal(context.systemFaceFor("volume").pluginId, "weather");
});

test("a load hands a plugin its island surfaces, and its unload drops its activities and destroys only those", () => {
    const { context } = service();
    const destroyed = [];
    const comp = name => ({ name, destroy() { destroyed.push(name); } });
    context.setComponents("weather", { "island": comp("island"), "islandSystem": comp("system"), "widget": comp("widget") });
    assert.equal(context.islandComponents.weather.name, "island");
    assert.equal(context.islandSystemComponents.weather.name, "system");
    const token = context.request("weather", { "data": { "title": "Rain" } });
    context.onPluginUnloaded("weather");
    assert.equal(context.entry(token), null);
    assert.equal(context.islandComponents.weather, undefined);
    assert.equal(context.islandSystemComponents.weather, undefined);
    assert.deepEqual(destroyed, ["island", "system"], "PluginService destroys its own surfaces");
    assert.equal(context.request("weather", {}), "", "no island surface any more");
});

test("a chosen action is kept for the status a script reads, and an unknown token or empty action changes nothing", () => {
    const { context, signals } = service();
    const token = context.requestScript("backup", { "data": { "title": "Backup", "actions": [{ "id": "stop", "label": "Stop" }] } });
    assert.equal(context.entry(token).lastAction, "");
    context.trigger(token, "stop");
    assert.equal(context.entry(token).lastAction, "stop");
    assert.deepEqual(signals.at(-1), ["action", token, "stop"]);
    context.trigger(token, "");
    context.trigger("script:other:9", "stop");
    assert.equal(signals.filter(s => s[0] === "action").length, 1);
    assert.equal(context.entry(token).lastAction, "stop");
});

test("on two islands, one going away leaves the activity on the other; the last one going drops it", () => {
    const { context, signals } = service({ islands: ["DP-1", "HDMI-A-1"] });
    const token = context.requestScript("backup", { "screen": "*", "data": { "title": "Backup" } });
    assert.deepEqual(Array.from(context.entry(token).hosts), ["DP-1", "HDMI-A-1"]);
    context.markShown(token, "DP-1");
    context.markShown(token, "HDMI-A-1");
    context.removeHost("HDMI-A-1");
    assert.deepEqual(Array.from(context.entry(token).hosts), ["DP-1"]);
    assert.equal(context.entry(token).state, "shown", "still shown on the island left");
    context.removeHost("DP-1");
    assert.equal(context.entry(token), null);
    assert.deepEqual(signals.at(-1), ["dropped", token, "unavailable"]);
});

test("a hand-edited island setting of the wrong type keeps its value instead of breaking the service", () => {
    const SPEC = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC;
    const blocked = ["weather"], faces = { "volume": "weather" };
    assert.deepEqual([null, {}, "weather", blocked].map(v => SPEC.islandPluginsBlocked.coerce(v)), [undefined, undefined, undefined, blocked]);
    assert.deepEqual([null, [], "weather", faces].map(v => SPEC.islandSystemFaces.coerce(v)), [undefined, undefined, undefined, faces]);
});

test("do not disturb turned on while an activity waits holds it, and turned off lets it show", () => {
    const { context } = service();
    const token = context.request("weather", { "kind": "alert", "data": { "title": "Rain" } });
    assert.equal(context.nextFor("DP-1").token, token);
    context.SessionData.doNotDisturb = true;
    assert.equal(context.nextFor("DP-1"), null);
    context.SessionData.doNotDisturb = false;
    assert.equal(context.nextFor("DP-1").token, token);
});
