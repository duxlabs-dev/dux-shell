import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const Spec = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url));
const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
const presets = loadScript(new URL("../Common/settings/DensityPresets.js", import.meta.url));

function settingsFunctions(names, context) {
    const source = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
    context.root = context;
    for (const name of names) {
        const found = source.match(new RegExp(`^    function ${name}\\(([^)]*)\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
        assert.ok(found, name);
        vm.runInContext(found[0], context);
    }
    return context;
}

function settings(globals) {
    return settingsFunctions(["applyInterfaceStyle", "presetDefault", "isManaged", "updateCompositorLayout"], vm.createContext(Object.assign({
        Store: store,
        Spec,
        DensityPresets: presets,
        AdminPolicy: { lockSettings: {} },
        density: "comfortable",
        compositorLayoutRefreshNeeded() {}
    }, globals)));
}

test("a style change moves the corner style with it unless the user picked one", () => {
    const cases = [
        ["expressive", "classic", "scale", "fixed"],
        ["classic", "expressive", "fixed", "scale"],
        ["expressive", "classic", "fixed", "fixed"],
        ["classic", "expressive", "scale", "scale"]
    ];
    for (const [from, to, mode, expected] of cases) {
        const root = settings({ interfaceStyle: from, radiusMode: mode });
        Spec.set(root, "interfaceStyle", to, () => {}, { applyInterfaceStyle: root.applyInterfaceStyle });
        assert.equal(root.radiusMode, expected, `${from} -> ${to} at ${mode}`);
    }
    const managed = settings({ interfaceStyle: "expressive", radiusMode: "scale", AdminPolicy: { lockSettings: { radiusMode: "scale" } } });
    Spec.set(managed, "interfaceStyle", "classic", () => {}, { applyInterfaceStyle: managed.applyInterfaceStyle });
    assert.equal(managed.radiusMode, "scale");
});

test("a load fills a missing corner style from the file's interface style, and a save omits only that", () => {
    for (const [style, mode] of [["classic", "fixed"], ["expressive", "scale"]]) {
        const root = { settingsConfigVersion: 999 };
        store.parse(root, { configVersion: 999, interfaceStyle: style });
        assert.equal(root.radiusMode, mode, style);
        assert.equal("radiusMode" in store.toJson(root, new Set(["interfaceStyle"])), false, style);
        root.radiusMode = mode === "fixed" ? "scale" : "fixed";
        assert.equal(store.toJson(root, new Set(["interfaceStyle"])).radiusMode, root.radiusMode, style);
        const kept = { settingsConfigVersion: 999 };
        store.parse(kept, { configVersion: 999, interfaceStyle: style, radiusMode: root.radiusMode });
        assert.equal(kept.radiusMode, root.radiusMode, style);
    }
});

test("under classic the corner style's default, modified state and reset follow the style", () => {
    const changes = [];
    const root = settingsFunctions(["specDefault", "isDefault", "resetToDefault", "isManaged", "presetDefault"], vm.createContext({
        Store: store,
        DensityPresets: presets,
        SpecUtil: loadScript(new URL("../DCommon/Common/settings/SpecUtil.js", import.meta.url)),
        Spec: { SPEC: Spec.SPEC, set: (target, key, value) => { changes.push([key, value]); target[key] = value; } },
        AdminPolicy: { lockSettings: {} },
        saveSettings() {},
        _hooks: {},
        density: "comfortable",
        interfaceStyle: "classic",
        radiusMode: "scale"
    }));
    assert.equal(root.specDefault("radiusMode"), "fixed");
    assert.equal(root.isDefault(["radiusMode"]), false);
    root.resetToDefault(["radiusMode"]);
    assert.deepEqual(changes, [["radiusMode", "fixed"]]);
    assert.equal(root.isDefault(["radiusMode"]), true);
});
