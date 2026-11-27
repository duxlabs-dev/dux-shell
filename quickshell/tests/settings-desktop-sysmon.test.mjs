import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

const LEGACY = ["showCpu", "showCpuGraph", "showCpuTemp", "showGpuTemp", "gpuPciId", "showMemory", "showMemoryGraph", "showNetwork", "showNetworkGraph", "showDisk", "layoutMode"];

function migrate(instance, list = "desktopWidgetInstances") {
    return store.migrateToVersion({ configVersion: 45, [list]: [instance] }, 46)[list][0].config;
}

const cfg = (config) => ({ id: "a", widgetType: "systemMonitor", config });

test("an old default config lands on tiles with the same four metrics", () => {
    const config = migrate(cfg({ showHeader: true, transparency: 0.5, layoutMode: "auto" }));
    assert.deepEqual(JSON.parse(JSON.stringify(config.metrics)), [
        { device: "cpu", vals: ["usage", "temp"], graph: true, on: true },
        { device: "memory", vals: ["used"], graph: true, on: true },
        { device: "net", vals: ["down", "up"], graph: true, on: true },
        { device: "disk", vals: ["read", "write", "space"], graph: true, on: true }
    ]);
    assert.equal(config.layout, "tiles");
    assert.equal(config.style, "icon");
    assert.equal(config.transparency, 0.5);
    assert.deepEqual(Object.keys(config).filter(key => LEGACY.includes(key)), []);
});

test("switches off, list mode and a GPU keep their meaning", () => {
    const config = migrate(cfg({ showCpu: false, showCpuGraph: false, showCpuTemp: false, showMemory: false, showMemoryGraph: false,
        showNetwork: false, showNetworkGraph: false, showDisk: false, layoutMode: "list", gpuPciId: "1002:15bf", showGpuTemp: true }));
    assert.deepEqual(JSON.parse(JSON.stringify(config.metrics)), [
        { device: "cpu", vals: ["usage"], graph: false, on: false },
        { device: "memory", vals: ["used"], graph: false, on: false },
        { device: "net", vals: ["down", "up"], graph: false, on: false },
        { device: "disk", vals: ["read", "write", "space"], graph: true, on: false },
        { device: "gpu:1002:15bf", vals: ["temp"], graph: false, on: true }
    ]);
    assert.equal(config.layout, "list");
});

test("an instance that already has metrics is unchanged", () => {
    const config = { metrics: [{ device: "cpu", vals: ["clock"], graph: false, on: true }], layout: "bars", showCpu: false };
    assert.deepEqual(JSON.parse(JSON.stringify(migrate(cfg(config)))), config);
});

test("lock screen monitors migrate and other widgets are left alone", () => {
    assert.equal(migrate(cfg({}), "lockScreenWidgetInstances").layout, "tiles");
    const clock = { id: "c", widgetType: "desktopClock", config: { showCpu: true } };
    assert.deepEqual(JSON.parse(JSON.stringify(migrate(clock))), { showCpu: true });
});

test("the old Tiles background reads as the Tiles style", () => {
    const catalog = loadScript(new URL("../Services/SysmonCatalog.js", import.meta.url));
    const pick = (raw) => {
        const c = catalog.normalizeConfig(raw);
        return [c.background, c.barStyle, c.listStyle, c.textShadow];
    };
    assert.deepEqual(pick({ layout: "bars", background: "tiles" }), ["none", "tiles", "rows", false]);
    assert.deepEqual(pick({ layout: "list", background: "tiles", textShadow: true }), ["none", "brackets", "tiles", false]);
    assert.deepEqual(pick({ background: "tiles" }), ["none", "brackets", "rows", false]);
    assert.deepEqual(pick({ layout: "graphs", background: "tiles" }), ["card", "brackets", "rows", false]);
});

test("opacity counts only when a card or tiles are painted", () => {
    const catalog = loadScript(new URL("../Services/SysmonCatalog.js", import.meta.url));
    const uses = (raw) => catalog.usesOpacity(catalog.normalizeConfig(raw));
    assert.equal(uses({ layout: "bars" }), true);
    assert.equal(uses({ layout: "tiles", background: "none" }), true);
    assert.equal(uses({ layout: "bars", barStyle: "tiles", background: "none" }), true);
    assert.equal(uses({ layout: "list", listStyle: "tiles", background: "none" }), true);
    for (const layout of ["bars", "list", "graphs"])
        assert.equal(uses({ layout, background: "none" }), false);
});

