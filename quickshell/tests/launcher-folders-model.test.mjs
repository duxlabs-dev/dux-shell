import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const ids = list => Array.from(list, i => i.id);

const Transform = loadScript(new URL("../Common/settings/LauncherFolders.js", import.meta.url));

const app = (id, extra) => Object.assign({ id, type: "app", name: id, section: "apps" }, extra);

test("transformFolder yields a drill-in item keyed by the folder", () => {
    const members = [app("a.desktop"), app("b.desktop")];
    const item = Transform.transformFolder({ id: "f1", name: "Work", icon: "", apps: ["a.desktop", "b.desktop"] }, members, "Open");
    assert.equal(item.id, "folder:f1");
    assert.equal(item.type, "folder");
    assert.equal(item.section, "apps");
    assert.equal(item.iconType, "folder");
    assert.equal(item.data.folderId, "f1");
    assert.equal(item.data.members, members);
    assert.equal(item.primaryAction.action, "open");

    const iconed = Transform.transformFolder({ id: "f2", name: "Games", icon: "sports_esports", apps: [] }, [], "Open");
    assert.equal(iconed.icon, "sports_esports");
    assert.equal(iconed.iconType, "material");
});

test("foldApps replaces foldered apps, core ones included, by folder items in folders order", () => {
    const items = [app("a"), app("b"), app("c"), app("core", { isCore: true }), app("d")];
    const folders = [
        { id: "f2", name: "Second", icon: "", apps: ["d", "core", "b"] },
        { id: "gone", name: "Uninstalled", icon: "", apps: ["zzz"] },
        { id: "f1", name: "First", icon: "", apps: ["a"] }
    ];
    const out = Transform.foldApps(items, folders, "Open");
    assert.deepEqual(ids(out), ["c", "folder:f2", "folder:f1"]);
    assert.deepEqual(ids(out[1].data.members), ["d", "core", "b"]);
    assert.equal(Transform.foldApps(items, [], "Open"), items);
    assert.equal(Transform.foldApps(items, [folders[1]], "Open"), items);
});

test("placeFolders re-inserts folder items at their slot, ascending, clamped to the list", () => {
    const folders = [
        { id: "late", name: "Late", icon: "", apps: ["q"], slot: 99 },
        { id: "mid", name: "Mid", icon: "", apps: ["r"], slot: 2 },
        { id: "first", name: "First", icon: "", apps: ["s"], slot: 0 }
    ];
    const folderItem = f => Transform.transformFolder(f, [], "Open");
    const items = [app("a"), app("b"), folderItem(folders[0]), app("c"), folderItem(folders[1]), folderItem(folders[2])];
    const out = Transform.placeFolders(items, folders);
    assert.deepEqual(ids(out), ["folder:first", "a", "folder:mid", "b", "c", "folder:late"]);
    assert.deepEqual(ids(items), ["a", "b", "folder:late", "c", "folder:mid", "folder:first"]);

    const tied = [
        { id: "t1", name: "", icon: "", apps: [], slot: 1 },
        { id: "t2", name: "", icon: "", apps: [], slot: 1 }
    ];
    assert.deepEqual(ids(Transform.placeFolders([folderItem(tied[1]), app("a"), folderItem(tied[0])], tied)), ["a", "folder:t1", "folder:t2"]);

    const plain = [app("a"), app("b")];
    assert.equal(Transform.placeFolders(plain, folders), plain);
    assert.equal(Transform.placeFolders(plain, []), plain);
});

test("placeFolders restores folders excluded by the app result limit without duplicating retained ones", () => {
    const apps = Array.from({ length: 500 }, (_, i) => app("app" + i));
    const folders = [
        { id: "first", name: "First", apps: ["member"], slot: 0 },
        { id: "last", name: "Last", apps: ["other"], slot: 999 }
    ];
    const folderItems = folders.map(folder => Transform.transformFolder(folder, [app(folder.apps[0])], "Open"));
    const allItems = apps.concat(folderItems);

    for (const retained of [apps, apps.concat(folderItems[0])]) {
        const placed = Transform.placeFolders(retained, folders, allItems);
        assert.equal(placed.length, apps.length + folders.length);
        assert.equal(placed[0], folderItems[0]);
        assert.equal(placed[placed.length - 1], folderItems[1]);
        assert.deepEqual(ids(placed.filter(item => item.type === "app")), ids(apps));
    }
});
