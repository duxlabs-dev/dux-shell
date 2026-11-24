import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const pins = loadScript(new URL("../Common/settings/DockPins.js", import.meta.url));
const folders = loadScript(new URL("../Common/settings/AppFolders.js", import.meta.url));
const config = loadScript(new URL("../Common/settings/DockConfig.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

test("a center drop replaces the target pin and preserves other pins", () => {
    const before = ["a", "b", "c", "d"];
    const created = pins.drop(before, "a", "c", "Folder");
    const folder = created[1];
    assert.deepEqual(plain(created.map(pins.id)), ["b", pins.id(folder), "d"]);
    assert.deepEqual(plain(folder.apps), ["c", "a"]);
    assert.deepEqual(before, ["a", "b", "c", "d"]);

    const added = pins.drop(created, "d", pins.id(folder), "Folder");
    assert.deepEqual(plain(added[1].apps), ["c", "a", "d"]);
    assert.equal(added[1].id, folder.id);
    assert.equal(pins.add(added, "a"), added);
    assert.equal(pins.drop(added, "missing", pins.id(folder), "Folder"), added);
    assert.equal(pins.drop(added, "b", "b", "Folder"), added);
});

test("folder members can reorder, return to the dock, and unpin", () => {
    const folder = { id: "f", name: "Folder", apps: ["a", "b", "c"] };
    const before = ["start", folder, "end"];
    const reordered = folders.moveAppById(before, "f", "c", "a");
    assert.deepEqual(plain(reordered[1].apps), ["c", "a", "b"]);

    const extracted = pins.extract(reordered, "f", "a");
    assert.deepEqual(plain(extracted), ["start", { ...folder, apps: ["c", "b"] }, "a", "end"]);
    assert.deepEqual(plain(pins.dissolve(extracted, "f")), ["start", "c", "b", "a", "end"]);
    const last = pins.remove(pins.remove(before, "a"), "b");
    assert.deepEqual(plain(pins.extract(last, "f", "c")), ["start", "c", "end"]);
    assert.deepEqual(plain(pins.remove(last, "c")), ["start", "end"]);
});

test("grouping pins around widgets puts the folder in the target slot", () => {
    const widgets = [{ id: "clock", widgetId: "clock" }, { id: "apps", widgetId: "appsDock" }];
    const before = ["a", "b", "c"];
    const apps = before.map(id => ({ appId: id, uniqueKey: id, type: "pinned", isPinned: true }));
    const order = ["pin:a", "clock", "pin:b", "apps", "pin:c"];
    const next = pins.drop(before, "a", "b", "Folder");
    const folderId = pins.id(next[0]);
    const folder = { appId: folderId, uniqueKey: folderId, type: "folder", isPinned: true };
    const nextOrder = config.replacePinSlot(widgets, apps, order, apps[1], apps[0], [folder.appId]);

    assert.deepEqual(plain(nextOrder), ["clock", "pin:" + folder.appId, "apps", "pin:c"]);
    assert.deepEqual(plain(config.surfaceItems(widgets, [folder, apps[2]], nextOrder).map(item => item.unitId ?? item.id)),
        ["clock", "pin:" + folder.appId, "pin:c"]);
    assert.deepEqual(plain(config.reorderPins(next, [folder, apps[2]], ["pin:c", "pin:" + folderId])), ["c", plain(next[0])]);
});

test("launcher and dock classify a drop without nesting folders", () => {
    const app = { id: "a", type: "app" };
    const target = { id: "b", type: "app" };
    const folder = { id: "f", type: "folder" };
    assert.equal(folders.dropAction(app, target), "create");
    assert.equal(folders.dropAction(app, folder), "add");
    assert.equal(folders.dropAction(folder, target), "move");
    assert.equal(folders.dropAction(app, app), "");
    assert.equal(folders.dropAction(app, { id: "z", type: "file" }), "");
});

test("folder drop hit testing includes the leftmost RTL cell and uses content rows", () => {
    assert.equal(folders.memberGridIndex(0, 50, 120, 40, 3, true), 5);
    assert.equal(folders.memberGridIndex(40, 50, 120, 40, 3, true), 4);
    assert.equal(folders.memberGridIndex(120, 50, 120, 40, 3, true), -1);
});

test("creating a folder from the menu wraps the pin in place or pins it", () => {
    const before = ["a", "b"];
    const wrapped = pins.create(before, "a", "Folder");
    assert.equal(pins.isFolder(wrapped[0]), true);
    assert.deepEqual(plain(wrapped[0].apps), ["a"]);
    assert.equal(wrapped[1], "b");
    const appended = pins.create(before, "c", "Folder");
    assert.deepEqual(plain(appended[2].apps), ["c"]);
    assert.equal(pins.create(wrapped, "a", "Folder"), wrapped);
    assert.deepEqual(before, ["a", "b"]);
});

test("several folders collapse under one expandable row", () => {
    const added = [];
    let toggled = 0;
    const options = expanded => ({
        header: "Add to folder",
        label: folder => "Add to " + folder.name,
        indent: 4,
        expanded,
        toggle: () => toggled++,
        add: folder => added.push(folder.id)
    });
    const one = folders.addToFolderEntries([{ id: "a", name: "A", apps: [] }], options(false));
    assert.deepEqual(plain(one.map(entry => [entry.text, !!entry.hidden])), [["Add to A", false]]);

    const two = [{ id: "a", name: "A", apps: [] }, { id: "b", name: "B", apps: [] }];
    const collapsed = folders.addToFolderEntries(two, options(false));
    assert.deepEqual(plain(collapsed.map(entry => !!entry.hidden)), [false, true, true]);
    assert.equal(collapsed[0].keepOpen, true);
    collapsed[0].action();
    assert.equal(toggled, 1);
    const open = folders.addToFolderEntries(two, options(true));
    assert.deepEqual(plain(open.map(entry => !!entry.hidden)), [false, false, false]);
    open[2].action();
    assert.deepEqual(added, ["b"]);
});
