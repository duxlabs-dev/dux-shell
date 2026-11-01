import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { loadScript } from "./qml-script.mjs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import vm from "node:vm";
import test from "node:test";

const resolve = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/ConfigIncludeResolve.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), resolve);
const plain = value => JSON.parse(JSON.stringify(value));

test("includePaths joins the compositor directory, with hypr for hyprland", () => {
    const hyprland = resolve.includePaths("layout", "hyprland", "/home/u/.config");
    assert.equal(hyprland.configFile, "/home/u/.config/hypr/hyprland.lua");
    assert.deepEqual(plain(hyprland.fragmentFiles), ["/home/u/.config/hypr/dms/layout.lua"]);
    assert.equal(resolve.includePaths("colors", "mango", "/home/u/.config"), null, "no spec, no paths");
});

test("resolveIncludeArgs spells mango as mangowc and names the fragment", () => {
    assert.deepEqual(plain(resolve.resolveIncludeArgs("outputs", "niri")), ["niri", "outputs.kdl"]);
    assert.deepEqual(plain(resolve.resolveIncludeArgs("windowrules", "mango")), ["mangowc", "windowrules.conf"]);
    assert.equal(resolve.resolveIncludeArgs("colors", "mango"), null, "no spec, no args");
});

test("repair preserves config and fragments, backs up, and adds live includes only once", t => {
    const directory = mkdtempSync(join(tmpdir(), "dms-includes-"));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    for (const [compositor, kind, prefix] of [["niri", "outputs", "//"], ["hyprland", "binds", "--"], ["mango", "binds", "#"]]) {
        const configDir = join(directory, compositor + " space's");
        const paths = resolve.includePaths(kind, compositor, configDir);
        mkdirSync(dirname(paths.configFile), { recursive: true });
        const original = prefix + " user config\n" + paths.includes.map(entry => prefix + " " + entry.includeLine + "\n").join("");
        writeFileSync(paths.configFile, original);
        const fragment = paths.fragmentFiles[0];
        mkdirSync(dirname(fragment), { recursive: true });
        writeFileSync(fragment, "existing fragment\n");
        const backup = paths.configFile + ".backup";
        execFileSync("sh", ["-c", resolve.repairScriptFor(kind, compositor, configDir, backup)]);
        assert.equal(readFileSync(backup, "utf8"), original);
        assert.equal(readFileSync(fragment, "utf8"), "existing fragment\n");
        for (const file of paths.fragmentFiles)
            assert.ok(existsSync(file));
        const repaired = readFileSync(paths.configFile, "utf8");
        assert.ok(repaired.startsWith(original));
        const live = repaired.split("\n").filter(line => !line.trimStart().startsWith(prefix));
        for (const { includeLine } of paths.includes)
            assert.equal(live.filter(line => line === includeLine).length, 1);
        if (compositor === "hyprland")
            assert.ok(live.indexOf(paths.includes[0].includeLine) < live.indexOf(paths.includes[1].includeLine));
        execFileSync("sh", ["-c", resolve.repairScriptFor(kind, compositor, configDir, "")]);
        assert.equal(readFileSync(paths.configFile, "utf8"), repaired);
    }
});

test("mango input fragment maps choices onto libinput numbers and spells numlock in snake_case", () => {
    const SPEC = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC;
    const source = readFileSync(new URL("../Services/MangoService.qml", import.meta.url), "utf8");
    const found = source.match(/^    function mangoInputLines\([^)]*\) \{\n[\s\S]*?^    \}/m);
    assert.ok(found, "mangoInputLines not found in MangoService.qml");
    const scope = vm.createContext({});
    vm.runInContext(found[0], scope);
    const defaults = Object.fromEntries(Object.keys(SPEC).filter(key => /^(mouse|touchpad|keyboard)[A-Z]|^focusFollowsMouse$/.test(key)).map(key => [key, SPEC[key].def]));
    const lines = overrides => [...scope.mangoInputLines(Object.assign({}, defaults, overrides))];
    const value = (list, key) => list.find(line => line.startsWith(key + "="))?.slice(key.length + 1);

    const stock = lines({});
    assert.equal(value(stock, "trackpad_natural_scrolling"), "1");
    assert.equal(value(stock, "mouse_accel_profile"), undefined, "default profile leaves the key to Mango");
    assert.ok(!stock.some(line => /^(xkb_rules_|repeat_|numlock)/.test(line)), "unconfigured keyboard writes nothing");

    const chosen = lines({ mouseScrollMethod: "no-scroll", touchpadAccelProfile: "adaptive", touchpadScrollMethod: "on-button-down", touchpadClickMethod: "clickfinger", touchpadDisableOnExternalMouse: true, keyboardLayouts: "us,de", keyboardRepeatDelay: 300 });
    assert.equal(value(chosen, "mouse_scroll_method"), "0");
    assert.equal(value(chosen, "trackpad_accel_profile"), "2");
    assert.equal(value(chosen, "trackpad_scroll_method"), "4");
    assert.equal(value(chosen, "trackpad_click_method"), "2");
    assert.equal(value(chosen, "trackpad_send_events_mode"), "2");
    assert.equal(value(chosen, "xkb_rules_layout"), "us,de");
    assert.equal(value(chosen, "xkb_rules_variant"), undefined, "empty fields stay out");
    assert.equal(value(chosen, "repeat_delay"), "300");
    assert.equal(value(chosen, "numlock_on"), "0");
    assert.equal(value(lines({ keyboardNumlock: true }), "numlock_on"), "1");

    assert.equal(value(stock, "sloppy_focus"), undefined, "untouched focus mode stays Mango's");
    for (const mode of [0, 1])
        assert.equal(value(lines({ focusFollowsMouse: mode }), "sloppy_focus"), String(mode));
});
