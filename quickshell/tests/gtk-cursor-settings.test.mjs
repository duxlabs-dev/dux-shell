import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");

function gtkCursorScript() {
    const start = source.indexOf("    function _gtkCursorScript(");
    assert.notEqual(start, -1, "SettingsData.qml lost _gtkCursorScript");
    const end = source.indexOf("\n    }", start) + 6;
    const context = vm.createContext({});
    vm.runInContext(source.slice(start, end), context);
    return context._gtkCursorScript();
}

function withHome(files, run) {
    const home = mkdtempSync(join(tmpdir(), "dms-gtk-cursor-"));
    const config = join(home, ".config");
    try {
        for (const [path, content] of Object.entries(files)) {
            const full = join(home, path);
            mkdirSync(join(full, ".."), { recursive: true });
            writeFileSync(full, content);
        }
        execFileSync("sh", ["-c", gtkCursorScript(), "sh", "Breeze_Light", "32", config, home]);
        run(path => (existsSync(join(home, path)) ? readFileSync(join(home, path), "utf8") : null));
    } finally {
        rmSync(home, { recursive: true, force: true });
    }
}

test("existing GTK cursor entries are replaced", () => {
    withHome({
        ".config/gtk-3.0/settings.ini": "[Settings]\ngtk-theme-name=Breeze\ngtk-cursor-theme-name=breeze_cursors\ngtk-cursor-theme-size=24\n",
        ".gtkrc-2.0": 'gtk-theme-name="Breeze"\ngtk-cursor-theme-name="breeze_cursors"\ngtk-cursor-theme-size=24\n',
        ".config/xsettingsd/xsettingsd.conf": 'Gtk/CursorThemeName "breeze_cursors"\nGtk/CursorThemeSize 24\nNet/ThemeName "Breeze"\n'
    }, read => {
        assert.equal(read(".config/gtk-3.0/settings.ini"), "[Settings]\ngtk-theme-name=Breeze\ngtk-cursor-theme-name=Breeze_Light\ngtk-cursor-theme-size=32\n");
        assert.equal(read(".gtkrc-2.0"), 'gtk-theme-name="Breeze"\ngtk-cursor-theme-name="Breeze_Light"\ngtk-cursor-theme-size=32\n');
        assert.equal(read(".config/xsettingsd/xsettingsd.conf"), 'Gtk/CursorThemeName "Breeze_Light"\nGtk/CursorThemeSize 32\nNet/ThemeName "Breeze"\n');
    });
});

test("settings.ini gets the entries added, created when missing", () => {
    withHome({
        ".config/gtk-3.0/settings.ini": "[Settings]\ngtk-icon-theme-name=Papirus\n"
    }, read => {
        assert.equal(read(".config/gtk-3.0/settings.ini"), "[Settings]\ngtk-cursor-theme-name=Breeze_Light\ngtk-cursor-theme-size=32\ngtk-icon-theme-name=Papirus\n");
        assert.equal(read(".config/gtk-4.0/settings.ini"), "[Settings]\ngtk-cursor-theme-name=Breeze_Light\ngtk-cursor-theme-size=32\n");
    });
});

test("gtkrc-2.0 and xsettingsd are left alone when they set no cursor", () => {
    withHome({
        ".gtkrc-2.0": 'gtk-theme-name="Breeze"\n',
        ".config/xsettingsd/xsettingsd.conf": 'Net/ThemeName "Breeze"\n'
    }, read => {
        assert.equal(read(".gtkrc-2.0"), 'gtk-theme-name="Breeze"\n');
        assert.equal(read(".config/xsettingsd/xsettingsd.conf"), 'Net/ThemeName "Breeze"\n');
    });
});

test("settings.ini without a Settings section gets one appended", () => {
    withHome({
        ".config/gtk-4.0/settings.ini": "# managed by hand\n"
    }, read => {
        assert.equal(read(".config/gtk-4.0/settings.ini"), "# managed by hand\n\n[Settings]\ngtk-cursor-theme-name=Breeze_Light\ngtk-cursor-theme-size=32\n");
    });
});
