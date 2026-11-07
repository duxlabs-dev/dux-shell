import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const activities = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/IslandActivities.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), activities);
vm.runInContext(readFileSync(new URL("../Common/IslandActivityInput.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), activities);
const plain = value => JSON.parse(JSON.stringify(value));

test("a permanent bubble needs a loaded, allowed plugin id without a colon; keep awake is the shell's own", () => {
    assert.equal(activities.permanentAllowed("abyss", true, true), true);
    assert.equal(activities.permanentAllowed("abyss", false, true), false);
    assert.equal(activities.permanentAllowed("abyss", true, false), false);
    for (const id of ["dms:abyss", "script:x", "", null, 3])
        assert.equal(activities.permanentAllowed(id, true, true), false, String(id));
    assert.equal(activities.permanentAllowed("dms:keepawake", false, false), true);
});

test("each plugin owns one entry; the newest on a side shows there, the other side keeps its own", () => {
    let table = activities.withPermanent({}, "abyss", { "side": "left", "label": "A" }, 1);
    table = activities.withPermanent(table, "orbit", { "side": "left", "label": "O" }, 2);
    table = activities.withPermanent(table, "sands", { "label": "S" }, 3);
    assert.deepEqual(Object.keys(table).sort(), ["abyss", "orbit", "sands"]);
    assert.equal(activities.permanentOn(table, "left").pluginId, "orbit");
    assert.equal(activities.permanentOn(table, "right").pluginId, "sands");
    assert.equal(table.sands.side, "right");
    assert.equal(table.sands.receiving, false);
    // A drop on the shown one keeps its place in line.
    table = activities.withPermanent(table, "abyss", Object.assign({}, table.abyss, { "receiving": true }), 4);
    assert.equal(activities.permanentOn(table, "left").pluginId, "orbit");
    table = activities.withPermanent(table, "orbit", null, 5);
    assert.deepEqual(plain(activities.permanentOn(table, "left")), { "pluginId": "abyss", "side": "left", "receiving": true, "label": "A", "image": "", "seq": 1 });
    assert.equal(activities.permanentOn(table, "top"), null);
});

test("a plugin's label and image are typed and bounded", () => {
    const hostile = activities.withPermanent({}, "abyss", { "label": "L".repeat(10000), "image": 42 }, 1).abyss;
    assert.equal(hostile.label.length, 24, "a long label is cut, so the bubble's width stays bounded");
    assert.equal(activities.withPermanent({}, "abyss", { "label": { "toString": "x" } }, 1).abyss.label, "", "an object is no text");
    assert.equal(hostile.image, "", "a number is no image");
    const fine = activities.withPermanent({}, "abyss", { "label": 7, "image": "file:///a.png" }, 1).abyss;
    assert.equal(fine.label, "7", "a number reads as text, as on a face");
    assert.equal(fine.image, "file:///a.png");
    assert.equal(activities.withPermanent({}, "abyss", { "image": new URL("file:///a.svg") }, 1).abyss.image, "file:///a.svg", "a url value (Qt.resolvedUrl gives one) keeps its text");
    assert.equal(activities.withPermanent({}, "abyss", { "image": "file:///" + "a".repeat(3000) }, 1).abyss.image, "", "a too long URL is dropped");
});

test("an unloaded plugin's entry goes, the others stay; the shell's own never shows as a plugin bubble", () => {
    let table = activities.withPermanent({}, "abyss", { "side": "left" }, 1);
    table = activities.withPermanent(table, "dms:keepawake", { "side": "left", "kind": "keepawake" }, 2);
    assert.equal(activities.permanentOn(table, "left").pluginId, "abyss");
    const before = table;
    table = activities.withPermanent(table, "abyss", null, 3);
    assert.notEqual(table, before);
    assert.deepEqual(Object.keys(table), ["dms:keepawake"]);
    assert.equal(activities.permanentOn(table, "left"), null);
    assert.equal(activities.withPermanent(table, "absent", null, 4), table);
});

test("the manifest schema lists every surface PluginService loads, and the island block", () => {
    const schema = JSON.parse(readFileSync(new URL("../PLUGINS/plugin-schema.json", import.meta.url), "utf8"));
    const service = readFileSync(new URL("../Services/PluginService.qml", import.meta.url), "utf8");
    const keys = JSON.parse(service.match(/pluginSurfaceKeys:\s*(\[[^\]]*\])/)[1]);
    assert.deepEqual(Object.keys(schema.properties.components.properties).sort(), keys.slice().sort());
    assert.deepEqual(Object.keys(schema.properties.island.properties).sort(), ["notifyApp", "systemFaces"]);
});
