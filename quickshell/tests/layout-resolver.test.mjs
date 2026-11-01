import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const resolver = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/LayoutResolver.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), resolver);
const plain = value => JSON.parse(JSON.stringify(value));
const screens = [
    { name: "DP-1", model: "Panel", x: 0, y: 0, width: 1920, height: 1080, scale: 1 },
    { name: "DP-2", model: "Panel", x: 1920, y: 0, width: 1600, height: 900, scale: 1.25 }
];
const islandDefaults = { islandReserveThickness: 40, islandCompactThickness: 38, islandOuterGap: 4 };
const bar = (id, position = 0, values = {}) => ({ id, position, enabled: true, ...values });

function resolve(configs, options = {}, screen = screens[0]) {
    return resolver.resolveScreen(configs.map(config => ({
        config, wingSize: config.gothCornersEnabled ? 12 : 0, barThickness: 40, popupThickness: 40, islandThickness: resolver.islandThickness(config, islandDefaults),
        islandReserve: resolver.islandReserve(config, islandDefaults)
    })), screen, {
        screens, displayNameMode: "name", framePreferences: ["all"], effectiveFrameEnabled: false,
        effectiveConnected: false, frameThickness: 12, frameBarSize: 48, ...options
    });
}

test("island metrics clamp each setting and a default reservation follows the pill", () => {
    assert.deepEqual(plain(resolver.islandMetrics({}, islandDefaults)), { reserve: 42, compact: 38, gap: 4, thickness: 42 });
    assert.deepEqual(plain(resolver.islandMetrics({ islandCompactThickness: 60 }, islandDefaults)), { reserve: 64, compact: 60, gap: 4, thickness: 64 });
    assert.deepEqual(plain(resolver.islandMetrics({ islandReserveThickness: 500, islandCompactThickness: 1, islandOuterGap: -3 }, islandDefaults)), { reserve: 128, compact: 24, gap: 0, thickness: 128 });
    assert.equal(resolver.islandThickness({ islandReserveThickness: 30, islandCompactThickness: 60, islandOuterGap: 10 }, islandDefaults), 70);
    assert.deepEqual(plain(resolver.islandMetrics({ islandOuterGap: 10, islandNotch: true }, islandDefaults)), { reserve: 38, compact: 38, gap: 0, thickness: 40 });
    assert.deepEqual(plain(resolver.islandMetrics({ islandCompactThickness: 32, islandNotch: true }, islandDefaults)), { reserve: 32, compact: 32, gap: 0, thickness: 40 });
});

test("an island set to reserve less than its pill paints the full pill but reserves only what was set", () => {
    const island = bar("island", 0, { island: true, islandReserveThickness: 30 });
    const alone = resolve([island]);
    assert.deepEqual(plain([alone.instances[0].rowThickness, alone.instances[0].exclusiveZone, alone.edges.top.reservation]), [42, 30, 30]);
    const stacked = resolve([island, bar("below")]);
    assert.deepEqual(plain([stacked.instances[1].rowOffset, stacked.edges.top.reservation]), [42, 86]);
});

test("absent, empty, explicit and fallback assignments remain distinct", () => {
    for (const count of [1, 2]) {
        const live = screens.slice(0, count);
        const covers = config => resolver.coversScreen(config, screens[0], live, "name");
        assert.equal(covers({}), true);
        assert.equal(covers({ screenPreferences: [] }), false);
        assert.equal(covers({ screenPreferences: ["all"] }), true);
        assert.equal(covers({ screenPreferences: ["DP-2"] }), false);
        assert.equal(covers({ screenPreferences: [], showOnLastDisplay: true }), count === 1);
        assert.equal(covers({ screenPreferences: ["missing"], showOnLastDisplay: true }), count === 1);
        assert.equal(covers({ hideOnLastDisplay: true }), count !== 1);
        assert.equal(covers({ screenPreferences: ["DP-1"], hideOnLastDisplay: true }), count !== 1);
        assert.equal(covers({ screenPreferences: [], showOnLastDisplay: true, hideOnLastDisplay: true }), false);
    }
});

