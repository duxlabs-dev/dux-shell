import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const kdl = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/niriKdl.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), kdl);

test("kdlString escapes backslashes, quotes and newlines", () => {
    assert.equal(kdl.kdlString('My "Theme"\\x'), '"My \\"Theme\\"\\\\x"');
    assert.equal(kdl.kdlString("a\nb"), '"a\\nb"');
});

test("deviceBlock drops an empty device and indents the lines of a used one", () => {
    assert.equal(kdl.deviceBlock("mouse", []), "");
    assert.equal(kdl.deviceBlock("touchpad", ["tap"]), "    touchpad {\n        tap\n    }\n");
});

const mouse = { speed: 0, profile: "default", naturalScroll: false, leftHanded: false, middleEmulation: false, scrollFactor: 1.0, scrollMethod: "default" };
const touchpad = { ...mouse, tap: false, clickMethod: "default", disableOnExternalMouse: false, disableWhileTyping: false, tapAndDrag: true, dragLock: false };

test("device blocks leave niri's defaults out and appear with their first line", () => {
    const cases = [
        [kdl.mouseBlock(mouse), ""],
        [kdl.touchpadBlock(touchpad), ""],
        [kdl.mouseBlock({ ...mouse, speed: -0.5 }), "    mouse {\n        accel-speed -0.5\n    }\n"],
        [kdl.mouseBlock({ ...mouse, leftHanded: true, scrollFactor: 2 }), "    mouse {\n        left-handed\n        scroll-factor 2.0\n    }\n"],
        [kdl.touchpadBlock({ ...touchpad, tap: true, speed: 0.3 }), "    touchpad {\n        tap\n        accel-speed 0.3\n    }\n"],
        [kdl.touchpadBlock({ ...touchpad, tapAndDrag: false }), "    touchpad {\n        drag false\n    }\n"]
    ];
    for (const [got, want] of cases)
        assert.equal(got, want);
});

test("pointer string settings are escaped", () => {
    const lines = kdl.pointerLines({ ...touchpad, profile: "fl\"at", clickMethod: "a\\b", scrollMethod: "x\"\ny" });
    assert.equal(lines.join("\n"), String.raw`accel-profile "fl\"at"` + "\n" + String.raw`click-method "a\\b"` + "\n" + String.raw`scroll-method "x\"\ny"`);
});

test("pinch-sensitivity is written only inside the slider range", () => {
    for (const value of [NaN, -1, 5, Infinity])
        assert.equal(kdl.touchpadBlock({ ...touchpad, pinchSensitivity: value }), "", String(value));
    assert.equal(kdl.touchpadBlock({ ...touchpad, pinchSensitivity: 1.5 }), "    touchpad {\n        pinch-sensitivity 1.5\n    }\n");
});
