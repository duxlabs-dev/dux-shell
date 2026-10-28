import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const presets = loadScript(new URL("../Common/settings/DensityPresets.js", import.meta.url));
const Spec = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url));
const levels = ["spacious", "comfortable", "compact", "dense"];
const plain = value => JSON.parse(JSON.stringify(value));
const at = (surface, density, extra = {}) => Object.assign(plain(presets.values(surface, density)), extra);
const pairs = levels.flatMap(from => levels.filter(to => to !== from).map(to => [from, to]));

function bars(density) {
    return [
        Object.assign({ id: "default", position: 0 }, at("bar", density)),
        Object.assign({ id: "custom", position: 1 }, at("bar", density, { innerPadding: 11 })),
        Object.assign({ id: "island", island: true }, at("bar", density), at("island", density, { islandSatelliteGap: 30 })),
        Object.assign({ id: "former", position: 2 }, at("bar", density), at("island", density, { islandCompactThickness: 50 }))
    ];
}

test("untouched sizes take the new level, set ones stay, per instance", () => {
    for (const [from, to] of pairs) {
        const moved = plain(presets.transitionAll(bars(from), "bar", from, to));
        assert.deepEqual(moved, [
            Object.assign({ id: "default", position: 0 }, at("bar", to)),
            Object.assign({ id: "custom", position: 1 }, at("bar", to, { innerPadding: 11 })),
            Object.assign({ id: "island", island: true }, at("bar", to), at("island", to, { islandSatelliteGap: 30 })),
            Object.assign({ id: "former", position: 2 }, at("bar", to), at("island", to, { islandCompactThickness: 50 }))
        ], `${from} -> ${to}`);
        const docks = plain(presets.transitionAll([at("dock", from, { id: "a" }), at("dock", from, { id: "b", iconSize: 64 })], "dock", from, to));
        assert.deepEqual(docks, [at("dock", to, { id: "a" }), at("dock", to, { id: "b", iconSize: 64 })], `${from} -> ${to}`);
    }
});

test("a round trip restores every instance and a missing field counts as untouched", () => {
    for (const [from, to] of pairs) {
        const start = bars(from);
        assert.deepEqual(plain(presets.transitionAll(presets.transitionAll(start, "bar", from, to), "bar", to, from)), start, `${from} -> ${to} -> ${from}`);
    }
    assert.deepEqual(plain(presets.transition({ id: "old" }, "bar", "comfortable", "dense")), at("bar", "dense", { id: "old" }));
});

test("an unknown or unchanged level moves nothing", () => {
    for (const [from, to] of [["comfortable", "tiny"], ["tiny", "compact"], [undefined, "compact"], ["compact", "compact"]])
        assert.equal(presets.transitionAll(bars("compact"), "bar", from, to), null, `${from} -> ${to}`);
});

test("a dot bar takes island sizes and null entries are left alone", () => {
    for (const [from, to] of pairs) {
        const moved = plain(presets.transitionAll([null, Object.assign({ id: "dot", dot: true }, at("bar", from))], "bar", from, to));
        assert.deepEqual(moved, [null, Object.assign({ id: "dot", dot: true }, at("bar", to), at("island", to))], `${from} -> ${to}`);
        assert.deepEqual(plain(presets.transitionAll([at("dock", from, { id: "a" }), null], "dock", from, to)), [at("dock", to, { id: "a" }), null], `${from} -> ${to}`);
    }
});

test("a load fills the sizes a file leaves out from its density, and keeps the ones it has", () => {
    const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
    const pick = (config, surface) => Object.fromEntries(Object.keys(presets.PRESETS[surface]).map(key => [key, config[key]]));
    for (const density of levels) {
        const root = { settingsConfigVersion: 999 };
        store.parse(root, { configVersion: 999, density, dockConfigs: [{ id: "d" }, { id: "e", iconSize: 64 }] });
        assert.deepEqual(pick(root.barConfigs[0], "bar"), at("bar", density), density);
        assert.deepEqual([pick(root.dockConfigs[0], "dock"), root.dockConfigs[1].iconSize], [at("dock", density), 64], density);
        assert.deepEqual(pick(root, "frame"), at("frame", density), density);
        store.parse(root, { configVersion: 999, density });
        assert.deepEqual(pick(root.dockConfigs[0], "dock"), at("dock", density), density);
    }
});

