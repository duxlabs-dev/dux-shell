import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const SCROLL_AREA = "../Modules/DBar/BarScrollArea.qml";
const QtStub = Object.freeze({
    NoButton: 0,
    NoModifier: 0,
    ShiftModifier: 0x02000000,
    NoScrollPhase: 0,
    ScrollBegin: 1,
    ScrollUpdate: 2,
    ScrollEnd: 3
});

function functionSource(file, name) {
    const source = readFileSync(new URL(file, import.meta.url), "utf8");
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in ${file}`);
    return found[0];
}

function createScrollArea(overrides = {}) {
    const events = {
        volume: [],
        volumeSound: 0,
        brightness: [],
        workspace: [],
        focusWindow: [],
        cooldownRestarts: 0
    };
    const WheelInput = vm.createContext({ Qt: QtStub });
    vm.runInContext(readFileSync(new URL("../DCommon/Common/WheelInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/gm, ""), WheelInput);
    const context = vm.createContext(Object.assign({
        Qt: QtStub,
        WheelInput,
        scrollEnabled: true,
        xBehavior: "focusWindow",
        yBehavior: "workspace",
        screenName: "DP-1",
        screen: { name: "DP-1" },
        barConfig: {},
        touchpadAccumulatorX: 0,
        touchpadAccumulatorY: 0,
        actionInProgress: false,
        gestureActive: false,
        gestureHorizontal: false,
        cooldownTimer: {
            restart() {
                events.cooldownRestarts++;
            }
        },
        SettingsData: {
            barWidgetEntry: () => ({}),
            widgetOption: (_type, _entry, key) => key === "reverseScrolling" ? Boolean(context.reverseScrolling) : false
        },
        reverseScrolling: false,
        AudioService: {
            sink: { audio: { volume: 0.5, muted: false } },
            wheelVolumeStep: 5,
            adjustDefaultSinkVolume(step, direction) {
                events.volume.push([step, direction]);
            },
            playVolumeChangeSoundIfEnabled() {
                events.volumeSound++;
            }
        },
        BrightnessService: {
            adjustScreenBrightness(screen, step, direction) {
                events.brightness.push([screen?.name ?? screen, step, direction]);
                return true;
            }
        },
        CompositorService: {
            stepWindowFocus(screenName, direction) {
                events.focusWindow.push([screenName, direction]);
                return true;
            }
        },
        workspaceSwitchRequested(direction) {
            events.workspace.push(direction);
        }
    }, overrides));
    context.root = context;
    for (const name of [
        "isLevelBehavior",
        "handleLevelAction",
        "handleScrollAction",
        "fire",
        "stepLevelAccumulator",
        "levelStepAmount",
        "mouseWheelUnits",
        "accumulateLevelX",
        "accumulateLevelY",
        "accumulateX",
        "accumulateY",
        "horizontalGesture",
        "processWheel"
    ])
        vm.runInContext(functionSource(SCROLL_AREA, name), context);
    return { context, events };
}

function mouseWheel(dy, dx = 0, modifiers = 0) {
    return {
        accepted: true,
        phase: QtStub.NoScrollPhase,
        modifiers,
        angleDelta: { x: dx, y: dy },
        pixelDelta: { x: 0, y: 0 }
    };
}

function touchpadWheel(dy, phase = QtStub.ScrollUpdate, dx = 0) {
    return {
        accepted: true,
        phase,
        modifiers: QtStub.NoModifier,
        angleDelta: { x: dx, y: dy },
        pixelDelta: { x: dx, y: dy }
    };
}

test("volume scroll increases on scroll up, ignores workspace reverseScrolling, and scales merged multi-detent frames", () => {
    const { context, events } = createScrollArea({
        yBehavior: "volume",
        reverseScrolling: true
    });
    context.AudioService.wheelVolumeStep = 3;

    context.processWheel(mouseWheel(120));
    context.processWheel(mouseWheel(240));
    context.processWheel(mouseWheel(-120));

    assert.deepEqual(events.volume, [[3, 1], [6, 1], [3, -1]]);
    assert.equal(events.volumeSound, 0);
    assert.equal(context.actionInProgress, false);
    assert.equal(events.cooldownRestarts, 0);
});

test("compositor-scaled mouse wheel (e.g. 0.7x -> 84 angleDelta) fires immediately on first notch", () => {
    const { context, events } = createScrollArea({
        yBehavior: "volume",
        xBehavior: "brightness",
        barConfig: { scrollBrightnessStep: 12 }
    });

    context.processWheel(mouseWheel(84));
    context.processWheel(mouseWheel(-84));
    assert.deepEqual(events.volume, [[5, 1], [5, -1]]);

    // Shift + scaled vertical wheel fires custom scrollBrightnessStep immediately on click 1
    context.processWheel(mouseWheel(84, 0, QtStub.ShiftModifier));
    assert.deepEqual(events.brightness, [["DP-1", 12, 1]]);

    // Discrete workspace switch also fires on click 1 with scaled mouseScrollFactor
    context.yBehavior = "workspace";
    context.processWheel(mouseWheel(84));
    assert.deepEqual(events.workspace, [-1]);
});

test("touchpad level scroll steps smoothly by 1% per 100 angleDelta and resets on reversal or ScrollBegin/ScrollEnd", () => {
    const { context, events } = createScrollArea({
        xBehavior: "brightness",
        yBehavior: "volume",
        barConfig: { scrollBrightnessStep: 15 }
    });

    context.processWheel(touchpadWheel(60, QtStub.ScrollBegin));
    context.processWheel(touchpadWheel(60, QtStub.ScrollUpdate));
    context.processWheel(touchpadWheel(190, QtStub.ScrollUpdate));
    // Reversing direction discards partial +10 remainder before accumulating downward
    context.processWheel(touchpadWheel(-110, QtStub.ScrollUpdate));
    context.processWheel(touchpadWheel(0, QtStub.ScrollEnd));

    assert.deepEqual(events.volume, [[1, 1], [2, 1], [1, -1]]);
    assert.equal(context.touchpadAccumulatorY, 0);

    // Touchpad horizontal brightness still steps 1% per 100 delta regardless of mouse scrollBrightnessStep
    context.processWheel(touchpadWheel(0, QtStub.ScrollBegin, 150));
    assert.deepEqual(events.brightness, [["DP-1", 1, 1]]);
});

test("null sink safely no-ops volume scroll while discrete workspace scroll still enforces cooldown", () => {
    const { context, events } = createScrollArea({ yBehavior: "volume" });
    context.AudioService.sink = null;
    context.processWheel(mouseWheel(120));
    assert.deepEqual(events.volume, []);
    assert.equal(events.volumeSound, 0);

    context.yBehavior = "workspace";
    context.processWheel(mouseWheel(120));
    context.processWheel(mouseWheel(120));
    assert.deepEqual(events.workspace, [-1]);
    assert.equal(context.actionInProgress, true);
    assert.equal(events.cooldownRestarts, 1);
});

test("scrollable bar widgets default scrollEnabled to true, expose bar/island scroll defaults, and pass through disabled or horizontal wheels", () => {
    const defaults = loadScript(new URL("../Common/settings/BarWidgetDefaults.js", import.meta.url));

    for (const widgetType of ["workspaceSwitcher", "runningApps", "music", "battery", "controlCenterButton"]) {
        assert.equal(defaults.option(widgetType, null, "scrollEnabled"), true, widgetType);
        assert.equal(defaults.option(widgetType, { scrollEnabled: false }, "scrollEnabled"), false, widgetType);
    }
    assert.equal(defaults.ISLAND_DEFAULTS.islandScrollEmptyStrip, true);

    const defaultBar = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC.barConfigs.def[0];
    assert.equal(defaultBar.scrollBrightnessStep, 5);
    assert.equal(defaultBar.scrollExtendToEdge, true);
    assert.equal("overrideWidgetScroll" in defaultBar, false);

    const WheelInput = vm.createContext({ Qt: QtStub });
    vm.runInContext(readFileSync(new URL("../DCommon/Common/WheelInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/gm, ""), WheelInput);
    const adjustments = [];
    const battery = vm.createContext({
        Qt: QtStub,
        WheelInput,
        touchpadAccumulator: 0,
        scrollEnabled: true,
        barConfig: { scrollBrightnessStep: 8 },
        parentScreen: { name: "DP-1" },
        BrightnessService: {
            brightnessAvailable: true,
            adjustScreenBrightness(screen, step, direction) {
                adjustments.push([screen?.name, step, direction]);
                return true;
            }
        }
    });
    battery.battery = battery;
    vm.runInContext(functionSource("../Modules/DBar/Widgets/Battery.qml", "handleBatteryWheel"), battery);

    // Horizontal wheel on Battery sets accepted = false so BarScrollArea receives it
    const horiz = mouseWheel(0, 120);
    battery.handleBatteryWheel(horiz);
    assert.equal(horiz.accepted, false);
    assert.deepEqual(adjustments, []);

    // Vertical wheel when scrollEnabled = false sets accepted = false so bar scroll receives it
    battery.scrollEnabled = false;
    const disabledVert = mouseWheel(84);
    battery.handleBatteryWheel(disabledVert);
    assert.equal(disabledVert.accepted, false);
    assert.deepEqual(adjustments, []);

    // Enabled vertical wheel fires immediately on scaled mouse wheel (84) using barConfig.scrollBrightnessStep
    battery.scrollEnabled = true;
    const activeVert = mouseWheel(84);
    battery.handleBatteryWheel(activeVert);
    assert.equal(activeVert.accepted, true);
    assert.deepEqual(adjustments, [["DP-1", 8, 1]]);
});

test("DBarBody.pointInIslandSatellite distinguishes satellite widget bounds from empty strip space", () => {
    const leftSection = { visible: true, implicitWidth: 120, implicitHeight: 32, originX: 16, originY: 4 };
    const rightSection = { visible: true, implicitWidth: 90, implicitHeight: 32, originX: 1800, originY: 4 };
    const body = vm.createContext({
        islandSatellitesEnabled: true,
        _leftSection: leftSection,
        _rightSection: rightSection
    });
    vm.runInContext(functionSource("../Modules/DBar/DBarBody.qml", "pointInIslandSatellite"), body);

    const sourceItem = {
        mapToItem(section, x, y) {
            return { x: x - section.originX, y: y - section.originY };
        }
    };

    assert.equal(body.pointInIslandSatellite(sourceItem, 50, 16), true);
    assert.equal(body.pointInIslandSatellite(sourceItem, 1840, 20), true);
    assert.equal(body.pointInIslandSatellite(sourceItem, 600, 16), false);

    body.islandSatellitesEnabled = false;
    assert.equal(body.pointInIslandSatellite(sourceItem, 50, 16), false);
});
