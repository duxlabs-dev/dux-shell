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

test("mango toml repair sources the fragment from config.toml under its own [global]", t => {
    const configDir = mkdtempSync(join(tmpdir(), "dms-includes-toml-"));
    t.after(() => rmSync(configDir, { recursive: true, force: true }));
    const dms = configDir + "/dms";
    writeFileSync(dms, '#!/bin/sh\n[ "$*" = "config resolve-include mangowc cursor.conf" ] || exit 2\nprintf \'{"exists":true,"included":%s}\\n\' "$INCLUDED"\n', { mode: 0o755 });
    const configFile = configDir + "/mango/config.toml";
    mkdirSync(dirname(configFile), { recursive: true });
    const varSource = '[var]\ndir = "./dms"\n[global]\nsource = "$dir/cursor.conf"\n';
    for (const [name, included, original, want] of [
        ["a source written with a var", "true", varSource, varSource],
        ["no trailing newline", "false", '[global]\nsource = ["./dms/layout.conf"]\n[bind.default]\n"SUPER+Return" = "spawn,foot"', '[global]\nsource = ["./dms/layout.conf"]\n[bind.default]\n"SUPER+Return" = "spawn,foot"\n[global]\nsource = "./dms/cursor.conf"\n'],
        ["a mention core does not count", "false", '[env]\nsource = "./dms/cursor.conf"\n', '[env]\nsource = "./dms/cursor.conf"\n[global]\nsource = "./dms/cursor.conf"\n'],
        ["no dms source yet", "false", '[bind.default]\n"SUPER+Return" = "spawn,foot"\n', '[bind.default]\n"SUPER+Return" = "spawn,foot"\n\n# DMS Include Configs\n[global]\nsource = "./dms/cursor.conf"\n']
    ]) {
        writeFileSync(configFile, original);
        execFileSync("sh", ["-c", resolve.repairScriptFor("cursor", "mango", configDir, "", "config.toml", dms)], { env: { ...process.env, INCLUDED: included } });
        assert.equal(readFileSync(configFile, "utf8"), want, name);
    }
    assert.ok(!existsSync(configDir + "/mango/config.conf"), "a config.conf would shadow config.toml");
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