const dash = (cards, dashOptions) => store.migrateToVersion({ configVersion: 47, dashCards: cards, dashOptions }, 48);
const plain = (value) => JSON.parse(JSON.stringify(value));
const placed = (id, instanceId, config) => ({ id, instanceId, w: 2, h: 1, config });
const old = ["cpu", "memory", "network", "disk", "sysmon"].map((id) => ({ id, w: 2, h: 1 }));
const tile = (device, vals, extra) => ({ layout: "tiles", style: "icon", graphInterval: 300, metrics: [Object.assign({ device, vals, graph: true, on: true }, extra)] });
const bars = (temp) => ({ layout: "bars", style: "icon", metrics: [{ device: "cpu", vals: temp ? ["usage", "temp"] : ["usage"], graph: false, on: true }, { device: "memory", vals: ["used"], graph: false, on: true }] });

test("dash cards become system monitor cards with the old defaults and options", () => {
    const clock = { id: "clock", w: 1, h: 1 };
    let result = plain(dash([clock].concat(old), { clock: { x: 1 }, cpu: { y: 1 }, sysmon: {} }));
    assert.deepEqual(result.dashCards, [clock,
        placed("sysmon", "cpu-1", tile("cpu", ["usage", "temp"])),
        placed("sysmon", "memory-2", tile("memory", ["used"])),
        placed("sysmon", "network-3", tile("net", ["down", "up"])),
        placed("sysmon", "disk-4", tile("disk", ["space"], { mount: "/" })),
        placed("sysmon", "sysmon-5", bars(true))]);
    assert.deepEqual(result.dashOptions, { clock: { x: 1 } });

    result = plain(dash(old, {
        cpu: { temperature: false, trend: false, tone: "tertiary" }, memory: { swap: true }, network: { trend: false },
        disk: { io: true, tone: "bogus" }, sysmon: { temperature: false, tone: "primary" }
    }));
    const expected = [tile("cpu", ["usage"]), tile("memory", ["used", "swap"]), tile("net", ["down", "up"]), tile("disk", ["space", "read"], { mount: "/" }), bars(false)];
    expected[0].metrics[0].graph = false;
    expected[0].tone = "tertiary";
    expected[2].metrics[0].graph = false;
    expected[4].tone = "primary";
    assert.deepEqual(result.dashCards.map((card) => card.config), expected);
});

test("a configured system monitor card and a second run are unchanged", () => {
    const configured = { id: "sysmon", instanceId: "a", w: 1, h: 1, config: { layout: "list" } };
    const once = plain(dash([configured].concat(old), { sysmon: { temperature: false } }));
    assert.deepEqual(once.dashCards[0], configured);
    assert.deepEqual(plain(store.migrateToVersion(Object.assign({}, once, { configVersion: 47 }), 48)).dashCards, once.dashCards);
});

const bar = (id, extra) => Object.assign({ id, enabled: true, overflowMode: "hide", background: "none" }, extra);
const sysmon = (extra) => Object.assign({ id: "sysmon", enabled: true, overflowMode: "hide", background: "none", popout: "processes" }, extra);
const one = (device, vals, extra) => ({ metrics: [Object.assign({ device, vals }, extra)] });
const widgets = (list, extra) => plain(store.migrateToVersion(Object.assign({ configVersion: 48, barConfigs: [{ id: "b", rightWidgets: list }] }, extra), 49).barConfigs[0].rightWidgets);

test("bar monitor widgets become sysmon widgets with their options and generic keys", () => {
    const defaults = ["cpuUsage", "memUsage", "diskUsage", "cpuTemp", "gpuTemp", "network_speed_monitor"].map((id) => bar(id, { minimumWidth: true }));
    assert.deepEqual(widgets(defaults), [
        sysmon(one("cpu", ["usage"])), sysmon(one("memory", ["used"])),
        sysmon(Object.assign(one("disk", ["space"], { mount: "/" }), { label: "both" })), sysmon(one("cpu", ["temp"])),
        sysmon({ selectedGpuIndex: 0 }), sysmon(one("net", ["down", "up"]))
    ]);
    assert.deepEqual(widgets([
        bar("memUsage", { showSwap: true, showInGb: true }), bar("diskUsage", { mountPath: "/home", showMountPath: false, diskUsageMode: 3 }),
        bar("gpuTemp", { pciId: "0000:01:00.0", selectedGpuIndex: 1 }), bar("gpuTemp", { pciId: "", selectedGpuIndex: 1 }),
        bar("network_speed_monitor", { compactMode: true, hideWhenIdle: true }), "cpuUsage"
    ]), [
        sysmon(one("memory", ["used", "swap"], { percent: false })),
        sysmon(Object.assign(one("disk", ["space"], { mount: "/home", diskMode: 3 }), { label: "icon" })),
        sysmon({ selectedGpuIndex: 1, pciId: "0000:01:00.0" }), sysmon({ selectedGpuIndex: 1 }),
        sysmon(one("net", ["down", "up"], { compact: true, hideIdle: true })),
        { id: "sysmon", enabled: true, popout: "processes", metrics: [{ device: "cpu", vals: ["usage"] }] }
    ]);
});

