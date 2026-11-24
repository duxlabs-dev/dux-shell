import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const IconFolders = loadScript(new URL("../Common/IconFolders.js", import.meta.url));
const SPEC = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC;
const state = { base: "Papirus-Dark", applied: "Papirus-Dark-dms-1a2b3c4d", recipe: "papirus", inputs: "x" };

test("the applied name is the overlay only for the picked pack with recoloring on", () => {
    assert.equal(IconFolders.appliedName("Papirus-Dark", true, state), "Papirus-Dark-dms-1a2b3c4d");
    assert.equal(IconFolders.appliedName("Papirus-Dark", false, state), "Papirus-Dark");
    assert.equal(IconFolders.appliedName("Papirus-Dark", true, null), "Papirus-Dark");
    assert.equal(IconFolders.appliedName("breeze", true, state), "breeze");
    assert.equal(IconFolders.appliedName("System Default", true, { base: "System Default", applied: "System Default-dms-1a2b3c4d" }), "System Default");
});

test("a state naming anything but a hashed overlay of its base is not applied", () => {
    for (const applied of ["Adwaita", "breeze-dms-00ff00ff", "Papirus-Dark-dms-a", "Papirus-Dark-dms-1A2B3C4D", "Papirus-Dark-dms-1a2b3c4", "Papirus-Dark-dms-1a2b3c4d5", "Papirus-Dark-dms-9f8e7d6c'; rm -rf ~; '", "", null])
        assert.equal(IconFolders.appliedName("Papirus-Dark", true, { base: "Papirus-Dark", applied }), "Papirus-Dark");
    assert.equal(IconFolders.appliedName("Papirus-Dark", true, { base: "breeze", applied: "Papirus-Dark-dms-9f8e7d6c" }), "Papirus-Dark");
});

test("the state file parses to null unless it names a base and an applied theme", () => {
    assert.equal(IconFolders.parseState(JSON.stringify(state)).applied, "Papirus-Dark-dms-1a2b3c4d");
    for (const text of ["", "{", "null", "[]", '{"base":"Papirus-Dark"}', '{"base":1,"applied":"x"}'])
        assert.equal(IconFolders.parseState(text), null);
});

test("a probe keeps its code for the settings row and is null without a supported flag", () => {
    const probe = IconFolders.parseProbe('{"supported":false,"code":"no-colored-folders","recipe":"papirus","reason":"Icon theme has no folder icons that can be recolored"}');
    assert.deepEqual({ ...probe }, { supported: false, code: "no-colored-folders", reason: "Icon theme has no folder icons that can be recolored" });
    assert.equal(IconFolders.parseProbe('{"supported":true}').code, "");
    for (const text of ["", "Error: unknown command", '{"code":"supported"}'])
        assert.equal(IconFolders.parseProbe(text), null);
});

test("the theme list hides overlays and reports an overlay system theme as its pack", () => {
    const found = IconFolders.parseThemeList("SYSDEFAULT:Papirus-Dark-dms-9f8e7d6c\nAdwaita\nPapirus-Dark\nPapirus-Dark-dms-9f8e7d6c\nPapirus-Dark-dms-1a2b3c4d\n\nmy-dms-theme\nPapirus-Dark-dms-a\n");
    assert.deepEqual(Array.from(found.themes), ["System Default", "Adwaita", "Papirus-Dark", "my-dms-theme", "Papirus-Dark-dms-a"]);
    assert.equal(found.systemDefault, "Papirus-Dark");
    assert.equal(IconFolders.parseThemeList("").systemDefault, null);
});

test("an overlay of a picked pack is not drift, another theme or another pack's overlay is", () => {
    const picks = ["Papirus-Dark", "Papirus-Light"];
    for (const platform of ["Papirus-Dark", "Papirus-Light-dms-0badc0de", "Papirus-Dark-dms-1a2b3c4d", "Tela"])
        assert.equal(IconFolders.isOwn(platform, "Tela", picks), true, platform);
    for (const platform of ["Adwaita", "breeze-dms-00ff00ff", "Papirus"])
        assert.equal(IconFolders.isOwn(platform, "Tela", picks), false, platform);
});

test("the shell form of baseName strips exactly what the script form does", () => {
    const names = ["Papirus-Dark-dms-9f8e7d6c", "Papirus-Dark-dms-a", "Papirus-Dark-dms-1A2B3C4D", "Papirus-Dark-dms-1a2b3c4", "Papirus-Dark-dms-1a2b3c4d5", "Papirus-Dark", "a-dms-00000000-dms-ffffffff", "x-dms-0123456g"];
    const out = execFileSync("sh", ["-c", `for cur in "$@"; do printf '%s\\n' "${IconFolders.shBase("cur")}"; done`, "sh", ...names], { encoding: "utf8" });
    assert.deepEqual(out.trim().split("\n"), names.map(name => IconFolders.baseName(name)));
});

test("recolored icons resolve to files inside the applied overlay directory", () => {
    const dir = "/home/u/.local/share/icons/Papirus-Dark-dms-1a2b3c4d";
    const full = { ...state, dir, icons: { folder: "48x48/places/folder.svg", constructor: "64x64/places/constructor.svg", up: "../../Papirus/folder.svg", abs: "/etc/passwd", empty: "" } };
    const found = IconFolders.manifest("Papirus-Dark", true, full);
    assert.equal(IconFolders.iconUrl(found, "folder"), "file://" + dir + "/48x48/places/folder.svg");
    assert.equal(IconFolders.iconUrl(found, "constructor"), "file://" + dir + "/64x64/places/constructor.svg");
    for (const name of ["firefox", "toString", "up", "abs", "empty", ""])
        assert.equal(IconFolders.iconUrl(found, name), "", name);
    assert.equal(IconFolders.iconUrl(null, "folder"), "");

    assert.equal(IconFolders.manifest("Papirus-Dark", false, full), null);
    assert.equal(IconFolders.manifest("breeze", true, full), null);
    assert.equal(IconFolders.manifest("Papirus-Dark", true, state), null);
    for (const other of ["/home/u/.local/share/icons/Papirus-Dark-dms-9f8e7d6c", "/home/u/.local/share/icons/Papirus-Dark", dir + "/", "icons/Papirus-Dark-dms-1a2b3c4d", ""])
        assert.equal(IconFolders.manifest("Papirus-Dark", true, { ...full, dir: other }), null, other);
    assert.equal(IconFolders.manifest("Papirus-Dark", true, { ...full, icons: "folder" }), null);
});

