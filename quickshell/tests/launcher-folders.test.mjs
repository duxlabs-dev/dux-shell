import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const folders = loadScript(new URL("../Common/settings/LauncherFolders.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));
const appsById = list => Object.fromEntries(plain(list).map(f => [f.id, f.apps]));

const seed = () => [
    { id: "a", name: "A", icon: "", apps: ["x", "y"] },
    { id: "b", name: "B", icon: "", apps: ["z"] }
];

test("createFolder pulls its apps out of other folders and drops the emptied ones", () => {
    const before = seed();
    const snapshot = plain(before);
    const result = folders.createFolder(before, "New", ["y", "z", "y"]);

    assert.ok(result.id);
    assert.deepEqual(appsById(result.folders), { a: ["x"], [result.id]: ["y", "z"] });
    assert.deepEqual(plain(before), snapshot);
});

test("removeApp deletes a folder it empties and keeps identity when the app is in none", () => {
    const before = seed();
    assert.deepEqual(appsById(folders.removeApp(before, "z")), { a: ["x", "y"] });
    assert.deepEqual(appsById(folders.removeApp(before, "x")), { a: ["y"], b: ["z"] });
    assert.equal(folders.removeApp(before, "missing"), before);
});

test("addApp moves an app between folders without duplicating it", () => {
    const before = seed();
    assert.equal(folders.addApp(before, "a", "x"), before);
    assert.equal(folders.addApp(before, "nope", "q"), before);
    assert.deepEqual(appsById(folders.addApp(before, "a", "z")), { a: ["x", "y", "z"] });
    assert.deepEqual(appsById(folders.addApp(before, "b", "x")), { a: ["y"], b: ["z", "x"] });
});

test("dissolveFolder removes only that folder", () => {
    const before = seed();
    assert.deepEqual(appsById(folders.dissolveFolder(before, "a")), { b: ["z"] });
    assert.equal(folders.dissolveFolder(before, "nope"), before);
});

test("createFolder stores a non-negative integer slot, defaulting to 0", () => {
    assert.equal(folders.createFolder([], "A", ["x"], 7).folders[0].slot, 7);
    assert.equal(folders.createFolder([], "A", ["x"]).folders[0].slot, 0);
    assert.equal(folders.createFolder([], "A", ["x"], -3).folders[0].slot, 0);
    assert.equal(folders.createFolder([], "A", ["x"], 2.9).folders[0].slot, 2);
});

test("setFolderSlot moves a folder and keeps identity when unchanged or unknown", () => {
    const before = seed().map((f, i) => Object.assign(f, { slot: i }));
    const moved = folders.setFolderSlot(before, "b", 5);
    assert.equal(plain(moved)[1].slot, 5);
    assert.deepEqual(plain(moved)[0], plain(before)[0]);
    assert.equal(folders.setFolderSlot(before, "a", 0), before);
    assert.equal(folders.setFolderSlot(before, "nope", 3), before);
    assert.equal(plain(before)[1].slot, 1);
});
