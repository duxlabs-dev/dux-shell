import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Services/PluginService.qml", import.meta.url), "utf8");

function createService({ availablePlugins, loadedPlugins, desktopWidgetInstances = [], failEnable = [] }) {
    const cache = { disabledPluginsSnapshot: [], disabledDesktopWidgetsSnapshot: [] };
    const calls = { disabled: [], enabled: [] };

    const context = vm.createContext({
        Array,
        Object,
        Set,
        availablePlugins,
        loadedPlugins,
        SettingsData: {
            desktopWidgetInstances,
            updateDesktopWidgetInstance(id, updates) {
                const inst = desktopWidgetInstances.find(item => item.id === id);
                if (inst)
                    Object.assign(inst, updates);
            }
        },
        CacheData: {
            get disabledPluginsSnapshot() {
                return cache.disabledPluginsSnapshot;
            },
            get disabledDesktopWidgetsSnapshot() {
                return cache.disabledDesktopWidgetsSnapshot;
            },
            set(key, value) {
                cache[key] = value;
            }
        },
        isPluginLoaded(id) {
            return context.loadedPlugins[id] !== undefined;
        },
        disablePlugin(id) {
            calls.disabled.push(id);
            delete context.loadedPlugins[id];
            return true;
        },
        enablePlugin(id, onResult) {
            calls.enabled.push(id);
            const ok = !failEnable.includes(id);
            if (ok)
                context.loadedPlugins[id] = context.availablePlugins[id];
            if (onResult)
                onResult(ok);
            return ok;
        }
    });

    for (const name of ["disableAllPlugins", "restoreDisabledPlugins"]) {
        const match = source.match(new RegExp(`^    function ${name}\\([^\\n]*\\)(?:: \\w+)? \\{\\n[\\s\\S]*?^    \\}`, "m"));
        assert.ok(match, `Missing ${name} in PluginService.qml`);
        vm.runInContext(match[0], context);
    }

    return { context, cache, calls };
}

test("disableAllPlugins snapshots all loaded plugins and restoreDisabledPlugins re-enables only them", () => {
    const availablePlugins = {
        alpha: { id: "alpha", surfaces: ["bar"] },
        beta: { id: "beta", surfaces: ["daemon"] },
        gamma: { id: "gamma", surfaces: ["bar"] },
        desktopOnly: { id: "desktopOnly", surfaces: ["desktop"] }
    };
    const loadedPlugins = {
        alpha: availablePlugins.alpha,
        beta: availablePlugins.beta,
        desktopOnly: availablePlugins.desktopOnly
    };
    const desktopWidgetInstances = [
        { id: "dw_desktop_1", widgetType: "desktopOnly", enabled: true },
        { id: "dw_desktop_off", widgetType: "desktopOnly", enabled: false },
        { id: "dw_builtin", widgetType: "desktopClock", enabled: true }
    ];
    const { context, cache, calls } = createService({ availablePlugins, loadedPlugins, desktopWidgetInstances });

    const disabled = Array.from(context.disableAllPlugins());
    assert.deepEqual(disabled.sort(), ["alpha", "beta", "desktopOnly"]);
    assert.deepEqual(calls.disabled.sort(), ["alpha", "beta", "desktopOnly"]);
    assert.deepEqual(Array.from(cache.disabledPluginsSnapshot).sort(), ["alpha", "beta", "desktopOnly"]);
    assert.deepEqual(Array.from(cache.disabledDesktopWidgetsSnapshot), ["dw_desktop_1"]);
    assert.equal(desktopWidgetInstances[0].enabled, false);
    assert.equal(desktopWidgetInstances[1].enabled, false);
    assert.equal(desktopWidgetInstances[2].enabled, true);
    assert.equal(context.isPluginLoaded("desktopOnly"), false);
    assert.equal(context.isPluginLoaded("gamma"), false);

    // Calling disableAllPlugins again with no loaded plugins keeps the existing snapshot.
    assert.deepEqual(Array.from(context.disableAllPlugins()), []);
    assert.deepEqual(Array.from(cache.disabledPluginsSnapshot).sort(), ["alpha", "beta", "desktopOnly"]);

    let failedResult = null;
    const restored = Array.from(context.restoreDisabledPlugins(failed => {
        failedResult = Array.from(failed);
    }));
    assert.deepEqual(restored.sort(), ["alpha", "beta", "desktopOnly"]);
    assert.deepEqual(calls.enabled.sort(), ["alpha", "beta", "desktopOnly"]);
    assert.deepEqual(failedResult, []);
    assert.deepEqual(Array.from(cache.disabledPluginsSnapshot), []);
    assert.deepEqual(Array.from(cache.disabledDesktopWidgetsSnapshot), []);
    assert.equal(desktopWidgetInstances[0].enabled, true);
    assert.equal(desktopWidgetInstances[1].enabled, false);
});

test("restoreDisabledPlugins reports failed plugins and keeps their desktop widget disabled", () => {
    const availablePlugins = {
        alpha: { id: "alpha", surfaces: ["bar"] },
        broken: { id: "broken", surfaces: ["desktop"] }
    };
    const loadedPlugins = {
        alpha: availablePlugins.alpha,
        broken: availablePlugins.broken
    };
    const desktopWidgetInstances = [
        { id: "dw_broken", widgetType: "broken", enabled: true }
    ];
    const { context, cache } = createService({ availablePlugins, loadedPlugins, desktopWidgetInstances, failEnable: ["broken"] });

    context.disableAllPlugins();
    let failedResult = null;
    context.restoreDisabledPlugins(failed => {
        failedResult = Array.from(failed);
    });
    assert.deepEqual(failedResult, ["broken"]);
    assert.deepEqual(Array.from(cache.disabledPluginsSnapshot), []);
    assert.equal(desktopWidgetInstances[0].enabled, false);
});
