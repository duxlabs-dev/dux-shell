import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Services/NiriService.qml", import.meta.url), "utf8");

function fixture() {
    const context = vm.createContext({
        SettingsData: { niriOverviewBackgroundEnabled: false, niriActiveWindowColorEnabled: false, niriLayoutGapsOverride: -1, niriLayoutBorderSize: -1, getPrimaryBarConfig: () => null },
        Theme: { windowRadius: 12, primary: { r: 0.2, g: 0.4, b: 0.6, a: 0.5 }, surfaceContainerHighest: { r: 1, g: 1, b: 1, a: 1 } },
        Qt: { rgba: (r, g, b, a) => {
            assert.equal(a, 1, "niri palette colors must be opaque");
            return "#" + [r, g, b].map(value => Math.round(value * 255).toString(16).padStart(2, "0")).join("");
        } },
        Paths: { strip: path => path },
        StandardPaths: { writableLocation: () => "/config" },
        log: { debug() {} },
        writeConfigProcess: { running: false },
        writeAlttabProcess: {},
        _layoutXrayLoaded: true,
        _layoutAppliedRevision: 0,
        _awaitingLayoutReloadRevision: 0,
        _layoutRequestRevision: 1,
        _lastGeneratedAlttabContent: "",
        layoutXrayEnabled: true,
        layoutBarXrayEnabled: true,
        replaceFileCommand: () => "write",
        ensureDmsConfigFiles() {}
    });
    context.root = context;
    for (const name of ["niriColor", "niriOverviewBlock", "niriBlurBlock", "doGenerateNiriLayoutConfig"]) {
        const body = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{[\\s\\S]*?^    \\}\\n(?=\\n    (?:function|property))`, "m"));
        assert.ok(body, `${name} must exist`);
        vm.runInContext(body[0], context);
    }
    Object.defineProperty(context, "overviewBackdropConfig", { get: () => context.niriOverviewBlock() });
    Object.defineProperty(context, "activeWindowColor", { get: () => context.SettingsData.niriActiveWindowColorEnabled ? context.niriColor(context.Theme.primary) : "" });
    function generate() {
        context.writeConfigProcess.running = false;
        context._awaitingLayoutReloadRevision = 0;
        context.doGenerateNiriLayoutConfig();
        return context.writeConfigProcess.configContent;
    }
    return { context, generate };
}

test("overview integration follows the highest surface color through palette changes", () => {
    const { context, generate } = fixture();
    context.SettingsData.niriOverviewBackgroundEnabled = true;
    assert.match(generate(), /overview \{\n    backdrop-color "#ffffff"\n\}/);
    context.Theme.surfaceContainerHighest = { r: 0.6, g: 0.4, b: 0.2, a: 1 };
    assert.match(generate(), /backdrop-color "#996633"/);
});

test("the two integrations can be independently disabled without changing other outline states", () => {
    const { context, generate } = fixture();
    for (const background of [false, true]) {
        for (const outline of [false, true]) {
            context.SettingsData.niriOverviewBackgroundEnabled = background;
            context.SettingsData.niriActiveWindowColorEnabled = outline;
            const config = generate();
            assert.equal(config.includes('backdrop-color "#ffffff"'), background);
            assert.equal((config.match(/active-color "#336699"/g) ?? []).length, outline ? 2 : 0);
            assert.doesNotMatch(config, /inactive-color|urgent-color|tab-indicator/);
            assert.match(config, /geometry-corner-radius 12/);
        }
    }
});

test("window outline integration uses the primary accent and follows palette changes", () => {
    const { context, generate } = fixture();
    context.SettingsData.niriActiveWindowColorEnabled = true;
    const config = generate();
    for (const section of ["border", "focus-ring"])
        assert.match(config, new RegExp(section + ' \\{\\n        width 2\\n        active-color "#336699"\\n    \\}'));
    context.Theme.primary = { r: 0.6, g: 0.2, b: 0.4, a: 1 };
    assert.equal((generate().match(/active-color "#993366"/g) ?? []).length, 2);
});
