import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Services/ActionCatalogService.qml", import.meta.url), "utf8");
const ActionCatalog = loadScript(new URL("../Common/ActionCatalog.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

function service() {
    const toasts = [];
    const warnings = [];
    const context = vm.createContext({
        ActionCatalog,
        ToastService: { showInfo: message => toasts.push(["info", message]), showError: (title, details) => toasts.push(["error", title, details]) },
        log: { warn: (...args) => warnings.push(args.join(" ")), error: (...args) => warnings.push(args.join(" ")) },
        items: [], revision: 0, _appliedKey: "", _catalogKey: "k1", _itemList: [], _pluginDefs: {}, _defById: {}, _terms: { "Dark mode": "Koyu mod" },
        _ctxObject: { tr: t => t }
    });
    vm.runInContext("var I18n = { tr: t => t }; String.prototype.arg = function(value) { return this.replace('%1', value); };", context);
    context.root = context;
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\) \{\n[\s\S]*?^    \}/gm))
        vm.runInContext(match[0], context);
    context.toasts = toasts;
    context.warnings = warnings;
    return context;
}

const action = (id, extra = {}) => Object.assign({ id, title: "Lamp " + id, text: "Turn the lamp " + id + " in the living room.", run: () => {} }, extra);

function expose(context, defs) {
    context._pluginDefs = Object.assign({}, context._pluginDefs);
    context._defById = Object.fromEntries(defs.map(d => [d.id, d]));
    context.items = defs.map(d => plain(ActionCatalog.toItem(d, t => t)));
}

test("registering replaces the plugin's earlier actions and reports bad entries", () => {
    const s = service();
    let outcome = plain(s.registerPluginActions("home", [action("on"), action("off"), { id: "broken" }]));
    assert.equal(outcome.registered, 2);
    assert.equal(outcome.errors.length, 1);
    assert.equal(s.warnings.length, 1);
    assert.deepEqual(Object.keys(s._pluginDefs), ["home"]);

    outcome = plain(s.registerPluginActions("home", [action("dim")]));
    assert.deepEqual(plain(s._pluginDefs.home.map(d => d.id)), ["plugin:home:dim"]);

    s.registerPluginActions("garden", [action("water")]);
    s.registerPluginActions("home", []);
    assert.deepEqual(Object.keys(s._pluginDefs), ["garden"], "an empty list removes the plugin");
});

test("every registration produces a fresh map so bindings re-evaluate", () => {
    const s = service();
    const before = s._pluginDefs;
    s.registerPluginActions("home", [action("on")]);
    const afterRegister = s._pluginDefs;
    s.unregisterPluginActions("home");
    assert.notEqual(afterRegister, before);
    assert.notEqual(s._pluginDefs, afterRegister);
    assert.deepEqual(Object.keys(s._pluginDefs), []);
    const untouched = s._pluginDefs;
    s.unregisterPluginActions("never-registered");
    assert.equal(s._pluginDefs, untouched);
});

test("unloading a plugin removes its actions", () => {
    const s = service();
    s.registerPluginActions("home", [action("on")]);
    s.registerPluginActions("garden", [action("water")]);
    const handler = /target: PluginService\s*\n\s*function onPluginUnloaded\(pluginId\) \{\n([\s\S]*?)\n        \}/.exec(source);
    assert.ok(handler, "the service must listen to PluginService.pluginUnloaded");
    vm.runInContext("function onPluginUnloaded(pluginId) {" + handler[1] + "}", s);
    s.onPluginUnloaded("home");
    assert.deepEqual(Object.keys(s._pluginDefs), ["garden"]);
});

test("revision moves only when the catalog key changes", () => {
    const s = service();
    s._itemList = [{ id: "a" }];
    s._sync();
    assert.equal(s.revision, 1);
    assert.deepEqual(plain(s.items), [{ id: "a" }]);
    s._itemList = [{ id: "a" }, { id: "b" }];
    s._sync();
    assert.equal(s.revision, 1, "same key, same revision");
    s._catalogKey = "k2";
    s._sync();
    assert.equal(s.revision, 2);
    assert.equal(s.items.length, 2);
});

test("execute runs the action, reports failures and never throws", () => {
    const s = service();
    const ran = [];
    s.registerPluginActions("home", [action("on", { run: (values, query) => ran.push([plain(values), query]) }), action("off", { run: () => false }), action("gone", { available: () => false })]);
    expose(s, s._pluginDefs.home);

    assert.equal(s.execute("nope", ""), false);
    assert.equal(s.execute("plugin:home:on", "lamba aç"), true);
    assert.deepEqual(ran, [[{}, "lamba aç"]]);
    assert.deepEqual(plain(s.toasts), [["info", "Lamp on"]]);

    s.toasts.length = 0;
    assert.equal(s.execute("plugin:home:off", ""), false);
    assert.equal(s.execute("plugin:home:gone", ""), false);
    assert.deepEqual(plain(s.toasts), [["error", "Lamp off", "Action failed"], ["error", "Lamp gone", "Not available"]]);

    s.toasts.length = 0;
    s._defById["plugin:home:on"].run = () => {
        throw new Error("kaboom");
    };
    assert.equal(s.execute("plugin:home:on", ""), false);
    assert.equal(s.warnings.length > 0, true);
    assert.equal(s.toasts[0][0], "error");
});

test("a missing value tells the user what to type", () => {
    const s = service();
    s.registerPluginActions("home", [action("dim", { params: [{ name: "percent", type: "percent", min: 0, max: 100, required: true, example: "30%" }] })]);
    expose(s, s._pluginDefs.home);
    assert.equal(s.execute("plugin:home:dim", "kıs"), false);
    assert.deepEqual(plain(s.toasts), [["error", "Lamp dim", "Add a value, for example 30%"]]);
    assert.equal(s.execute("plugin:home:dim", "%30"), true);
});

test("availability, state and the index list follow the actions", () => {
    const s = service();
    let hot = true;
    s.registerPluginActions("home", [action("on", { available: () => hot, state: () => "Living room" }), action("off")]);
    expose(s, s._pluginDefs.home);
    assert.equal(s.available("plugin:home:on"), true);
    assert.equal(s.available("missing"), false);
    assert.equal(s.stateText("plugin:home:on"), "Living room");
    assert.equal(s.stateText("missing"), "");
    assert.deepEqual(plain(s.indexItems().map(i => i.id)), ["plugin:home:on", "plugin:home:off"]);
    assert.deepEqual(plain(s.indexItems()[0].payload), { category: "plugin" });
    hot = false;
    assert.deepEqual(plain(s.indexItems().map(i => i.id)), ["plugin:home:off"], "unavailable actions are not offered to the search index");
    assert.equal(s.itemById("plugin:home:off").id, "plugin:home:off");
    assert.equal(s.itemById("x"), null);
});

test("titles come from the term table first, then the translation catalog", () => {
    const s = service();
    assert.equal(s._translate("Dark mode"), "Koyu mod");
    assert.equal(s._translate("Something else"), "Something else");
});