test("the backup never saves the picked pack or one of its overlays", () => {
    const dir = mkdtempSync(join(tmpdir(), "dms-icon-backup-"));
    const file = join(dir, "gtk-3.0", "icon-theme.dms-backup");
    const script = IconFolders.backupScript(`'${file}'`, `printf '%s' "$CUR"`, "'Papirus-Dark'");
    const run = cur => {
        rmSync(join(dir, "gtk-3.0"), { recursive: true, force: true });
        execFileSync("sh", ["-c", script], { env: { ...process.env, CUR: cur } });
        return existsSync(file) ? readFileSync(file, "utf8") : null;
    };
    try {
        for (const cur of ["", "Papirus-Dark", "Papirus-Dark-dms-1a2b3c4d", "Papirus-Dark-dms-9f8e7d6c"])
            assert.equal(run(cur), null, cur);
        assert.equal(run("Adwaita"), "Adwaita\n");
        assert.equal(run("breeze-dms-00ff00ff"), "breeze\n");
        execFileSync("sh", ["-c", script], { env: { ...process.env, CUR: "Tela" } });
        assert.equal(readFileSync(file, "utf8"), "breeze\n");
    } finally {
        rmSync(dir, { recursive: true, force: true });
    }
});

test("the generator is owed an overlay, a clear only after something was generated, or nothing", () => {
    assert.equal(IconFolders.wanted("Papirus-Dark", true, false), "apply:Papirus-Dark");
    assert.equal(IconFolders.wanted("Papirus-Dark", false, false), "");
    assert.equal(IconFolders.wanted("System Default", false, false), "");
    assert.equal(IconFolders.wanted("Papirus-Dark", false, true), "clear");
    assert.equal(IconFolders.wanted("System Default", true, true), "clear");
    assert.equal(IconFolders.args("apply:Papirus-Dark", "light", "/cache/dms").join(" "), "matugen icon-folders --state-dir /cache/dms --icon-theme Papirus-Dark --mode light");
    assert.equal(IconFolders.args("clear", "light", "/cache/dms").join(" "), "matugen icon-folders --state-dir /cache/dms --clear");
    assert.equal(IconFolders.wanted("Papirus-Dark", true, false, "app-style=themed"), "apply:Papirus-Dark", "the style belongs to Dux Icons only");
});

test("a finished request runs again once, and only when its overlay is not the one on disk", () => {
    const want = "apply:Papirus-Dark";
    assert.equal(IconFolders.needsRun(want, "", "", false, false), true);
    assert.equal(IconFolders.needsRun(want, "apply:breeze", want, true, true), true);
    assert.equal(IconFolders.needsRun(want, want, "", true, true), false);
    assert.equal(IconFolders.needsRun(want, want, "", false, false), false);
    assert.equal(IconFolders.needsRun(want, want, "", true, false), true);
    assert.equal(IconFolders.needsRun(want, want, want, true, false), false);
    assert.equal(IconFolders.needsRun("clear", "clear", "", false, false), false);
});

test("Dux Icons is generated whenever it is picked, with the app icon option in the request", () => {
    const built = { base: "dux-icons", applied: "dux-icons-dms-1a2b3c4d" };
    assert.equal(IconFolders.generates("dux-icons", false), true);
    assert.equal(IconFolders.label("dux-icons"), "Dux Icons");
    assert.equal(IconFolders.label("Papirus-Dark"), "Papirus-Dark");
    assert.equal(IconFolders.generates("Papirus-Dark", false), false);
    assert.equal(IconFolders.generates("System Default", true), false);

    assert.equal(IconFolders.style("color", "circle", false), "shape=circle", "every known shape is named");
    assert.equal(IconFolders.style("color", "blob", false), "", "an unknown shape is left to the pack");
    assert.equal(IconFolders.style("themed", "squircle", true), "app-style=themed,gradient,shape=squircle");
    assert.equal(IconFolders.wanted("dux-icons", false, false, ""), "apply:dux-icons");
    assert.equal(IconFolders.wanted("dux-icons", false, false, "app-style=themed"), "apply/app-style=themed:dux-icons");
    assert.equal(IconFolders.packOf("apply/app-style=themed,shape=hexagon:dux-icons"), "dux-icons");
    assert.equal(IconFolders.packOf("apply:Pack:With:Colons"), "Pack:With:Colons");
    assert.equal(IconFolders.packOf("clear"), "");
    assert.equal(IconFolders.args("apply/app-style=themed,gradient,shape=squircle:dux-icons", "dark", "/cache/dms").join(" "), "matugen icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode dark --app-style themed --gradient --shape squircle");
    assert.deepEqual(Array.from(IconFolders.styleArgs("gradient,shape=cookie", "icon-")), ["--icon-gradient", "--icon-shape", "cookie"]);
    assert.deepEqual(Array.from(IconFolders.styleArgs("", "icon-")), []);

    assert.equal(IconFolders.appliedName("dux-icons", true, built), "dux-icons-dms-1a2b3c4d");
    assert.equal(IconFolders.indexName("dux-icons", true, built), "dux-icons-dms-1a2b3c4d", "the shell indexes the whole generated pack");
    assert.equal(IconFolders.indexName("dux-icons", true, null), "dux-icons");

    // An Icon= that is a file path never reaches a theme lookup; the pack lists the icon it built from it.
    const listed = Object.assign({ dir: "/icons/dux-icons-dms-1a2b3c4d", icons: { "/opt/app/icon.png": "scalable/apps/app.svg" } }, built);
    const paths = IconFolders.manifest("dux-icons", true, listed);
    assert.equal(IconFolders.iconUrl(paths, "/opt/app/icon.png"), "file:///icons/dux-icons-dms-1a2b3c4d/scalable/apps/app.svg");
    assert.equal(IconFolders.iconUrl(paths, "/opt/other/icon.png"), "");
    assert.equal(IconFolders.manifest("dux-icons", true, built), null);
    assert.equal(IconFolders.indexName("Papirus-Dark", true, state), "Papirus-Dark", "a folder overlay is resolved by path, never indexed");
});

