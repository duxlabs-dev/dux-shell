import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Common/SettingsTabs.qml", import.meta.url), "utf8");

// Takes the text between the first opener after `from` and its matching closer, string literals skipped.
function balanced(from, open, close) {
    const start = source.indexOf(open, from);
    assert.notEqual(start, -1, `no ${open} after offset ${from}`);
    let depth = 0;
    let quote = "";
    for (let i = start; i < source.length; i++) {
        const ch = source[i];
        if (quote) {
            if (ch === "\\")
                i++;
            else if (ch === quote)
                quote = "";
            continue;
        }
        if (ch === '"' || ch === "'") {
            quote = ch;
            continue;
        }
        if (ch === open)
            depth++;
        else if (ch === close && --depth === 0)
            return source.slice(start, i + 1);
    }
    assert.fail(`no matching ${close}`);
}

function sliceFunction(name) {
    const at = source.indexOf(`function ${name}(`);
    assert.notEqual(at, -1, `function ${name} not found`);
    const block = balanced(at, "{", "}");
    return source.slice(at, source.indexOf("{", at) + block.length);
}

function sliceStructure() {
    const at = source.indexOf("readonly property var structure:");
    assert.notEqual(at, -1, "structure not found");
    return balanced(at, "[", "]");
}

function tabs(isNiri) {
    const context = vm.createContext({
        I18n: {
            tr: text => {
                const s = {
                    text,
                    arg: () => s
                };
                return s;
            }
        },
        CompositorService: {
            displayName: "niri",
            isNiri,
            isHyprland: false,
            isMango: false,
            supportsWindowRules: true,
            supportsLayoutConfig: true,
            supportsInputConfig: true,
            supportsPointerConfig: true
        },
        KeybindsService: { available: true },
        MultimediaService: { unavailable: false },
        NetworkService: { networkAvailable: true, cellularDevices: [] },
        CupsService: { cupsAvailable: true },
        DMSService: { isConnected: true, apiVersion: 30 },
        GreeterService: { available: true, ensureDetected: () => {} },
        DesktopService: { ensureProbed: () => {} },
        PluginService: { availablePluginsList: [] },
        SettingsUiState: { niriSection: "windows" }
    });
    for (const name of ["buildPageMap", "buildNormalizedIds", "normalizeId", "isPluginPage", "visibleLeaves", "isVisible", "redirectNiri", "resolvePage"])
        vm.runInContext(sliceFunction(name), context);
    vm.runInContext(`pluginPrefix = "plugin:"; structure = ${sliceStructure()}; pageMap = buildPageMap(structure); normalizedIds = buildNormalizedIds(pageMap);`, context);
    return context;
}

test("niri opens the niri page on the owning section instead of the merged tabs", () => {
    const context = tabs(true);
    assert.equal(context.resolvePage("keybinds"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "keybinds");
    assert.equal(context.resolvePage("keyboard"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "input");
    assert.equal(context.resolvePage("mouse_touchpad"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "input");
    assert.equal(context.resolvePage("window_rules"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "windows");
});

test("niri keeps the other pages on themselves and the section untouched", () => {
    const context = tabs(true);
    assert.equal(context.resolvePage("default_apps"), "default_apps");
    assert.equal(context.SettingsUiState.niriSection, "windows");
    assert.equal(context.resolvePage("niri"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "windows");
});

test("niri leaves no empty Input category in the menu", () => {
    const context = tabs(true);
    assert.equal(context.isVisible(context.pageMap["input"]), false);
    for (const id of ["keybinds", "keyboard", "mouse_touchpad"])
        assert.equal(context.isVisible(context.pageMap[id]), false, id);
    assert.equal(context.isVisible(context.pageMap["window_rules"]), false);
});

test("the niri page also answers for the emptied Input category", () => {
    const context = tabs(true);
    assert.equal(context.resolvePage("input"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "input");
});

test("without niri the merged tabs stay where they were", () => {
    const context = tabs(false);
    assert.equal(context.resolvePage("keybinds"), "keybinds");
    assert.equal(context.resolvePage("window_rules"), "window_rules");
    assert.equal(context.isVisible(context.pageMap["input"]), true);
    assert.equal(context.isVisible(context.pageMap["keybinds"]), true);
    assert.equal(context.SettingsUiState.niriSection, "windows");
});

test("niri hides the compositor layout tab and answers with the windows section", () => {
    const context = tabs(true);
    assert.equal(context.isVisible(context.pageMap["compositor_layout"]), false);
    assert.equal(context.resolvePage("compositor_layout"), "niri");
    assert.equal(context.SettingsUiState.niriSection, "windows");
});

test("without niri the compositor layout tab stays", () => {
    const context = tabs(false);
    assert.equal(context.isVisible(context.pageMap["compositor_layout"]), true);
    assert.equal(context.resolvePage("compositor_layout"), "compositor_layout");
});
