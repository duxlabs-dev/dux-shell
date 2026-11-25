import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const sessionSpec = loadScript(new URL("../Common/settings/SessionSpec.js", import.meta.url));
const librarySource = readFileSync(new URL("../Services/WallpaperLibraryService.qml", import.meta.url), "utf8");
const sessionSource = readFileSync(new URL("../Common/SessionData.qml", import.meta.url), "utf8");

function extractFunction(source, name) {
    const match = source.match(new RegExp(`^    function ${name}\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!match)
        throw new Error(`${name} not found`);
    return match[0];
}

function library(folders, options = {}) {
    const context = vm.createContext({
        folders,
        visibleFolders: folders.filter(f => !f.hidden),
        selection: options.selection ?? [],
        filtering: (options.selection ?? []).length > 0,
        SessionData: { isLightMode: !!options.isLightMode }
    });
    for (const name of ["itemsIn", "selected", "normalizeAppearance", "folderMatchesMode", "selectedForMode"])
        vm.runInContext(extractFunction(librarySource, name), context);
    return context;
}

function session(state = {}) {
    const modeCalls = [];
    const context = vm.createContext(Object.assign({
        isLightMode: false,
        perModeWallpaper: false,
        themeModeAutoEnabled: false,
        perMonitorWallpaper: false,
        wallpaperPath: "",
        wallpaperPathLight: "",
        wallpaperPathDark: "",
        wallpaperCyclingFolderPath: "",
        wallpaperFolders: [],
        Qt: { callLater() {} },
        WallpaperLibraryService: { listedPath: p => p },
        setLightMode(light, skip) {
            modeCalls.push({ light, skip });
            context.isLightMode = light;
        },
        setWallpaper(path) {
            context.wallpaperPath = path;
        },
        setMonitorWallpaper(screenName, path) {
            context.lastMonitorPick = { screenName, path };
        },
        setMonitorCyclingFolderPath() {},
        saveSettings() {},
        wallpaperRequestRevision() { return 1; },
        Theme: {
            setLightMode(light) {
                modeCalls.push({ light });
                context.isLightMode = light;
            }
        },
        WallpaperLibraryService: {
            folderOf(path, cb) {
                if (state.ownerByPath)
                    cb(state.ownerByPath[path] ?? "");
            }
        }
    }, state));
    vm.runInContext(extractFunction(sessionSource, "applyWallpaperPick"), context);
    return { context, modeCalls };
}

test("coerceWallpaperFolders normalizes appearance tags while preserving existing fields", () => {
    const coerced = sessionSpec.coerceWallpaperFolders([
        { path: "/walls/light", recursive: true, hidden: false, appearance: "light" },
        { path: "/walls/dark", recursive: false, hidden: true, appearance: "dark" },
        { path: "/walls/any", appearance: "any" },
        { path: "/walls/legacy" },
        { path: "/walls/invalid", appearance: "neon" }
    ]);
    assert.deepEqual(coerced.map(f => f.appearance), ["light", "dark", "", "", ""]);
    assert.equal(coerced[0].recursive, true);
    assert.equal(coerced[1].hidden, true);
});

test("selectedForMode filters by isLightMode and keeps All folders", () => {
    const folders = [
        { path: "/walls/light", hidden: false, appearance: "light" },
        { path: "/walls/dark", hidden: false, appearance: "dark" },
        { path: "/walls/shared", hidden: false, appearance: "" }
    ];
    const items = [
        { path: "/walls/light/a.jpg", folder: "/walls/light" },
        { path: "/walls/dark/b.jpg", folder: "/walls/dark" },
        { path: "/walls/shared/c.jpg", folder: "/walls/shared" }
    ];

    const lightLib = library(folders, { isLightMode: true });
    assert.deepEqual(lightLib.selectedForMode(items).map(i => i.path), ["/walls/light/a.jpg", "/walls/shared/c.jpg"]);

    const darkLib = library(folders, { isLightMode: false });
    assert.deepEqual(darkLib.selectedForMode(items).map(i => i.path), ["/walls/dark/b.jpg", "/walls/shared/c.jpg"]);
});

test("selectedForMode returns empty when no matching folders exist so caller controls fallback", () => {
    const folders = [
        { path: "/walls/light", hidden: false, appearance: "light" },
        { path: "/walls/dark", hidden: false, appearance: "dark" }
    ];
    const items = [{ path: "/walls/light/a.jpg", folder: "/walls/light" }];
    const darkLib = library(folders, { isLightMode: false });
    assert.deepEqual(darkLib.selectedForMode(items), []);
    assert.deepEqual(darkLib.selected(items).map(i => i.path), ["/walls/light/a.jpg"]);
});

test("applyWallpaperPick auto-switches light/dark mode via Theme.setLightMode unless perModeWallpaper is enabled", () => {
    const folders = [
        { path: "/walls", recursive: true, appearance: "" },
        { path: "/walls/light", recursive: true, appearance: "light" },
        { path: "/walls/dark", recursive: false, appearance: "dark" }
    ];
    const ownerByPath = {
        "/walls/light/sub/day.jpg": "/walls/light",
        "/walls/dark/night.jpg": "/walls/dark",
        "/walls/neutral.jpg": "/walls",
        "/walls/dark/nested/deep.jpg": "/walls",
        "/walls/light/day.jpg": "/walls/light"
    };

    const s1 = session({ isLightMode: false, wallpaperFolders: folders, ownerByPath });
    s1.context.applyWallpaperPick("", "/walls/light/sub/day.jpg");
    assert.deepEqual(s1.modeCalls, [{ light: true }]);
    assert.equal(s1.context.wallpaperPath, "/walls/light/sub/day.jpg");

    s1.context.applyWallpaperPick("", "/walls/dark/night.jpg");
    assert.deepEqual(s1.modeCalls, [{ light: true }, { light: false }]);

    // Unclassified / All folder keeps current mode
    s1.context.applyWallpaperPick("", "/walls/neutral.jpg");
    assert.equal(s1.modeCalls.length, 2);

    // Non-matching owner falls back without switching
    s1.context.applyWallpaperPick("", "/walls/dark/nested/deep.jpg");
    assert.equal(s1.modeCalls.length, 2);

    // perModeWallpaper skips mode switching
    const s2 = session({ isLightMode: false, perModeWallpaper: true, wallpaperFolders: folders, ownerByPath });
    s2.context.applyWallpaperPick("", "/walls/light/day.jpg");
    assert.deepEqual(s2.modeCalls, []);

    // themeModeAutoEnabled skips mode switching while still updating wallpaperPath
    const s3 = session({ isLightMode: false, themeModeAutoEnabled: true, wallpaperFolders: folders, ownerByPath });
    s3.context.applyWallpaperPick("", "/walls/light/day.jpg");
    assert.equal(s3.context.wallpaperPath, "/walls/light/day.jpg");
    assert.deepEqual(s3.modeCalls, []);
});