test("model assignments follow screen position and preserve connector matching", () => {
    assert.equal(resolver.screenModelIndex(screens[1], screens), 1);
    assert.equal(resolver.screenModelIndex(screens[1], [screens[1]]), -1);
    for (const [preferences, mode, expected] of [
        [["Panel-1"], "model", true], [["Panel"], "model", false], [["Panel"], "name", true],
        [[{ model: "Panel", modelIndex: 1 }], "model", true], [[{ model: "Panel", modelIndex: 0 }], "model", false],
        [[{ name: "DP-2" }], "name", true], [["DP-2"], "model", true], [[], "model", false]
    ])
        assert.equal(resolver.screenMatches(screens[1], preferences, screens, mode), expected);
    const moved = [{ ...screens[0], x: 1920 }, { ...screens[1], x: 0 }];
    assert.equal(resolver.screenModelIndex(moved[1], moved), 0);
});

test("mixed configs coexist in config order on a horizontal and a vertical edge in every frame mode", () => {
    for (const position of [0, 2])
        for (const [effectiveFrameEnabled, effectiveConnected] of [[false, false], [true, false], [true, true]]) {
            const configs = ["z", "a", "m", "b"].map((id, index) => bar(id, position, { island: index % 2 === 1, innerPadding: index * 2 }));
            const layout = resolve(configs, { effectiveFrameEnabled, effectiveConnected });
            assert.deepEqual(plain(layout.instances.map(instance => instance.barId)), configs.map(config => config.id));
            let offset = 0;
            for (const instance of layout.instances) {
                assert.equal(instance.rowOffset, offset);
                offset += instance.rowThickness;
                assert.equal(instance.kind, configs[instance.configOrder].island ? "island" : effectiveFrameEnabled && effectiveConnected ? "frame" : "bar");
            }
            const band = layout.edges[["top", "bottom", "left", "right"][position]];
            assert.equal(band.occupancy, offset);
            assert.equal(band.reservation, offset);
            if (layout.manualPlacement) {
                const owned = layout.instances.reduce((sum, instance) => sum + instance.exclusionSize, 0);
                assert.equal(owned + (effectiveFrameEnabled ? band.reservation : 0), offset);
                assert.equal(layout.instances.every(instance => instance.exclusiveZone === -1), true);
            }
        }
});

test("row identity and occupancy stay fixed through reveal, floating and expansion", () => {
    const configs = [bar("z", 0, { autoHide: true }), bar("a", 0, { island: true, islandFloating: true }), bar("m")];
    const before = resolve(configs);
    const after = resolve(configs.map(config => ({ ...config, expanded: true, revealed: true })));
    assert.deepEqual(plain(after.instances), plain(before.instances));
    assert.deepEqual(plain(before.instances.map(instance => instance.reservation)), [0, 0, 130]);
    assert.equal(before.edges.top.reservation, 130);
    assert.equal(before.instances[0].exclusionSize, 130);
    assert.equal(before.edges.top.occupancy, 130);
    const resized = resolve(configs, {}, { ...screens[0], scale: 1.5, width: 1280 });
    assert.deepEqual(plain(before.instances.map(instance => instance.key)), plain(resized.instances.map(instance => instance.key)));
});

test("disabled and unassigned instances disappear; hidden bars keep row identity", () => {
    const layout = resolve([bar("disabled", 0, { enabled: false }), bar("missing", 0, { screenPreferences: [] }), bar("hidden", 0, { visible: false }), bar("visible")]);
    assert.deepEqual(plain(layout.instances.map(instance => instance.barId)), ["hidden", "visible"]);
    assert.deepEqual(plain(layout.instances.map(instance => instance.reservation)), [0, 88]);
});