test("junk in old bar entries falls back to the old defaults", () => {
    assert.deepEqual(widgets([bar("gpuTemp", { pciId: 5, selectedGpuIndex: -2, device: "net", vals: ["x"], metrics: [] }), bar("gpuTemp", { pciId: "a\nb", selectedGpuIndex: 2 }), bar("diskUsage", { mountPath: "/a\nb" }), bar("diskUsage", { mountPath: "home" }), bar("memUsage", { showSwap: "yes" }), 7, null, { id: "clock" }]), [
        sysmon({ selectedGpuIndex: 0 }), sysmon({ selectedGpuIndex: 2 }), sysmon(Object.assign(one("disk", ["space"], { mount: "/" }), { label: "both" })), sysmon(Object.assign(one("disk", ["space"], { mount: "/" }), { label: "both" })),
        sysmon(one("memory", ["used"])), 7, null, { id: "clock" }
    ]);
});

test("island layouts and docks migrate too and a second run changes nothing", () => {
    const input = {
        configVersion: 48,
        barConfigs: [null, { id: "i", islandHomeLayout: [{ id: "cpuUsage", enabled: false }], leftWidgets: [{ id: "island", islandHomeLayout: ["memUsage"] }] }],
        dockConfigs: [{ id: "d", widgets: [{ id: "w1", widgetId: "cpuTemp", enabled: true }, { widgetId: "appsDock" }, "network_speed_monitor"] }]
    };
    const once = plain(store.migrateToVersion(input, 49));
    assert.deepEqual(once.barConfigs[1].islandHomeLayout, [{ id: "sysmon", enabled: false, popout: "processes", ...one("cpu", ["usage"]) }]);
    assert.deepEqual(once.barConfigs[1].leftWidgets[0].islandHomeLayout, [{ id: "sysmon", enabled: true, popout: "processes", ...one("memory", ["used"]) }]);
    assert.deepEqual(once.dockConfigs[0].widgets, [{ id: "w1", widgetId: "sysmon", enabled: true, popout: "processes", ...one("cpu", ["temp"]) }, { widgetId: "appsDock" }, { widgetId: "sysmon", enabled: true, popout: "processes", ...one("net", ["down", "up"]) }]);
    assert.deepEqual(plain(store.migrateToVersion(Object.assign({}, once, { configVersion: 48 }), 49)), once);
});

test("pending GPU widgets resolve to their own card once, twin cards included", () => {
    const twin = (busId) => ({ pciId: "10de:2684", busId });
    const gpus = [twin("0000:01:00.0"), twin("0000:02:00.0")];
    const entries = [bar("gpuTemp", { pciId: "10de:2684", selectedGpuIndex: 1 }), bar("gpuTemp", { pciId: "10de:2684", selectedGpuIndex: 0 }), bar("gpuTemp", { pciId: "1002:aaaa", selectedGpuIndex: 0 }), bar("gpuTemp", { selectedGpuIndex: 9 })];
    const settings = store.migrateToVersion({ configVersion: 48, barConfigs: [{ id: "b", rightWidgets: entries }], dockConfigs: [{ id: "d", widgets: [{ widgetId: "gpuTemp", selectedGpuIndex: 1 }] }] }, 49);
    assert.equal(store.resolveSysmonGpus(settings, []), false);
    assert.equal(store.resolveSysmonGpus(settings, gpus), true);
    const right = plain(settings.barConfigs[0].rightWidgets);
    assert.deepEqual(right.map((w) => w.metrics?.[0].device), ["gpu:0000:02:00.0", "gpu:0000:01:00.0", "gpu:1002:aaaa", "gpu:0000:01:00.0"]);
    assert.deepEqual([right[2].selectedGpuIndex, right[2].pciId], [undefined, undefined]);
    assert.equal(settings.dockConfigs[0].widgets[0].metrics[0].device, "gpu:0000:02:00.0");
    assert.equal(store.resolveSysmonGpus(settings, gpus), false);
});