test("a size set back to the comfortable value survives a save at any density", () => {
    const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
    const sized = ["barConfigs", "dockConfigs", "frameThickness", "frameBarSize"];
    for (const density of levels) {
        const file = { configVersion: 999, density };
        const root = { settingsConfigVersion: 999 };
        store.parse(root, file);
        const untouched = store.toJson(root, new Set(Object.keys(file)));
        assert.deepEqual(sized.filter(key => key in untouched), [], density);
        root.frameThickness = Spec.SPEC.frameThickness.def;
        root.frameBarSize = Spec.SPEC.frameBarSize.def;
        root.barConfigs = plain(Spec.SPEC.barConfigs.def);
        root.dockConfigs = plain(Spec.SPEC.dockConfigs.def);
        const expected = plain(sized.map(key => root[key]));
        const reloaded = { settingsConfigVersion: 999 };
        store.parse(reloaded, store.toJson(root, new Set(Object.keys(file))));
        assert.deepEqual(plain(sized.map(key => reloaded[key])), expected, density);
    }
});

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

test("a density change moves bars, docks and frame once, skipping managed and user-set values", () => {
    const settings = settingsFunctions(["applyDensityPresets", "isManaged"], vm.createContext({
        DensityPresets: presets,
        AdminPolicy: { lockSettings: { frameBarSize: 40 } },
        density: "comfortable",
        barConfigs: bars("comfortable"),
        dockConfigs: [at("dock", "comfortable", { id: "dock", spacing: 20 })],
        frameThickness: 16,
        frameBarSize: 40
    }));
    let saves = 0;
    Spec.set(settings, "density", "compact", () => saves++, { applyDensityPresets: settings.applyDensityPresets });
    assert.deepEqual(plain(settings.barConfigs), plain(presets.transitionAll(bars("comfortable"), "bar", "comfortable", "compact")));
    assert.deepEqual(plain(settings.dockConfigs), [at("dock", "compact", { id: "dock", spacing: 20 })]);
    assert.deepEqual([settings.frameThickness, settings.frameBarSize, saves], [12, 40, 1]);
});

test("an unknown previous level moves sizes from comfortable, the level Theme rendered", () => {
    for (const previous of ["Compact", "", undefined]) {
        const settings = settingsFunctions(["applyDensityPresets", "isManaged"], vm.createContext({
            DensityPresets: presets,
            AdminPolicy: { lockSettings: {} },
            density: previous,
            barConfigs: bars("comfortable"),
            dockConfigs: [at("dock", "comfortable", { id: "dock" })],
            frameThickness: 16,
            frameBarSize: 40
        }));
        Spec.set(settings, "density", "dense", () => {}, { applyDensityPresets: settings.applyDensityPresets });
        assert.deepEqual(plain(settings.barConfigs), plain(presets.transitionAll(bars("comfortable"), "bar", "comfortable", "dense")), String(previous));
        assert.deepEqual(plain(settings.dockConfigs), [at("dock", "dense", { id: "dock" })], String(previous));
        assert.deepEqual([settings.frameThickness, settings.frameBarSize], [8, 34], String(previous));
    }
});

test("resets land on the current level's preset", () => {
    const changes = [];
    const settings = settingsFunctions(["barConfigDefault", "dockConfigDefaults", "specDefault", "isDefault", "resetToDefault", "isManaged", "presetDefault"], vm.createContext({
        DensityPresets: presets,
        Store: loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url)),
        interfaceStyle: "expressive",
        DockConfig: loadScript(new URL("../Common/settings/DockConfig.js", import.meta.url)),
        SpecUtil: loadScript(new URL("../DCommon/Common/settings/SpecUtil.js", import.meta.url)),
        Spec: { SPEC: Spec.SPEC, set: (root, key, value) => changes.push([key, value]) },
        AdminPolicy: { lockSettings: {} },
        saveSettings() {},
        _hooks: {},
        density: "dense",
        frameThickness: 8
    }));
    assert.deepEqual([settings.barConfigDefault("innerPadding"), settings.barConfigDefault("spacing"), settings.dockConfigDefaults().iconSize, settings.dockConfigDefaults().margin], [-4, 4, 36, 8]);
    assert.equal(settings.isDefault(["frameThickness"]), true);
    settings.resetToDefault(["frameBarSize", "frameRounding"]);
    assert.deepEqual(changes, [["frameBarSize", 34], ["frameRounding", null]]);
});
