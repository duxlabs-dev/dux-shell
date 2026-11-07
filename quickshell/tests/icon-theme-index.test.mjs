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
        assert.equal(build([loser, winner]).icon, winner);
        assert.equal(build([winner, loser]).icon, winner);
    }
    const ties = ["/user/theme/apps/a/icon.svg", "/user/theme/apps/b/icon.svg"];
    assert.equal(build(ties).icon, ties[0]);
});

test("index prefers rasters up to 256px over larger ones, and the smallest of those otherwise", () => {
    const cases = [
        ["/system/hicolor/apps/1024x1024/icon.png", "/system/hicolor/apps/256x256/icon.png"],
        ["/system/hicolor/apps/512x512/icon.png", "/system/hicolor/apps/128x128/icon.png"],
        ["/system/hicolor/apps/1024x1024/icon.png", "/system/hicolor/apps/512x512/icon.png"],
        ["/system/hicolor/apps/256x256/icon.png", "/system/hicolor/apps/scalable/icon.png"]
    ];
    for (const [loser, winner] of cases) {
        assert.equal(build([loser, winner]).icon, winner);
        assert.equal(build([winner, loser]).icon, winner);
    }
});

test("index bounds retained paths by resolvable names and handles object property names", () => {
    const paths = ["/user/theme/apps/icon.svg", "/user/theme/apps/16/icon.png", "/system/pixmaps/loose.xpm", "/user/theme/apps/__proto__.svg", "/user/theme/apps/constructor.png", "/user/theme/apps/not a name.svg"];
    const result = build(paths);
    assert.equal(Object.keys(result).length, 4);
    assert.equal(result.__proto__, paths[3]);
    assert.equal(result.constructor, paths[4]);
    assert.equal(result.loose, paths[2]);
});

const serviceSource = () => readFileSync(process.env.ICON_SERVICE_SOURCE || new URL("../Services/IconThemeService.qml", import.meta.url), "utf8");

test("loose icons only fill names missing from a completed theme scan, never a timed-out one", () => {
    const source = serviceSource();
    const job = ["complete", "publish"].map(name => source.match(new RegExp(`^            function ${name}\\(\\) \\{[\\s\\S]*?^            \\}`, "m"))[0]).join("\n");
    const run = finish => {
        let published = null;
        const context = vm.createContext({
            theme: "theme", remaining: 2, finished: false,
            themeIndex: { paths: build(["/user/theme/apps/themed.svg"]) },
            looseIndex: { paths: build(["/system/pixmaps/themed.png", "/system/pixmaps/kitty.png"]) },
            root: { _publishIndex: (theme, paths) => published = paths },
            destroy() {}
        });
        vm.runInContext(job, context);
        finish(context);
        return published;
    };
    const completed = run(job => { job.complete(); job.complete(); });
    assert.equal(completed.themed, "/user/theme/apps/themed.svg");
    assert.equal(completed.kitty, "/system/pixmaps/kitty.png");
    const timedOut = run(job => { job.complete(); job.publish(); job.complete(); });
    assert.equal(timedOut.themed, "/user/theme/apps/themed.svg");
    assert.equal(timedOut.kitty, undefined);
});

test("first lookup uses the completed index without spawning or retaining misses", () => {
    const source = serviceSource();
    const resolve = source.match(/^    function resolve\(name\) \{[\s\S]*?^    \}/m)[0];
    let spawns = 0;
    const context = vm.createContext({
        _iconPaths: build(["/user/theme/apps/icon.svg"]),
        Paths: { toFileUrl: path => "file://" + path },
        revision: 0, managedTheme: "theme", _dirsForTheme: "theme", _cache: {},
        _resolveAsync: () => spawns++
    });
    vm.runInContext(resolve, context);
    assert.equal(context.resolve("icon"), "file:///user/theme/apps/icon.svg");
    for (let i = 0; i < 100; i++)
        assert.equal(context.resolve("missing-" + i), "");
    assert.equal(spawns, 0);
    assert.equal(Object.keys(context._iconPaths).length, 1);
});
