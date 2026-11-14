import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Common/SessionData.qml", import.meta.url), "utf8");
const SpecUtil = loadScript(new URL("../DCommon/Common/settings/SpecUtil.js", import.meta.url));
const keys = ["wallpaperPath", "wallpaperPathLight", "wallpaperPathDark", "perModeWallpaper", "perMonitorWallpaper", "monitorWallpapersLight", "monitorWallpapersDark", "isLightMode"];

function session(state) {
    const context = vm.createContext(Object.assign({
        isLightMode: false, wallpaperPath: "", wallpaperPathLight: "", wallpaperPathDark: "",
        perModeWallpaper: false, perMonitorWallpaper: false, monitorWallpapers: {}, monitorWallpapersLight: {}, monitorWallpapersDark: {},
        Qt: { callLater() {} },
        SpecUtil,
        Spec: { SPEC: Object.fromEntries(keys.map(k => [k, {}])) },
        SettingsData: { updateCosmicThemeMode() {} },
        Theme: { generateSystemThemesFromCurrentTheme() {} },
        saveSettings() {}
    }, state));
    vm.runInContext("var root = this;", context);
    for (const name of ["applyProfileValues", "setWallpaper", "setLightMode", "syncWallpaperForCurrentMode"]) {
        const fn = source.match(new RegExp(`^    function ${name}\\([^\\n]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
        if (!fn)
            throw new Error(`${name} not found in SessionData.qml`);
        vm.runInContext(fn[0], context);
    }
    return context;
}

const slots = { perModeWallpaper: true, wallpaperPathLight: "/light.jpg", wallpaperPathDark: "/dark.jpg" };

test("per-mode wallpaper slots are never overwritten by the single path", () => {
    for (const [name, live, values, shown] of [
        ["dark to light", { isLightMode: false }, { ...slots, isLightMode: true, wallpaperPath: "/light.jpg" }, "/light.jpg"],
        ["captured in dark, applied in light", { isLightMode: true }, { ...slots, wallpaperPath: "/dark.jpg" }, "/light.jpg"],
        ["per-monitor with a stale single path", { isLightMode: true }, { ...slots, perMonitorWallpaper: true, wallpaperPath: "/stale.jpg" }, "/stale.jpg"]
    ]) {
        const context = session(Object.assign({ wallpaperPath: "/old.jpg", wallpaperPathLight: "/oldl.jpg", wallpaperPathDark: "/oldd.jpg" }, live));
        context.applyProfileValues(values);
        assert.deepEqual([context.wallpaperPathLight, context.wallpaperPathDark, context.wallpaperPath], ["/light.jpg", "/dark.jpg", shown], name);
    }
});

test("a mode-only profile with per-mode wallpapers switches to the other mode's wallpaper", () => {
    const context = session({ isLightMode: false, perModeWallpaper: true, wallpaperPath: "/d.jpg", wallpaperPathLight: "/l.jpg", wallpaperPathDark: "/d.jpg" });
    context.applyProfileValues({ isLightMode: true });
    assert.deepEqual([context.isLightMode, context.wallpaperPath, context.wallpaperPathDark], [true, "/l.jpg", "/d.jpg"]);
});
