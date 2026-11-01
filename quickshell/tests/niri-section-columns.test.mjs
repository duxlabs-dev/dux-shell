import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const columns = loadScript(new URL("../Common/niri/sections/columns.js", import.meta.url));
const { assemble } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));
const { target } = loadScript(new URL("../Common/niri/colwidth.js", import.meta.url));

const raw = changes => assemble([{ id: "windows", toKdl: columns.toKdl }], Object.assign({}, columns.defaults, changes));
const defaultLayout = "layout {\n    default-column-width { proportion 0.5; }\n}\n";
// Every other test looks past the always-written default width.
const kdl = changes => raw(changes).replace(defaultLayout, "");

test("the 1/3 default is written even unchanged so it wins over config.kdl at boot", () => {
    assert.equal(columns.defaults["columns.defaultWidth"], 0.5);
    assert.equal(raw({}), defaultLayout);
});

test("the desk's shared key keeps its fixed name and values", () => {
    assert.equal(columns.defaults["columns.centerFocused"], "never");
    assert.match(kdl({ "columns.centerFocused": "on-overflow" }), /center-focused-column "on-overflow"/);
});

test("layout changes land in one layout block", () => {
    assert.equal(kdl({
        "columns.centerFocused": "always",
        "columns.centerSingle": true,
        "columns.defaultWidth": 1,
        "columns.presetWidths": [0.25, 0.5],
        "columns.display": "tabbed"
    }), [
        "layout {",
        "    center-focused-column \"always\"",
        "    always-center-single-column",
        "    default-column-width { proportion 1.0; }",
        "    preset-column-widths {",
        "        proportion 0.25",
        "        proportion 0.5",
        "    }",
        "    default-column-display \"tabbed\"",
        "}",
        ""
    ].join("\n"));
});

test("an empty preset list is never written", () => {
    assert.equal(kdl({ "columns.presetWidths": [] }), "");
});

test("turning off what DMS's config.kdl turns on writes an explicit false", () => {
    assert.equal(kdl({ "columns.noCsd": false }), "prefer-no-csd false\n");
});

test("overview zoom and Alt-Tab", () => {
    assert.equal(kdl({ "columns.overviewZoom": 0.35, "columns.altTab": false, "columns.altTabDelay": 0, "columns.altTabPreviewScale": 0.75 }), [
        "overview {",
        "    zoom 0.35",
        "}",
        "recent-windows {",
        "    off",
        "    open-delay-ms 0",
        "    previews {",
        "        max-scale 0.75",
        "    }",
        "}",
        ""
    ].join("\n"));
});

test("string values are quoted through the shared KDL escape", () => {
    const out = kdl({ "columns.centerFocused": "a\"\n}", "columns.display": "b\\\"" });
    assert.match(out, /center-focused-column "a\\"\\n}"/);
    assert.match(out, /default-column-display "b\\\\\\""/);
});

test("every key is stored in the page and searchable", () => {
    for (const key in columns.defaults) {
        assert.equal(columns.stored[key], "page");
        assert.ok(columns.search.some(s => s.key === key), key);
    }
});

test("overview close on focus binds to the SettingsData property and writes no KDL", () => {
    assert.equal(columns.stored["columns.overviewCloseFocus"], "SettingsData:closeNiriOverviewOnWindowFocus");
    assert.ok(columns.search.some(s => s.key === "columns.overviewCloseFocus"));
    assert.equal(kdl({ "columns.overviewCloseFocus": true }), "");
});

test("the Super+R option lives on the page only, off by default, never written to niri.kdl", () => {
    assert.equal(columns.defaults["columns.cycleWidth"], false);
    assert.equal(kdl({ "columns.cycleWidth": true }), "");
    const windows = [{ id: 1, workspace_id: 1, is_focused: true, layout: { pos_in_scrolling_layout: [1, 0], window_size: [400, 600] } }];
    assert.equal(target({}, columns.defaults, windows), null, "an empty page keeps niri's own switch");
    assert.equal(target({ "columns.cycleWidth": true }, columns.defaults, windows)?.id, 1, "on: the page cycles");
});