test("Dux Icons base options reach the style only away from the generator's defaults", () => {
    // Generator defaults, not settings defaults: only these stay off the command line.
    const defaults = { color: "theme", source: "score", style: "tonal", tone: -1, ownTone: -1 };
    assert.equal(IconFolders.style("color", "squircle", false, defaults), "shape=squircle", "the generator defaults keep the old style and command line");
    assert.equal(IconFolders.style("color", "squircle", false), "shape=squircle");
    assert.equal(IconFolders.style("color", "squircle", false, { ...defaults, color: "app" }), "shape=squircle,tile-color=app");
    assert.equal(IconFolders.style("color", "circle", true, { color: "app", source: "common", style: "content", tone: 35, ownTone: 80 }), "gradient,shape=circle,tile-color=app,color-source=common,tile-style=content,tile-tone=35,own-tone=80");
    assert.equal(IconFolders.style("color", "", false, { ...defaults, source: "common", style: "neutral" }), "", "a source and a style only go with the app's own color");
    for (const color of ["edge", "ring"]) {
        assert.equal(IconFolders.style("color", "", false, { ...defaults, color }), `tile-color=${color}`, `${color} at its defaults names only the color`);
        assert.equal(IconFolders.style("color", "", false, { ...defaults, color, source: "common", style: "content" }), `tile-color=${color},color-source=common`, `${color} takes a source but no style`);
    }
    assert.equal(IconFolders.style("color", "", false, { ...defaults, tone: 0, ownTone: 98 }), "tile-tone=0,own-tone=98");
    for (const bad of [{ color: "blue" }, { color: "app", source: "x", style: "loud" }, { tone: 101 }, { tone: 2.5 }, { tone: "50" }, { ownTone: 39 }, { ownTone: 99 }])
        assert.equal(IconFolders.style("color", "", false, bad).replace("tile-color=app", ""), "", JSON.stringify(bad));

    const style = "shape=rounded,tile-color=app,color-source=common,tile-style=neutral,tile-tone=40,own-tone=90";
    assert.deepEqual(Array.from(IconFolders.styleArgs(style, "icon-")), ["--icon-shape", "rounded", "--icon-tile-color", "app", "--icon-color-source", "common", "--icon-tile-style", "neutral", "--icon-tile-tone", "40", "--icon-own-tone", "90"]);
    assert.deepEqual(Array.from(IconFolders.styleArgs("unknown=1,tile-tone=5", "")), ["--tile-tone", "5"], "an unknown part is dropped");
    assert.equal(IconFolders.args(`apply/${style}:dux-icons`, "dark", "/cache/dms").join(" "), "matugen icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode dark --shape rounded --tile-color app --color-source common --tile-style neutral --tile-tone 40 --own-tone 90");
    assert.equal(IconFolders.packOf(`apply/${style}:dux-icons`), "dux-icons");
    assert.deepEqual(Array.from(IconFolders.styleArgs("tile-color=ring,color-source=common", "")), ["--tile-color", "ring", "--color-source", "common"]);
});

test("a Themed or Monochrome app style is sent by name and drops the options only Color draws", () => {
    const tile = { color: "app", source: "common", style: "content", tone: 35, ownTone: 80, files: "color" };
    for (const appStyle of ["themed", "monochrome"]) {
        const style = IconFolders.style(appStyle, "circle", true, tile);
        assert.equal(style, `app-style=${appStyle},gradient,shape=circle,tile-tone=35,file-style=color`);
        assert.equal(IconFolders.colorApps(appStyle), false, appStyle);
        assert.deepEqual(Array.from(IconFolders.runArgs("dux-icons", style)), ["--icon-app-style", appStyle, "--icon-gradient", "--icon-shape", "circle", "--icon-tile-tone", "35", "--icon-file-style", "color"]);
        assert.equal(IconFolders.args(IconFolders.wanted("dux-icons", false, false, style), "light", "/cache/dms").join(" "), `matugen icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode light --app-style ${appStyle} --gradient --shape circle --tile-tone 35 --file-style color`);
    }
    for (const appStyle of ["color", "Themed", "mono", "", undefined, true]) {
        assert.equal(IconFolders.colorApps(appStyle), true, String(appStyle));
        assert.equal(IconFolders.style(appStyle, "circle", true, tile), "gradient,shape=circle,tile-color=app,color-source=common,tile-style=content,tile-tone=35,own-tone=80,file-style=color", String(appStyle));
    }
    assert.notEqual(IconFolders.style("themed", "circle", false), IconFolders.style("monochrome", "circle", false), "each style is its own request");
});

test("a Tinted app style keeps the per-app tile options and drops only the Dux app tone", () => {
    const tile = { color: "ring", source: "common", style: "content", tone: 35, ownTone: 80, files: "color" };
    assert.equal(IconFolders.colorApps("tinted"), false);
    assert.equal(IconFolders.tiledApps("tinted"), true);
    assert.equal(IconFolders.tiledApps("themed"), false);
    assert.equal(IconFolders.tiledApps("color"), true);
    const style = IconFolders.style("tinted", "circle", false, tile);
    assert.equal(style, "app-style=tinted,shape=circle,tile-color=ring,color-source=common,tile-tone=35,file-style=color");
    assert.deepEqual(Array.from(IconFolders.runArgs("dux-icons", style)), ["--icon-app-style", "tinted", "--icon-shape", "circle", "--icon-tile-color", "ring", "--icon-color-source", "common", "--icon-tile-tone", "35", "--icon-file-style", "color"]);
});

