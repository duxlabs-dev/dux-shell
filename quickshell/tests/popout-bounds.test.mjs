import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const bounds = loadScript(new URL("../Common/PopoutBounds.js", import.meta.url));
const rect = value => ({...value});

test("top and bottom popouts keep vertical travel but bound horizontal pixels", () => {
    const result = bounds.strip(3840, 2160, false, {x: 1000, y: 40, width: 600, height: 700}, {x: 1000, y: 0, width: 600, height: 1}, 40);
    assert.deepEqual(rect(result), {x: 960, y: 0, width: 680, height: 2160});
});

test("side popouts retain the handoff origin and clip to the output", () => {
    const result = bounds.strip(1920, 1080, true, {x: 20, y: 40, width: 600, height: 700}, {x: 0, y: 900, width: 1, height: 100}, 100);
    assert.deepEqual(rect(result), {x: 0, y: 0, width: 1920, height: 1080});
});

test("an origin outside a smaller output still yields an on-screen surface", () => {
    const result = bounds.strip(1280, 720, false, {x: 1500, y: 40, width: 200, height: 300}, {x: 1600, y: 40, width: 200, height: 300}, 40);
    assert.deepEqual(rect(result), {x: 1279, y: 0, width: 1, height: 720});
});

test("an open surface fits the output after its resolution shrinks", () => {
    const old = {x: 2000, y: 0, width: 800, height: 2160};
    const current = {x: 1000, y: 0, width: 600, height: 1080};
    assert.deepEqual(rect(bounds.clip(bounds.unite(old, current), 1920, 1080)), {x: 1000, y: 0, width: 920, height: 1080});
});
