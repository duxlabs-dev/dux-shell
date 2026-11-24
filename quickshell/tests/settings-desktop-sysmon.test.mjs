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
