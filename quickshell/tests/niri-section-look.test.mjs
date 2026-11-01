import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Look = loadScript(new URL("../Common/niri/sections/look.js", import.meta.url));
const Assemble = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));
const kdl = state => Assemble.assemble([{ id: "windows", toKdl: Look.toKdl }], Object.assign({}, Look.defaults, state));

test("defaults write nothing", () => {
    assert.equal(kdl({}), "");
});

test("ring off, border, shadow and blur write their niri lines", () => {
    assert.equal(kdl({ "look.ringOn": false, "look.borderOn": true, "look.shadowOn": true, "look.blurOn": true }),
        "window-rule {\n    background-effect {\n        blur true\n    }\n}\n"
        + "layout {\n    focus-ring {\n        off\n    }\n    border {\n        on\n    }\n    shadow {\n        on\n    }\n}\n");
});

test("colors: roles are left to the page service and colors.kdl, only opaque hex goes through", () => {
    assert.equal(kdl({ "look.ringColor": "#112233" }), "layout {\n    focus-ring {\n        active-color \"#112233\"\n    }\n}\n");
    assert.equal(kdl({ "look.ringColor": "tertiary" }), "");
    assert.equal(kdl({ "look.borderOn": true, "look.borderColor": "#aabbcc" }), "layout {\n    border {\n        on\n        active-color \"#aabbcc\"\n    }\n}\n");
    assert.equal(kdl({ "look.ringColor": "#80aabbcc" }), "");
    assert.equal(kdl({ "look.ringColor": "#aabbcc\" }\nspawn-at-startup \"x" }), "");
    assert.equal(kdl({ "look.borderOn": false, "look.borderColor": "#aabbcc" }), "");
});

test("the radius toggle keeps theme auto as its resting state", () => {
    // -1 follows the theme; 0 is a real (square) size, never what an off toggle writes
    assert.equal(Look.radiusAuto(-1), true);
    assert.equal(Look.radiusAuto(0), false);
    assert.equal(Look.radiusAuto(12), false);
    assert.equal(Look.radiusWrite(false, 15.7), -1);
    assert.equal(Look.radiusWrite(true, 15.7), 16);
});

test("widths, gaps, radius and blur strength stay with the DMS settings that already write them", () => {
    for (const key of ["look.gaps", "look.ringWidth", "look.borderWidth", "look.radius", "look.blurStrength"]) {
        assert.ok(Look.stored[key].startsWith("SettingsData:"), key);
        assert.equal(key in Look.defaults, false, key);
    }
    assert.equal(Look.stored["look.ringWidth"], Look.stored["look.borderWidth"]);
    for (const key of Object.keys(Look.defaults))
        assert.ok(Look.stored[key] === "page" || Look.stored[key].startsWith("NiriService:"), key);
    assert.deepEqual(kdl({ "look.xray": false, "look.barXray": false }), "");
    for (const entry of Look.search)
        assert.ok(entry.key in Look.stored, entry.key);
});