test("the tile style goes with a tile made from the logo's seed: App color, and Edge Match in Tinted", () => {
    const tile = { source: "common", style: "content" };
    for (const [appStyle, color, styled] of [
        ["color", "app", true],
        ["tinted", "app", true],
        ["tinted", "edge", true],
        ["color", "edge", false],
        ["color", "ring", false],
        ["tinted", "ring", false],
        ["tinted", "theme", false],
        ["themed", "app", false],
        ["monochrome", "edge", false]
    ]) {
        const name = `${appStyle} ${color}`;
        assert.equal(IconFolders.tileStyled(appStyle, color), styled, name);
        assert.equal(IconFolders.style(appStyle, "", false, { ...tile, color }).includes("tile-style=content"), styled, name);
    }
});

test("the shipped Dux Icons settings defaults draw themed squircles with colored files, sent on the command line", () => {
    assert.equal(SPEC.iconShape.def, "squircle");
    assert.equal(SPEC.iconTileColor.def, "edge");
    assert.equal(SPEC.iconColorSource.def, "common");
    assert.equal(SPEC.iconFileStyle.def, "color");
    assert.equal(SPEC.iconAppStyle.def, "themed");
    assert.equal(SPEC.iconGradient.def, false);
    assert.equal(SPEC.iconTileTone.def, -1);
    assert.equal(SPEC.iconOwnTone.def, -1);
    const style = IconFolders.style(SPEC.iconAppStyle.def, SPEC.iconShape.def, SPEC.iconGradient.def, {
        color: SPEC.iconTileColor.def,
        source: SPEC.iconColorSource.def,
        style: SPEC.iconTileStyle.def,
        tone: SPEC.iconTileTone.def,
        ownTone: SPEC.iconOwnTone.def,
        files: SPEC.iconFileStyle.def
    });
    assert.equal(style, "app-style=themed,shape=squircle,file-style=color", "every setting off the generator's own default is sent, and the tile color settings stay out of Themed");
    assert.equal(IconFolders.args(IconFolders.wanted("dux-icons", false, false, style), "dark", "/cache/dms").join(" "), "matugen icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode dark --app-style themed --shape squircle --file-style color");
    assert.deepEqual(Array.from(IconFolders.styleArgs(style, "icon-")), ["--icon-app-style", "themed", "--icon-shape", "squircle", "--icon-file-style", "color"]);
});

test("Dux Icons colored files reach the generator only when picked", () => {
    assert.equal(IconFolders.style("color", "rounded", false, { files: "standard" }), "shape=rounded", "standard files keep the old style and command line");
    for (const bad of ["papirus", "Color", "", undefined])
        assert.equal(IconFolders.style("color", "rounded", false, { files: bad }), "shape=rounded", String(bad));
    const style = IconFolders.style("color", "rounded", false, { color: "ring", ownTone: 70, files: "color" });
    assert.equal(style, "shape=rounded,tile-color=ring,own-tone=70,file-style=color");
    assert.deepEqual(Array.from(IconFolders.styleArgs(style, "icon-")), ["--icon-shape", "rounded", "--icon-tile-color", "ring", "--icon-own-tone", "70", "--icon-file-style", "color"]);
    assert.equal(IconFolders.args(IconFolders.wanted("dux-icons", false, false, style), "dark", "/cache/dms").join(" "), "matugen icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode dark --shape rounded --tile-color ring --own-tone 70 --file-style color");
    assert.notEqual(IconFolders.wanted("dux-icons", false, false, style), IconFolders.wanted("dux-icons", false, false, "shape=rounded,tile-color=ring,own-tone=70"), "a new file style is a new request");
});

test("small panels swap a Dux Icons app icon for its tile-free copy only when the build wrote one", () => {
    const dir = "/icons/dux-icons-dms-1a2b3c4d";
    const bare = { base: "dux-icons", applied: "dux-icons-dms-1a2b3c4d", inputs: "x", dir, bare: true };
    const tiled = `file://${dir}/scalable/apps/discord.svg`;
    assert.equal(IconFolders.bareUrl("dux-icons", true, bare, tiled), `file://${dir}/bare/apps/discord.svg`);
    for (const [picked, enabled, built, url] of [
        ["dux-icons", true, { ...bare, bare: false }, tiled],
        ["dux-icons", false, bare, tiled],
        ["Papirus-Dark", true, bare, tiled],
        ["dux-icons", true, bare, `file://${dir}/scalable/places/folder.svg`],
        ["dux-icons", true, bare, `file://${dir}/scalable/apps/../places/folder.svg`],
        ["dux-icons", true, bare, "file:///usr/share/icons/hicolor/scalable/apps/discord.svg"],
        ["dux-icons", true, { ...bare, dir: "/icons/other" }, "file:///icons/other/scalable/apps/discord.svg"],
        ["dux-icons", true, null, tiled],
        ["dux-icons", true, bare, ""]
    ])
        assert.equal(IconFolders.bareUrl(picked, enabled, built, url), "", `${picked} ${url}`);
});

test("the theme list offers Dux Icons once, installed as a theme or only as its command", () => {
    const found = IconFolders.parseThemeList("Adwaita\ndux-icons\ndux-icons\ndux-icons-dms-1a2b3c4d\n");
    assert.deepEqual(Array.from(found.themes), ["System Default", "Adwaita", "dux-icons"]);

    const home = mkdtempSync(join(tmpdir(), "dms-icons-"));
    try {
        const list = env => execFileSync("/bin/sh", ["-c", IconFolders.shListSelf() + "; true"], { encoding: "utf8", env });
        assert.equal(list({ HOME: home, PATH: "/nonexistent" }), "");
        execFileSync("sh", ["-c", 'mkdir -p "$1/.local/bin" && : > "$1/.local/bin/dux-icons" && chmod +x "$1/.local/bin/dux-icons"', "sh", home]);
        assert.equal(list({ HOME: home, PATH: "/nonexistent" }), "dux-icons\n");
    } finally {
        rmSync(home, { recursive: true, force: true });
    }
});

