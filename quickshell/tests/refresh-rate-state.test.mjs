import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Services/RefreshRateService.qml", import.meta.url), "utf8");
const functions = [...source.matchAll(/^    function \w+\([^)]*\) \{[\s\S]*?^    \}/gm)].map(match => match[0]).join("\n");
const OutputModel = loadScript(new URL("../Common/OutputModel.js", import.meta.url));

function fixture(t, backend = "niri") {
    const dir = mkdtempSync(join(tmpdir(), "dms-refresh-test-"));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const path = join(dir, "restore.json");
    const output = {
        name: "eDP-1", make: "Panel", model: "High refresh", serial: "123", enabled: true,
        modes: [
            { id: "fast", width: 2560, height: 1600, refresh_rate: 240000, refresh: 240000 },
            { id: "slow", width: 2560, height: 1600, refresh_rate: 60000, refresh: 60000 }
        ],
        current_mode: 0
    };
    output.currentMode = output.modes[0];
    let succeed = true;
    let writes = 0;
    const commands = [];
    function apply(mode, callback) {
        commands.push(mode);
        if (succeed) {
            output.current_mode = output.modes.findIndex(m => mode === m.id || mode === OutputModel.formatNiriMode(m));
            assert.notEqual(output.current_mode, -1);
            output.currentMode = output.modes[output.current_mode];
        }
        callback?.(succeed);
    }
    function start(load = true) {
        const state = vm.createContext({
            OutputModel,
            SettingsData: {
                lowerDisplayRefreshRateOnBattery: true,
                displayPreviousRefreshModes: {},
                setDisplayPreviousRefreshModes(compositor, modes) {
                    this.displayPreviousRefreshModes[compositor] = modes;
                    // Declarative settings cannot persist the old implementation's writes.
                }
            },
            SessionData: { activeDisplayProfileModes: {} },
            CompositorService: { isNiri: backend === "niri", compositor: backend },
            NiriService: { outputs: { "eDP-1": output }, applyOutputConfig: (name, config, cb) => apply(config.mode, cb) },
            WlrOutputService: {
                wlrOutputAvailable: true, outputs: [output],
                applyConfiguration: (heads, cb) => apply(heads[0].modeId, cb)
            },
            batteryRefreshRateTarget: 60000, batteryRefreshRateTolerance: 1000,
            _previousRefreshModes: {}, _refreshModesLoaded: false, _lastAppliedTargets: {},
            syncDebounce: { restart() {} }, cascadeGuard: { restart() {} }, log: { info() {}, warn() {} },
            refreshModesFile: { setText(text) { writes++; writeFileSync(path, text); } }
        });
        state.root = state;
        vm.runInContext(functions, state);
        if (load) {
            let text = "";
            try { text = readFileSync(path, "utf8"); } catch (error) { if (error.code !== "ENOENT") throw error; }
            state.loadPreviousRefreshModes?.(text);
        }
        return state;
    }
    return { start, path, output, commands, writes: () => writes, failApply: () => { succeed = false; } };
}

for (const backend of ["niri", "wlr"]) {
    test(`${backend}: restore after shell restart without writable settings, then clear runtime state`, t => {
        const f = fixture(t, backend);
        let state = f.start();
        state.syncRefreshRates(false, "power-change");
        assert.equal(f.output.currentMode.refresh_rate, 60000);
        state = f.start();
        state.syncRefreshRates(true, "resume-reconcile");
        assert.equal(f.output.currentMode.refresh_rate, 240000);
        assert.deepEqual(JSON.parse(readFileSync(f.path, "utf8")), {});
    });

    test(`${backend}: failed restore retains runtime state for next shell instance`, t => {
        const f = fixture(t, backend);
        f.start().syncRefreshRates(false, "power-change");
        f.failApply();
        f.start().syncRefreshRates(true, "resume-reconcile");
        assert.equal(f.start().findPreviousRefreshMode("eDP-1", f.output), "2560x1600@240.000");
    });
}

test("wait for initial runtime read before changing modes", t => {
    const f = fixture(t);
    const state = f.start(false);
    state.syncRefreshRates(false, "startup");
    assert.equal(f.commands.length, 0);
    state.loadPreviousRefreshModes("");
    state.syncRefreshRates(false, "restore-state-loaded");
    assert.equal(f.output.currentMode.refresh_rate, 60000);
});

test("invalid runtime JSON is recoverable and unchanged mode backups do not rewrite it", t => {
    const f = fixture(t);
    for (const text of ["{broken", "null", "[]", "42"]) {
        writeFileSync(f.path, text);
        const state = f.start();
        assert.equal(state._refreshModesLoaded, true);
        state.storePreviousRefreshMode("eDP-1", f.output, f.output.modes[0]);
        const writes = f.writes();
        state.storePreviousRefreshMode("eDP-1", f.output, f.output.modes[0]);
        assert.equal(f.writes(), writes);
        assert.equal(f.start().findPreviousRefreshMode("eDP-1", f.output), "2560x1600@240.000");
    }
});

test("clearing restored output preserves other compositors and outputs", t => {
    const f = fixture(t);
    writeFileSync(f.path, JSON.stringify({ niri: { "DP-2": { mode: "1920x1080@144.000" } }, mango: { "DP-1": { mode: "1920x1080@120.000" } } }));
    const state = f.start();
    state.syncRefreshRates(false, "power-change");
    assert.equal(JSON.parse(readFileSync(f.path, "utf8")).niri["eDP-1"].mode, "2560x1600@240.000");
    state.syncRefreshRates(true, "power-change");
    assert.deepEqual(JSON.parse(readFileSync(f.path, "utf8")), {
        niri: { "DP-2": { mode: "1920x1080@144.000" } }, mango: { "DP-1": { mode: "1920x1080@120.000" } }
    });
});
