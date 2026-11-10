import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const index = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Services/IconThemeIndex.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), index);
const searchDirs = ["/user/theme", "/system/theme", "/system/inherited", "/system/hicolor"];
const looseDirs = ["/user/icons", "/system/pixmaps"];

function build(paths) {
    const result = index.create();
    for (const path of paths)
        index.add(result, path, searchDirs, looseDirs);
    return result.paths;
}

test("index keeps the existing category, root, format, size and tie priorities", () => {
    const cases = [
        ["/user/theme/actions/icon.svg", "/system/inherited/apps/icon.png"],
        ["/system/theme/apps/scalable/icon.svg", "/user/theme/apps/16/icon.png"],
        ["/user/theme/apps/512/icon.png", "/user/theme/apps/16/icon.svg"],
        ["/user/theme/apps/512/icon.svg", "/user/theme/apps/scalable/icon.svg"],
        ["/user/theme/apps/16x16/icon.png", "/user/theme/apps/48x48@2x/icon.png"],
        ["/system/pixmaps/icon.svg", "/user/icons/icon.png"]
    ];
    for (const [loser, winner] of cases) {
        assert.equal(build([loser, winner]).get("icon"), winner);
        assert.equal(build([winner, loser]).get("icon"), winner);
    }
    const ties = ["/user/theme/apps/a/icon.svg", "/user/theme/apps/b/icon.svg"];
    assert.equal(build(ties).get("icon"), ties[0]);
});

test("index prefers rasters up to 256px over larger ones, and the smallest of those otherwise", () => {
    const cases = [
        ["/system/hicolor/apps/1024x1024/icon.png", "/system/hicolor/apps/256x256/icon.png"],
        ["/system/hicolor/apps/512x512/icon.png", "/system/hicolor/apps/128x128/icon.png"],
        ["/system/hicolor/apps/1024x1024/icon.png", "/system/hicolor/apps/512x512/icon.png"],
        ["/system/hicolor/apps/256x256/icon.png", "/system/hicolor/apps/scalable/icon.png"]
    ];
    for (const [loser, winner] of cases) {
        assert.equal(build([loser, winner]).get("icon"), winner);
        assert.equal(build([winner, loser]).get("icon"), winner);
    }
});

test("index bounds retained paths by resolvable names and handles object property names", () => {
    const paths = ["/user/theme/apps/icon.svg", "/user/theme/apps/16/icon.png", "/system/pixmaps/loose.xpm", "/user/theme/apps/__proto__.svg", "/user/theme/apps/constructor.png", "/user/theme/apps/not a name.svg"];
    const result = build(paths);
    assert.equal(result.keys().length, 4);
    assert.equal(result.get("__proto__"), paths[3]);
    assert.equal(result.get("constructor"), paths[4]);
    assert.equal(result.get("loose"), paths[2]);
});