test("accumulated clearance includes all islands and bars exactly once", () => {
    const configs = [bar("a", 0, { spacing: 2 }), bar("b", 0, { spacing: 10 }), bar("left", 2), bar("island", 0, { island: true })];
    const layout = resolve(configs);
    assert.equal(resolver.adjacentInfo(layout, configs[2], configs[0]).topBar, 46 + 60 + 42);
    assert.equal(resolver.adjacentInfo(layout, { autoHide: true }, configs[0]).topBar, 0);
    assert.equal(layout.instances.find(instance => instance.barId === "left").margins.top, 134);
    assert.equal(resolver.barBounds(layout, 40, 0, configs[1], configs[0], false, 0).y, 42);
    assert.equal(resolver.barBounds(layout, 40, 2, configs[2], configs[0], false, 0).y, 134);
});

test("frame overlays reserve once and every row retains its position", () => {
    const configs = [bar("hosted"), bar("island", 0, { island: true }), bar("overlay", 0, { useOverlayLayer: true })];
    const layout = resolve(configs, { effectiveFrameEnabled: true, effectiveConnected: true });
    assert.deepEqual(plain(layout.instances.map(instance => instance.kind)), ["frame", "island", "bar"]);
    assert.deepEqual(plain(layout.instances.map(instance => instance.rowOffset)), [0, 48, 90]);
    assert.equal(layout.edges.top.reservation, 138);
    assert.equal(layout.edges.top.frameExclusionEnabled, true);
    assert.equal(layout.instances.reduce((sum, instance) => sum + instance.exclusionSize, 0), 0);
    assert.equal(resolve(configs, { effectiveFrameEnabled: true, effectiveConnected: true, framePreferences: [] }).instances[0].kind, "bar");
});

test("a hidden bar collapses its frame band to a reserved gutter outside the overview", () => {
    for (const effectiveConnected of [false, true]) {
        const options = { effectiveFrameEnabled: true, effectiveConnected };
        const shown = resolve([bar("main")], options).edges.top;
        const hidden = resolve([bar("main", 0, { visible: false })], options).edges.top;
        assert.deepEqual([shown.frameReservation, shown.overviewFrameReservation], [48, 48]);
        assert.deepEqual([hidden.frameReservation, hidden.frameExclusionEnabled, hidden.overviewFrameReservation], [12, true, 48]);
    }
});

test("popup triggers preserve each edge and connected gap policy", () => {
    const config = { bottomGap: 8, popupGapsAuto: false, popupGapsManual: 6 };
    const expected = [{ x: 20, y: 58, width: 24 }, { x: 20, y: 1022, width: 24 }, { x: 50, y: 30, width: 24 }, { x: 1870, y: 30, width: 24 }];
    for (let position = 0; position < 4; position++)
        assert.deepEqual(plain(resolver.popupTrigger({ x: 20, y: 30 }, screens[0], 40, 24, 4, position, config, null, false)), expected[position]);
    assert.equal(resolver.popupTrigger({ x: 20, y: 30 }, screens[0], 40, 24, 4, 0, config, null, true).y, 40);
});

test("painted wings keep rows apart and only the final wing extends past reservation", () => {
    const layout = resolve([bar("outer", 0, { gothCornersEnabled: true }), bar("inner", 0, { gothCornersEnabled: true })]);
    assert.deepEqual(plain(layout.instances.map(instance => instance.rowOffset)), [0, 56]);
    assert.equal(layout.edges.top.reservation, 100);
    assert.equal(layout.edges.top.occupancy, 112);
    assert.equal(layout.instances[0].paintedBounds.y + layout.instances[0].paintedBounds.height, layout.instances[1].paintedBounds.y);
});