test("picking Dux Icons generates without the folder toggle and clears after leaving it", () => {
    const { context, calls } = settings({ iconFolderRecolor: false, iconThemeDark: "dux-icons", iconStyle: "app-style=themed" });
    context.applyStoredIconTheme();
    assert.deepEqual(calls.runs, ["icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode dark --app-style themed"]);
    assert.deepEqual(calls.applied, [], "the pack is applied under its generated name, once");

    context.finish(JSON.stringify({ base: "dux-icons", applied: "dux-icons-dms-1a2b3c4d" }));
    context._setIconFolderState({ base: "dux-icons", applied: "dux-icons-dms-1a2b3c4d" });
    assert.deepEqual(calls.applied, ["dux-icons-dms-1a2b3c4d"]);

    context.iconStyle = "shape=rounded";
    context.applyStoredIconTheme();
    assert.equal(calls.runs.at(-1), "icon-folders --state-dir /cache/dms --icon-theme dux-icons --mode dark --shape rounded");

    context.finish(JSON.stringify({ base: "dux-icons", applied: "dux-icons-dms-9f8e7d6c" }));
    context._setIconFolderState({ base: "dux-icons", applied: "dux-icons-dms-9f8e7d6c" });
    context.iconThemeDark = "Papirus-Dark";
    context.iconFolderState = null;
    context.applyStoredIconTheme();
    assert.equal(calls.applied.at(-1), "Papirus-Dark");
    context.clearDelayFires();
    assert.equal(calls.runs.at(-1), "icon-folders --state-dir /cache/dms --clear");
});

