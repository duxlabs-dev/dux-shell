import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

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
        mouseAccumulatorX: 0,
        mouseAccumulatorY: 0,
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

test("volume scroll increases on scroll up, ignores workspace reverseScrolling, and never drops fast wheel detents", () => {
    const { context, events } = createScrollArea({
        yBehavior: "volume",
        reverseScrolling: true
    });
    context.AudioService.wheelVolumeStep = 3;

    context.processWheel(mouseWheel(120));
    context.processWheel(mouseWheel(120));
    context.processWheel(mouseWheel(-120));

    assert.deepEqual(events.volume, [[3, 1], [3, 1], [3, -1]]);
    assert.equal(events.volumeSound, 3);
    assert.equal(context.actionInProgress, false);
    assert.equal(events.cooldownRestarts, 0);
});

test("high-res mouse sub-detents accumulate cleanly and reset opposite-sign remainder on reversal", () => {
    const { context, events } = createScrollArea({ yBehavior: "volume" });

    context.processWheel(mouseWheel(40));
    context.processWheel(mouseWheel(40));
    assert.deepEqual(events.volume, []);
    context.processWheel(mouseWheel(40));
    assert.deepEqual(events.volume, [[5, 1]]);

    // Partial upward remainder (+60) is discarded when scrolling down (-120)
    context.processWheel(mouseWheel(60));
    context.processWheel(mouseWheel(-120));
    assert.deepEqual(events.volume, [[5, 1], [5, -1]]);
});

test("touchpad level scroll steps smoothly by 1% per 100 angleDelta and resets on ScrollBegin/ScrollEnd", () => {
    const { context, events } = createScrollArea({
        xBehavior: "brightness",
        yBehavior: "volume"
    });

    context.processWheel(touchpadWheel(60, QtStub.ScrollBegin));
    context.processWheel(touchpadWheel(60, QtStub.ScrollUpdate));
    context.processWheel(touchpadWheel(190, QtStub.ScrollUpdate));
    context.processWheel(touchpadWheel(0, QtStub.ScrollEnd));

    assert.deepEqual(events.volume, [[1, 1], [2, 1]]);
    assert.equal(context.touchpadAccumulatorY, 0);

    // Shift+vertical mouse wheel routes to horizontal xBehavior ("brightness")
    context.processWheel(mouseWheel(120, 0, QtStub.ShiftModifier));
    assert.deepEqual(events.brightness, [["DP-1", 5, 1]]);
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

test("wheel-consuming bar widgets default scrollEnabled to true and leave wheel unaccepted when disabled or horizontal", () => {
    const defaults = vm.createContext({});
    vm.runInContext(readFileSync(new URL("../Common/settings/BarWidgetDefaults.js", import.meta.url), "utf8").replace(/^\.pragma.*$/gm, ""), defaults);

    for (const widgetType of ["workspaceSwitcher", "runningApps", "battery", "controlCenterButton"]) {
        assert.equal(defaults.option(widgetType, null, "scrollEnabled"), true, widgetType);
        assert.equal(defaults.option(widgetType, { scrollEnabled: false }, "scrollEnabled"), false, widgetType);
    }

    const WheelInput = vm.createContext({ Qt: QtStub });
    vm.runInContext(readFileSync(new URL("../DCommon/Common/WheelInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/gm, ""), WheelInput);
    const adjustments = [];
    const battery = vm.createContext({
        Qt: QtStub,
        WheelInput,
        touchpadAccumulator: 0,
        scrollEnabled: true,
        parentScreen: { name: "DP-1" },
        barScrollOverridesWheel: () => Boolean(battery.overrideActive),
        overrideActive: false,
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

    // Vertical wheel when scrollEnabled = false sets accepted = false so bar volume scroll receives it
    battery.scrollEnabled = false;
    const disabledVert = mouseWheel(120);
    battery.handleBatteryWheel(disabledVert);
    assert.equal(disabledVert.accepted, false);
    assert.deepEqual(adjustments, []);

    // Enabled vertical wheel consumes event and targets the battery's screen
    battery.scrollEnabled = true;
    const activeVert = mouseWheel(120);
    battery.handleBatteryWheel(activeVert);
    assert.equal(activeVert.accepted, true);
    assert.deepEqual(adjustments, [["DP-1", 5, 1]]);

    // Temporary bar-level override yields wheel without changing battery.scrollEnabled
    adjustments.length = 0;
    battery.overrideActive = true;
    const overriddenVert = mouseWheel(120);
    battery.handleBatteryWheel(overriddenVert);
    assert.equal(overriddenVert.accepted, false);
    assert.equal(battery.scrollEnabled, true);
    assert.deepEqual(adjustments, []);
});

test("BarPill.barScrollOverridesWheel temporarily overrides bar widgets without affecting dock, overflow, or disabled bar scroll", () => {
    const WheelInput = vm.createContext({ Qt: QtStub });
    vm.runInContext(readFileSync(new URL("../DCommon/Common/WheelInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/gm, ""), WheelInput);

    const pill = vm.createContext({
        Qt: QtStub,
        WheelInput,
        barConfig: {
            scrollEnabled: true,
            overrideWidgetScroll: true,
            scrollYBehavior: "volume",
            scrollXBehavior: "none"
        },
        registrationContext: { surface: { kind: "bar" }, owner: {} },
        BarWidgetService: {
            registrationForItem: () => ({ context: pill.registrationContext })
        }
    });
    pill.root = pill;
    vm.runInContext(functionSource("../Modules/SurfaceWidgets/BarPill.qml", "barScrollOverridesWheel"), pill);

    // Active on Y ("volume"), inactive on X ("none")
    assert.equal(pill.barScrollOverridesWheel(mouseWheel(120)), true);
    assert.equal(pill.barScrollOverridesWheel(mouseWheel(0, 120)), false);

    // Turning off master bar scroll restores widget scroll
    pill.barConfig.scrollEnabled = false;
    assert.equal(pill.barScrollOverridesWheel(mouseWheel(120)), false);
    pill.barConfig.scrollEnabled = true;

    // Dock-hosted and overflow-popout widgets keep their own scroll
    pill.registrationContext = { surface: { kind: "dock" }, owner: {} };
    assert.equal(pill.barScrollOverridesWheel(mouseWheel(120)), false);
    pill.registrationContext = { surface: { kind: "bar" }, owner: { overflowAnchor: true } };
    assert.equal(pill.barScrollOverridesWheel(mouseWheel(120)), false);
});