test("surface origins include native cross-edge exclusions without adding manual margins twice", () => {
    const layout = resolve([bar("top"), bar("bottom", 1), bar("left", 2), bar("right", 3)]);
    assert.deepEqual(plain(resolver.surfaceOrigin(layout, 44, 992, { left: true, top: true, bottom: true }, {})), { x: 0, y: 44 });
    assert.deepEqual(plain(resolver.surfaceOrigin(layout, 1832, 44, { left: true, right: true, bottom: true }, {})), { x: 44, y: 1036 });
    assert.deepEqual(plain(resolver.surfaceOrigin(layout, 44, 992, { right: true, top: true, bottom: true }, { top: 44, bottom: 44, right: 44 })), { x: 1832, y: 44 });
    const frameIsland = resolve([bar("island", 0, { island: true })], { effectiveFrameEnabled: true });
    assert.equal(frameIsland.instances[0].rowOffset, 12);
    assert.equal(frameIsland.edges.top.reservation, 54);
});

test("an overview-only bar shares the row of a same-edge bar that retracts for the overview", () => {
    const main = bar("main");
    const standIn = bar("standin", 0, { visible: false, openOnOverview: true });
    const always = bar("always", 0, { openOnOverview: true });
    const offsets = layout => Object.fromEntries(layout.instances.map(instance => [instance.barId, instance.rowOffset]));
    const shared = resolve([main, standIn]);
    assert.deepEqual(offsets(shared), { main: 0, standin: 0 });
    assert.equal(shared.instances.find(instance => instance.barId === "standin").margins.top, 0);
    assert.equal(shared.edges.top.occupancy, 44);
    assert.equal(shared.edges.top.reservation, 44);
    assert.deepEqual(offsets(resolve([standIn, main])), { standin: 0, main: 0 });
    assert.deepEqual(offsets(resolve([main, always, standIn])), { main: 0, always: 44, standin: 0 });
    assert.deepEqual(offsets(resolve([always, standIn])), { always: 0, standin: 44 });
    assert.deepEqual(offsets(resolve([main, standIn], { effectiveFrameEnabled: true })), { main: 0, standin: 48 });
});

test("free islands and dots keep their key but leave every band, reservation and shadow untouched", () => {
    const configs = [bar("top"), bar("dot", 0, { dot: true }), bar("edge", 1, { island: true }), bar("free", 0, { island: true, islandFloating: true, islandPlacement: "free" })];
    for (const options of [{}, { effectiveFrameEnabled: true }, { effectiveFrameEnabled: true, effectiveConnected: true }]) {
        const layout = resolve(configs, options);
        const dot = layout.instances.find(instance => instance.barId === "dot");
        assert.deepEqual(plain({ ...dot, paintedBounds: undefined, margins: undefined }), { key: JSON.stringify(["DP-1", "dot"]), screenName: "DP-1", barId: "dot", configOrder: 1, edge: "", kind: "island", free: true, dot: true, hostsIsland: true, satelliteEdge: "", row: 0, rowThickness: 0, rowOffset: 0, reservation: 0, manualPlacement: false, exclusiveZone: -1, exclusionSize: 0 });
        assert.equal(layout.instances.find(instance => instance.barId === "free").dot, false);
        assert.equal(layout.edges.top.island, null);
        assert.equal(layout.edges.top.islandThickness, 0);
        assert.equal(layout.edges.top.occupancy, resolve([configs[0]], options).edges.top.occupancy);
        assert.equal(layout.edges.bottom.island.id, "edge");
        assert.equal(layout.manualPlacement, false);
        assert.equal(layout.islands.length, 3);
    }
    const layout = resolve(configs);
    assert.deepEqual(plain(layout.instances.filter(instance => instance.free).map(instance => instance.barId)), ["dot", "free"]);
    assert.equal(resolver.adjacentInfo(layout, configs[0], configs[0]).topBar, 0);
});