function functionSource(name, file = "SettingsData.qml") {
    const source = readFileSync(new URL(`../Common/${file}`, import.meta.url), "utf8");
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in ${file}`);
    return found[0];
}

const cleared = JSON.stringify({ base: "", applied: "", recipe: "", inputs: "" });
const overlay = base => ({ base, applied: base + "-dms-1a2b3c4d" });

function settings(values, session) {
    const calls = { applied: [], runs: [], reloads: 0, restored: 0, saves: 0 };
    const context = vm.createContext(Object.assign({
        IconFolders,
        calls,
        iconThemeDark: "Papirus-Dark",
        iconThemeLight: "Papirus-Light",
        iconThemePerMode: false,
        iconFolderRecolor: true,
        iconStyle: "",
        iconFolderState: null,
        _requestedIconTheme: "",
        _iconFoldersRunning: "",
        _iconFoldersDone: "",
        _iconFoldersRetried: "",
        _iconFoldersGenerated: false,
        _stateDir: "/cache/dms",
        SessionData: Object.assign({ isLightMode: false, lastAppliedIconTheme: "", iconFoldersPresent: false, saveSettings: () => calls.saves++ }, session),
        Proc: { dmsBin: "dms" },
        iconFoldersProcess: {
            command: [],
            _running: false,
            get running() {
                return this._running;
            },
            set running(value) {
                this._running = value;
                if (value)
                    calls.runs.push(this.command.slice(2).join(" "));
            }
        },
        iconFoldersClearDelay: {
            running: false,
            start() {
                this.running = true;
            },
            stop() {
                this.running = false;
            }
        },
        iconFolderStateView: { reload: () => calls.reloads++ },
        // Real writers read the name at call time, so the mock must too.
        updateGtkIconTheme: () => calls.applied.push(context.resolveAppliedIconTheme()),
        updateQtIconTheme() {},
        updateCosmicIconTheme() {},
        restoreIconTheme: () => calls.restored++
    }, values));
    for (const name of ["resolveIconTheme", "resolveAppliedIconTheme", "_generatesIconTheme", "applyStoredIconTheme", "_applyIconTheme", "_reapplyIconThemeIfChanged", "_wantedIconFolders", "_setIconFoldersPresent", "_syncIconFolders", "_startIconFolders", "_startIconFoldersClear", "_iconFoldersFinished", "_iconFoldersStartFailed", "_initIconFolders", "themeRunFinished", "_setIconFolderState"])
        vm.runInContext(functionSource(name), context);
    context.finish = output => {
        context.iconFoldersProcess._running = false;
        context._iconFoldersFinished(output);
    };
    context.clearDelayFires = () => {
        assert.equal(context.iconFoldersClearDelay.running, true, "no clear is waiting");
        context.iconFoldersClearDelay.running = false;
        context._startIconFoldersClear();
    };
    return { context, calls };
}

test("nothing is spawned or scheduled while the feature has never been on", () => {
    for (const iconThemeDark of ["Papirus-Dark", "System Default"]) {
        const { context, calls } = settings({ iconFolderRecolor: false, iconThemeDark });
        context._initIconFolders();
        context.applyStoredIconTheme();
        context.themeRunFinished(false);
        assert.deepEqual(calls.runs, []);
        assert.equal(context.iconFoldersClearDelay.running, false);
        assert.equal(calls.reloads + calls.saves, 0);
    }
});

test("a pack switch generates under the picked name first and applies the overlay once", () => {
    const { context, calls } = settings({ iconFolderState: overlay("breeze"), iconThemePerMode: true }, { isLightMode: true, lastAppliedIconTheme: "breeze-dms-1a2b3c4d" });
    context.applyStoredIconTheme();
    assert.deepEqual(calls.applied, []);
    assert.deepEqual(calls.runs, ["icon-folders --state-dir /cache/dms --icon-theme Papirus-Light --mode light"]);
    assert.equal(context.SessionData.iconFoldersPresent, true);

    context.finish(JSON.stringify(overlay("Papirus-Light")));
    assert.equal(calls.reloads, 1);
    context._setIconFolderState(overlay("Papirus-Light"));
    context._setIconFolderState(overlay("Papirus-Light"));
    assert.deepEqual(calls.applied, ["Papirus-Light-dms-1a2b3c4d"]);
    assert.equal(calls.runs.length, 1);
});

test("a pack that cannot be recolored is applied under its own name without a second call", () => {
    const { context, calls } = settings({}, { lastAppliedIconTheme: "breeze-dms-1a2b3c4d" });
    context.applyStoredIconTheme();
    context.finish("");
    context._setIconFolderState(null);
    assert.deepEqual(calls.applied, ["Papirus-Dark"]);
    assert.equal(calls.runs.length, 1);

    const failed = settings({});
    failed.context.applyStoredIconTheme();
    failed.context._iconFoldersStartFailed();
    assert.equal(failed.context._iconFoldersRunning, "apply:Papirus-Dark");
    failed.context.iconFoldersProcess._running = false;
    failed.context._iconFoldersStartFailed();
    failed.context._setIconFolderState(null);
    assert.deepEqual(failed.calls.applied, ["Papirus-Dark"]);
});

test("a new overlay from a theme run is applied without another generator call", () => {
    const { context, calls } = settings({ iconFolderState: state, _iconFoldersDone: "apply:Papirus-Dark", _iconFoldersGenerated: true }, { lastAppliedIconTheme: "Papirus-Dark-dms-1a2b3c4d", iconFoldersPresent: true });
    context.themeRunFinished(true);
    assert.equal(calls.reloads, 1);
    context._setIconFolderState(state);
    assert.deepEqual(calls.applied, []);
    context._setIconFolderState({ base: "Papirus-Dark", applied: "Papirus-Dark-dms-9f8e7d6c" });
    assert.deepEqual(calls.applied, ["Papirus-Dark-dms-9f8e7d6c"]);
    assert.deepEqual(calls.runs, []);
});

test("turning the feature off applies the picked name, then clears once whatever was last applied", () => {
    const { context, calls } = settings({ iconFolderRecolor: false }, { lastAppliedIconTheme: "Papirus-Dark", iconFoldersPresent: true });
    context.applyStoredIconTheme();
    assert.deepEqual(calls.applied, ["Papirus-Dark"]);
    assert.deepEqual(calls.runs, []);
    context.clearDelayFires();
    assert.deepEqual(calls.runs, ["icon-folders --state-dir /cache/dms --clear"]);

    context.finish(cleared);
    assert.equal(context.SessionData.iconFoldersPresent, false);
    context.applyStoredIconTheme();
    assert.equal(context.iconFoldersClearDelay.running, false);
    assert.equal(calls.runs.length, 1);
});

test("a clear that failed stays owed without being repeated in this session", () => {
    const { context, calls } = settings({ iconFolderRecolor: false, iconThemeDark: "System Default" }, { iconFoldersPresent: true });
    context.applyStoredIconTheme();
    assert.equal(calls.restored, 1);
    context.clearDelayFires();
    context.finish("");
    context.applyStoredIconTheme();
    assert.equal(context.SessionData.iconFoldersPresent, true);
    assert.equal(context.iconFoldersClearDelay.running, false);
    assert.equal(calls.runs.length, 1);
});

test("startup regenerates when the feature is on and finishes a clear the last session owed", () => {
    const on = settings({ iconFolderState: state }, { lastAppliedIconTheme: "Papirus-Dark-dms-1a2b3c4d", iconFoldersPresent: true });
    on.context._initIconFolders();
    assert.deepEqual(on.calls.runs, ["icon-folders --state-dir /cache/dms --icon-theme Papirus-Dark --mode dark"]);
    assert.deepEqual(on.calls.applied, []);

    const off = settings({ iconFolderRecolor: false }, { lastAppliedIconTheme: "Papirus-Dark-dms-1a2b3c4d", iconFoldersPresent: true });
    off.context._initIconFolders();
    assert.deepEqual(off.calls.applied, ["Papirus-Dark"]);
    off.context.clearDelayFires();
    assert.deepEqual(off.calls.runs, ["icon-folders --state-dir /cache/dms --clear"]);
});

test("turning the feature back on during a clear generates after it and keeps the marker", () => {
    const { context, calls } = settings({ iconFolderRecolor: false }, { iconFoldersPresent: true });
    context.applyStoredIconTheme();
    context.clearDelayFires();
    context.iconFolderRecolor = true;
    context.applyStoredIconTheme();
    assert.equal(calls.runs.length, 1);
    assert.deepEqual(calls.applied, ["Papirus-Dark"]);

    context.finish(cleared);
    assert.equal(context.SessionData.iconFoldersPresent, true);
    context._setIconFolderState(null);
    assert.equal(calls.runs[1], "icon-folders --state-dir /cache/dms --icon-theme Papirus-Dark --mode dark");
    context.finish(JSON.stringify(state));
    context._setIconFolderState(state);
    assert.deepEqual(calls.applied, ["Papirus-Dark", "Papirus-Dark-dms-1a2b3c4d"]);
    assert.equal(calls.runs.length, 2);
});

test("turning the feature back on before the clear starts cancels it", () => {
    const { context, calls } = settings({ iconFolderRecolor: false }, { iconFoldersPresent: true });
    context.applyStoredIconTheme();
    context.iconFolderRecolor = true;
    context.applyStoredIconTheme();
    assert.equal(context.iconFoldersClearDelay.running, false);
    assert.deepEqual(calls.runs, ["icon-folders --state-dir /cache/dms --icon-theme Papirus-Dark --mode dark"]);
});

test("a pick made while another pack generates is generated next and is the one applied", () => {
    const { context, calls } = settings({ iconThemeDark: "breeze" });
    context.applyStoredIconTheme();
    context.iconThemeDark = "Papirus-Dark";
    context.applyStoredIconTheme();
    assert.equal(calls.runs.length, 1);

    context.finish(JSON.stringify(overlay("breeze")));
    context._setIconFolderState(overlay("breeze"));
    assert.equal(calls.runs[1], "icon-folders --state-dir /cache/dms --icon-theme Papirus-Dark --mode dark");
    assert.deepEqual(calls.applied, []);
    context.finish(JSON.stringify(state));
    context._setIconFolderState(state);
    assert.deepEqual(calls.applied, ["Papirus-Dark-dms-1a2b3c4d"]);
    assert.equal(calls.runs.length, 2);
});

test("a state overwritten by an older run is corrected once, then the picked name is kept", () => {
    const { context, calls } = settings({});
    context.applyStoredIconTheme();
    context.finish(JSON.stringify(state));
    context._setIconFolderState(overlay("breeze"));
    assert.equal(calls.runs.length, 2);
    assert.deepEqual(calls.applied, []);

    context.finish(JSON.stringify(state));
    context._setIconFolderState(overlay("breeze"));
    context._setIconFolderState(overlay("breeze"));
    assert.equal(calls.runs.length, 2);
    assert.deepEqual(calls.applied, ["Papirus-Dark"]);
});

test("a theme run that outlived the feature is cleared again", () => {
    const { context, calls } = settings({ iconFolderRecolor: false }, { iconFoldersPresent: true });
    context.applyStoredIconTheme();
    context.clearDelayFires();
    context.finish(cleared);
    context.themeRunFinished(true);
    assert.equal(context.SessionData.iconFoldersPresent, true);
    context.clearDelayFires();
    assert.deepEqual(calls.runs, ["icon-folders --state-dir /cache/dms --clear", "icon-folders --state-dir /cache/dms --clear"]);
});

const defaultIconStyle = IconFolders.style(SPEC.iconAppStyle.def, SPEC.iconShape.def, SPEC.iconGradient.def, {
    color: SPEC.iconTileColor.def,
    source: SPEC.iconColorSource.def,
    style: SPEC.iconTileStyle.def,
    tone: SPEC.iconTileTone.def,
    ownTone: SPEC.iconOwnTone.def,
    files: SPEC.iconFileStyle.def
});

// SettingsData.iconStyleRunArgs as its binding in SettingsData.qml evaluates it.
function iconStyleRunArgs(iconTheme, iconStyle = defaultIconStyle) {
    const source = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
    const found = source.match(/^    readonly property var iconStyleRunArgs: (.+)$/m);
    if (!found)
        throw new Error("iconStyleRunArgs not found in SettingsData.qml");
    return Array.from(vm.runInContext(found[1], vm.createContext({ IconFolders, iconTheme, iconStyle })));
}

function themeRun(iconThemeGenerated, appliedKey, runArgs = iconStyleRunArgs("Papirus-Dark")) {
    const iconStyleRunArgs = runArgs;
    const context = vm.createContext({
        matugenAvailable: true,
        workerRunning: false,
        stateDir: "/cache/dms",
        shellDir: "/shell",
        configDir: "/config",
        colorsFileLoadFailed: false,
        _matugenRunKey: appliedKey,
        CacheData: { matugenAppliedKey: appliedKey },
        Proc: { dmsBin: "dms" },
        Qt: { md5: text => createHash("md5").update(text).digest("hex") },
        log: { info() {}, warn() {}, debug() {} },
        themeGenerationStarting() {},
        systemThemeGenerator: { command: null, running: false },
        // Unset keys read as absent or default, as on a fresh profile.
        SettingsData: new Proxy({ iconThemeGenerated, iconStyleRunArgs, runDmsMatugenTemplates: true, terminalOpacity: 100, terminalPalette: "default", matugenContrast: 0, matugenSpec: "2021" }, {
            get: (target, key) => key in target ? target[key] : String(key).startsWith("matugenTemplate") || key === "runUserMatugenTemplates"
        })
    });
    vm.runInContext(functionSource("setDesiredTheme", "Theme.qml"), context);
    context.setDesiredTheme("image", "/w/a.png", false, "Papirus-Dark", "scheme-tonal-spot", null);
    return { command: context.systemThemeGenerator.command, key: context._matugenRunKey };
}

test("a theme run asks for folder colors only with the toggle on, and the toggle changes the run key", () => {
    const off = themeRun(false, "");
    // Pre-toggle arguments: any extra flag would re-run every profile once after upgrade.
    assert.deepEqual(Array.from(off.command), ["dms", "matugen", "queue", "--state-dir", "/cache/dms", "--shell-dir", "/shell", "--config-dir", "/config", "--kind", "image", "--value", "/w/a.png", "--mode", "dark", "--icon-theme", "Papirus-Dark", "--matugen-type", "scheme-tonal-spot"]);
    assert.equal(themeRun(false, off.key).command, null);

    const on = themeRun(true, off.key);
    assert.deepEqual(Array.from(on.command), [...off.command, "--icon-folders"]);
    assert.notEqual(on.key, off.key);

    const styled = ["--icon-app-style", "themed", "--icon-shape", "squircle"];
    assert.deepEqual(Array.from(themeRun(true, off.key, styled).command), [...off.command, "--icon-folders", ...styled]);
    assert.equal(themeRun(false, off.key, styled).command, null, "a style alone asks for nothing");
});

test("a theme run sends the Dux Icons style only when Dux Icons is the pick", () => {
    assert.deepEqual(iconStyleRunArgs("dux-icons"), ["--icon-app-style", "themed", "--icon-shape", "squircle", "--icon-file-style", "color"]);
    const styled = IconFolders.style("themed", "clover", true, { color: "ring", tone: 40, ownTone: 70, files: "color" });
    assert.deepEqual(iconStyleRunArgs("dux-icons", styled), ["--icon-app-style", "themed", "--icon-gradient", "--icon-shape", "clover", "--icon-tile-tone", "40", "--icon-file-style", "color"]);
    // Only the self-built pack takes style flags: older dms builds fail on unknown flags.
    for (const picked of ["Papirus-Dark", "System Default", ""]) {
        assert.deepEqual(iconStyleRunArgs(picked), [], picked);
        assert.deepEqual(iconStyleRunArgs(picked, styled), [], picked);
    }
    const papirus = themeRun(true, "", iconStyleRunArgs("Papirus-Dark", styled));
    assert.equal(papirus.command.filter(arg => arg.startsWith("--icon-")).join(" "), "--icon-theme --icon-folders");
    assert.equal(papirus.key, themeRun(true, "").key, "a Dux Icons setting does not change a Papirus run");
});

// Values made inside the script's context have its prototypes, which a strict comparison tells apart.
const plain = value => JSON.parse(JSON.stringify(value));

test("the theme library keeps only named themes and the icon files they resolved", () => {
    const text = JSON.stringify({ themes: [{ name: "Papirus", removable: true, icons: ["/i/folder.svg", "", "/i/home.svg", 3, "relative.svg"] }, { name: "breeze", icons: [] }, { icons: ["/x.svg"] }, { name: "Bad", icons: "x" }, null] });
    assert.deepEqual(plain(IconFolders.parseLibrary(text)), { Papirus: { removable: true, icons: ["/i/folder.svg", "/i/home.svg"] }, breeze: { removable: false, icons: [] } });
    for (const broken of ["", "{", "null", "[]", '{"themes":3}'])
        assert.deepEqual(plain(IconFolders.parseLibrary(broken)), {});
});

test("every tile shape has an outline to preview it with", () => {
    assert.deepEqual(plain(IconFolders.shapes()), ["circle", "squircle", "rounded", "square", "hexagon", "cookie", "clover"]);
    for (const shape of IconFolders.shapes()) {
        const svg = decodeURIComponent(IconFolders.shapeUrl(shape, "#69b2ff").replace("data:image/svg+xml;utf8,", ""));
        assert.match(svg, /^<svg [^>]*viewBox="0 0 64 64" fill="#69b2ff"><(circle|rect|path) [^<>]+\/><\/svg>$/, shape);
    }
});

test("shell tiles take the Dux Icons outline only while its generated pack is in use", () => {
    const built = { base: "dux-icons", applied: "dux-icons-dms-1a2b3c4d" };
    assert.equal(IconFolders.tileShape("dux-icons", true, built, "cookie"), "cookie");
    assert.equal(IconFolders.tileShape("dux-icons", true, built, "blob"), "circle", "the pack draws circles for a shape it does not know");
    for (const [picked, enabled, applied] of [["dux-icons", true, null], ["dux-icons", false, built], ["Papirus-Dark", true, state], ["System Default", false, null]])
        assert.equal(IconFolders.tileShape(picked, enabled, applied, "cookie"), "", picked);
    assert.equal(IconFolders.outlinePath("circle"), "", "the circle stays a rounded Rectangle");
    for (const shape of IconFolders.shapes().slice(1))
        assert.match(IconFolders.outlinePath(shape), /^M[\d. ]+[A-Z][^"<>]*Z$/, shape);
});

test("a folder's previews sit on a grid inside every outline, in reading order", () => {
    const insets = { circle: 0.707, squircle: 0.84, rounded: 0.871, square: 0.998, hexagon: 0.648, cookie: 0.646, clover: 0.803 };
    for (const shape of IconFolders.shapes()) {
        for (const count of [1, 2, 3, 4]) {
            const slots = [...Array(count).keys()].map(i => IconFolders.gridSlot(shape, count, i, false));
            for (const s of slots)
                assert.ok(Math.max(Math.abs(s.x - 0.5), Math.abs(s.y - 0.5)) + s.size / 2 <= insets[shape] / 2, `${shape} ${count} stays inside the outline`);
            for (let i = 0; i < count; i++)
                for (let j = i + 1; j < count; j++)
                    assert.ok(Math.max(Math.abs(slots[i].x - slots[j].x), Math.abs(slots[i].y - slots[j].y)) >= slots[i].size, `${shape} ${count}: ${i} and ${j} overlap`);
            const mirrored = [...Array(count).keys()].map(i => IconFolders.gridSlot(shape, count, i, true));
            assert.deepEqual(mirrored.map(s => [+(1 - s.x).toFixed(6), +s.y.toFixed(6)]), slots.map(s => [+s.x.toFixed(6), +s.y.toFixed(6)]), `${shape} ${count} mirrors in RTL`);
        }
        const four = [0, 1, 2, 3].map(i => IconFolders.gridSlot(shape, 4, i, false));
        assert.ok(four[0].x < four[1].x && four[0].y === four[1].y && four[2].y > four[0].y && four[2].x === four[0].x, shape);
        const three = [0, 1, 2].map(i => IconFolders.gridSlot(shape, 3, i, false));
        assert.equal(three[2].x, 0.5, `${shape}: the third preview is centered under the first two`);
    }
});

test("cursor library keeps removable flags and PNG data URL pointers", () => {
    const png = "data:image/png;base64,iVBORw0KGgo=";
    const hand = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==";
    const text = JSON.stringify({ themes: [], cursors: [{ name: "Adwaita", removable: true, pointer: png, cursors: [png, hand, "/bad.png"] }, { name: "Hypr", removable: false, pointer: "" }, { name: "File", pointer: "/usr/share/x.png" }, { pointer: png }, { name: "Bad", pointer: 3 }, null] });
    assert.deepEqual(plain(IconFolders.parseCursorLibrary(text)), {
        Adwaita: { removable: true, pointer: png, cursors: [png, hand] },
        Hypr: { removable: false, pointer: "", cursors: [] },
        File: { removable: false, pointer: "", cursors: [] },
        Bad: { removable: false, pointer: "", cursors: [] },
    });
    for (const broken of ["", "{", "null", '{"cursors":3}', '{"themes":[]}'])
        assert.deepEqual(plain(IconFolders.parseCursorLibrary(broken)), {});
});

test("an install or remove reply carries its themes, and a refusal its code", () => {
    assert.deepEqual(plain(IconFolders.parseReply('{"themes":["Foo","Foo-Dark"]}')), { themes: ["Foo", "Foo-Dark"], code: "", reason: "" });
    assert.deepEqual(plain(IconFolders.parseReply('{"code":"exists","themes":["Foo",7],"error":"already installed"}')), { themes: ["Foo"], code: "exists", reason: "already installed" });
    for (const broken of ["", "not json", "null", '{"themes":"Foo","code":1,"error":{}}'])
        assert.deepEqual(plain(IconFolders.parseReply(broken)), { themes: [], code: "", reason: "" });
});
