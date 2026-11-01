import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

// The singleton imports qs.*, which qmltestrunner cannot resolve, so its functions run here against fakes.
const source = readFileSync(new URL("../Services/HotCornerService.qml", import.meta.url), "utf8");
const Corners = loadScript(new URL("../Common/niri/sections/corners.js", import.meta.url));

function service({ page = {}, outputSettings = {} } = {}) {
    const spawned = [];
    const context = vm.createContext({
        Corners,
        NiriService: {
            outputs: { "DP-1": { make: "LG", model: "27GL850", serial: "S1" } },
            getOutputIdentifier: (output, name) => output.make + " " + output.model + " " + output.serial
        },
        SessionData: {
            getNiriOutputSetting: (id, key, fallback) => outputSettings[id]?.[key] ?? fallback
        },
        NiriPageService: { state: Object.assign({}, Corners.defaults, page) },
        Quickshell: { execDetached: command => spawned.push(command) }
    });
    context.root = context;
    for (const match of source.matchAll(/^    function \w+\([^\n]*\) \{\n[\s\S]*?^    \}/gm))
        vm.runInContext(match[0], context);
    return { s: context, spawned };
}

const plain = value => JSON.parse(JSON.stringify(value));

test("a screen gets zones from the global corners until it has its own", () => {
    const page = { "corners.top-right": "notifications", "corners.screens": { "LG 27GL850 S1": { "bottom-left": "launcher" } } };
    const shared = service({ page });
    assert.deepEqual(plain(shared.s.zonesFor("DP-1")), ["top-right"]);

    const own = service({ page, outputSettings: { "LG 27GL850 S1": { hotCorners: { off: true } } } });
    assert.deepEqual(plain(own.s.zonesFor("DP-1")), ["bottom-left"]);
    assert.deepEqual(plain(own.s.zonesFor("HDMI-A-1")), ["top-right"]);
});

test("a hovered corner runs its current DMS action, niri's overview and nothing never do", () => {
    const { s, spawned } = service({ page: { "corners.top-right": "launcher", "corners.bottom-left": "screenshot", "corners.bottom-right": "lock" } });
    for (const corner of ["top-left", "top-right", "bottom-left", "bottom-right"])
        s.trigger("DP-1", corner);
    assert.deepEqual(plain(spawned), [["dms", "ipc", "call", "spotlight", "toggle"], ["dms", "screenshot"]]);
});
