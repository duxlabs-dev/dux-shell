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
