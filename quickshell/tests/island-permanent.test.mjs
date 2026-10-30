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
    assert.deepEqual(plain(activities.permanentOn(table, "left")), { "pluginId": "abyss", "side": "left", "receiving": true, "label": "A", "dropText": "", "image": "", "seq": 1 });
    assert.equal(activities.permanentOn(table, "top"), null);
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