test("a free island keeps a bar window for its satellites on its edge without reserving or shadowing it", () => {
    const top = bar("top");
    const free = values => bar("free", 1, { island: true, islandFloating: true, islandPlacement: "free", ...values });
    for (const options of [{}, { effectiveFrameEnabled: true }, { effectiveFrameEnabled: true, effectiveConnected: true }]) {
        const baseline = resolve([top], options);
        const layout = resolve([top, free({}), bar("dot", 1, { dot: true })], options);
        const instance = layout.instances.find(instance => instance.barId === "free");
        assert.equal(instance.satelliteEdge, "bottom");
        assert.equal(instance.edge, "");
        assert.equal(instance.reservation, 0);
        assert.equal(instance.exclusiveZone, -1);
        assert.equal(resolver.hostsBarWindow(instance), true);
        assert.equal(resolver.hostsBarWindow(layout.instances.find(instance => instance.barId === "dot")), false);
        assert.equal(layout.edges.bottom.island, null);
        assert.equal(layout.edges.bottom.islandThickness, 0);
        assert.deepEqual(plain(layout.edges), plain(resolve([top, bar("dot", 1, { dot: true })], options).edges));
        assert.equal(layout.edges.top.occupancy, baseline.edges.top.occupancy);
        assert.equal(layout.manualPlacement, false);
        const off = resolve([top, free({ islandSatellitesEnabled: false })], options).instances.find(instance => instance.barId === "free");
        assert.equal(resolver.hostsBarWindow(off), false);
    }
});

test("a bar hosting the island widget keeps its band and joins the islands without owning an edge", () => {
    const strip = value => JSON.parse(JSON.stringify(value, (key, entry) => key === "hostsIsland" || key === "centerWidgets" ? undefined : entry));
    const hosted = (id, position = 0, values = {}) => bar(id, position, { centerWidgets: ["clock", { id: "island", enabled: true }], ...values });
    for (const options of [{}, { effectiveFrameEnabled: true }, { effectiveFrameEnabled: true, effectiveConnected: true }]) {
        const baseline = resolve([bar("main"), bar("side", 2)], options);
        const layout = resolve([hosted("main"), bar("side", 2)], options);
        assert.deepEqual(strip(layout.instances), strip(baseline.instances));
        assert.deepEqual(strip(layout.edges), strip(baseline.edges));
        const main = layout.instances.find(instance => instance.barId === "main");
        assert.equal(main.hostsIsland, true);
        assert.equal(main.kind, options.effectiveConnected ? "frame" : "bar");
        assert.equal(layout.instances.find(instance => instance.barId === "side").hostsIsland, false);
        assert.deepEqual(plain(layout.islands.map(input => input.config.id)), ["main"]);
        assert.equal(layout.edges.top.island, null);
        assert.equal(layout.edges.top.islandThickness, 0);
        assert.deepEqual(plain(layout.bars.map(input => input.config.id)), ["main", "side"]);
    }
    for (const list of ["leftWidgets", "rightWidgets"])
        assert.equal(resolve([bar("main", 0, { [list]: ["island"] })]).instances[0].hostsIsland, true, list + " hosts the island too");
    assert.equal(resolve([bar("main", 0, { centerWidgets: [{ id: "island", enabled: false }] })]).instances[0].hostsIsland, false, "a disabled island widget hosts nothing");
    const two = resolve([hosted("first"), hosted("second", 1), bar("dot", 0, { dot: true })]);
    assert.deepEqual(plain(two.instances.map(instance => [instance.barId, instance.hostsIsland])), [["first", true], ["second", false], ["dot", true]]);
    assert.deepEqual(plain(two.islands.map(input => input.config.id)), ["dot", "first"]);
    const bypassed = resolve([hosted("host"), bar("island", 1, { island: true })]);
    assert.deepEqual(plain(bypassed.instances.map(instance => [instance.barId, instance.hostsIsland])), [["host", false], ["island", true]], "an island-layout bar on the screen wins over a hosted island");
    const overlay = resolve([hosted("overlay", 0, { useOverlayLayer: true })], { effectiveFrameEnabled: true, effectiveConnected: true });
    assert.equal(overlay.instances[0].kind, "bar");
    assert.equal(overlay.instances[0].hostsIsland, true);
});
