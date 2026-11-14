import assert from "node:assert/strict";
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";
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
        const original = prefix + " user config\n" + paths.includes.map(entry => prefix + " was " + entry.includeLine + "\n").join("");
        writeFileSync(paths.configFile, original);
        const fragment = paths.fragmentFiles[0];
        mkdirSync(dirname(fragment), { recursive: true });
        writeFileSync(fragment, "existing fragment\n");
        assert.notEqual(spawnSync("sh", ["-c", resolve.optedOutScriptFor(kind, compositor, configDir)]).status, 0, compositor + " a mention is not an opt out");
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

test("stop managing comments the include out in place, keeps the fragment, and setup restores it", t => {
    const directory = mkdtempSync(join(tmpdir(), "dms-disable-"));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const dms = directory + "/dms";
    writeFileSync(dms, '#!/bin/sh\nprintf \'{"exists":true,"included":false}\\n\'\n', { mode: 0o755 });
    for (const [compositor, kind, configName, before, live, after] of [
        ["niri", "animations", undefined, '// include "dms/animations.kdl"\ninclude optional=true "dms/layout.kdl"\n', ['include optional=true "dms/animations.kdl"'], '\nanimations {\n    slowdown 2.0\n}\n'],
        ["hyprland", "binds", undefined, 'require("dms.outputs")\n', ['require("dms.binds")', '    require "dms.binds-user"'], 'hl.bind("SUPER + Q", hl.dsp.exit())\n'],
        ["mango", "cursor", undefined, "source=./dms/layout.conf\n", ["source = ./dms/cursor.conf"], "cursor_size=24\n"],
        ["mango", "cursor", "config.toml", 'source = [\n    "./dms/layout.conf",\n', ['    "./dms/cursor.conf",'], ']\n[global]\nsource = "./dms/cursorx.conf"\n']
    ]) {
        const configDir = join(directory, compositor + (configName ?? ""));
        const paths = resolve.includePaths(kind, compositor, configDir, configName);
        const real = join(directory, "dotfiles-" + compositor + (configName ?? ""));
        const original = before + live.join("\n") + "\n" + after;
        writeFileSync(real, original);
        mkdirSync(dirname(paths.fragmentFiles[0]), { recursive: true });
        symlinkSync(real, paths.configFile);
        writeFileSync(paths.fragmentFiles[0], "fragment\n");

        const backup = paths.configFile + ".backup";
        const disable = resolve.disableScriptFor(kind, compositor, configDir, backup, configName);
        execFileSync("sh", ["-c", disable]);
        const token = compositor === "niri" ? "//" : compositor === "hyprland" ? "--" : "#";
        const disabled = before + live.map(line => token + " " + line).join("\n") + "\n" + after;
        assert.equal(readFileSync(paths.configFile, "utf8"), disabled, compositor + " disable");
        assert.equal(readFileSync(backup, "utf8"), original);
        assert.ok(lstatSync(paths.configFile).isSymbolicLink(), "a dotfiles symlink stays a link");
        assert.equal(readFileSync(paths.fragmentFiles[0], "utf8"), "fragment\n");
        spawnSync("sh", ["-c", disable]);
        assert.equal(readFileSync(paths.configFile, "utf8"), disabled, compositor + " disable twice");

        assert.equal(spawnSync("sh", ["-c", resolve.optedOutScriptFor(kind, compositor, configDir, configName)]).status, 0, compositor + " opted out");
        execFileSync("sh", ["-c", resolve.repairScriptFor(kind, compositor, configDir, "", configName, dms)]);
        assert.equal(readFileSync(paths.configFile, "utf8"), original, compositor + " setup restores in place");
    }
});

test("stop managing splits a one-line mango toml source array to comment out one element", t => {
    const configDir = mkdtempSync(join(tmpdir(), "dms-disable-array-"));
    t.after(() => rmSync(configDir, { recursive: true, force: true }));
    const dms = configDir + "/dms";
    writeFileSync(dms, '#!/bin/sh\nprintf \'{"exists":true,"included":false}\\n\'\n', { mode: 0o755 });
    const paths = resolve.includePaths("cursor", "mango", configDir, "config.toml");
    mkdirSync(dirname(paths.configFile), { recursive: true });
    const tail = '[bind.default]\n"SUPER+Return" = "spawn,foot"\n';
    writeFileSync(paths.configFile, '[global]\n  source = [ "./dms/layout.conf", "./dms/cursor.conf" ,"./dms/input.conf" ]\n' + tail);
    const split = element => '[global]\n  source = [\n      "./dms/layout.conf",\n' + element + '\n      "./dms/input.conf",\n  ]\n' + tail;

    execFileSync("sh", ["-c", resolve.disableScriptFor("cursor", "mango", configDir, "", "config.toml")]);
    assert.equal(readFileSync(paths.configFile, "utf8"), split('#       "./dms/cursor.conf",'));
    execFileSync("sh", ["-c", resolve.repairScriptFor("cursor", "mango", configDir, "", "config.toml", dms)]);
    assert.equal(readFileSync(paths.configFile, "utf8"), split('      "./dms/cursor.conf",'));
});

test("stop managing touches only a line that is just the include, in the table mango reads it from", t => {
    const directory = mkdtempSync(join(tmpdir(), "dms-disable-edge-"));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const dms = directory + "/dms";
    writeFileSync(dms, '#!/bin/sh\nprintf \'{"exists":true,"included":false}\\n\'\n', { mode: 0o755 });
    for (const [name, compositor, configName, original, disabled] of [
        ["a lua statement after the include", "hyprland", undefined, 'require("dms.cursor"); hl.config({})\n', null],
        ["a kdl node after the include", "niri", undefined, 'include "dms/cursor.kdl"; cursor { }\n', null],
        ["a comma inside a quoted toml path", "mango", "config.toml", '[global]\nsource = ["./other,a.conf", "./dms/cursor.conf"]\n', null],
        ["a lua comment after the include", "hyprland", undefined, 'require("dms.cursor") -- mine\n', '-- require("dms.cursor") -- mine\n'],
        ["a conf comment after the include", "mango", undefined, "source=./dms/cursor.conf # mine\n", "# source=./dms/cursor.conf # mine\n"],
        ["a single-quoted toml source with a comment", "mango", "config.toml", "[global]\nsource = './dms/cursor.conf' # mine\n", "[global]\n# source = './dms/cursor.conf' # mine\n"],
        ["an [env] variable named source", "mango", "config.toml", '[env]\nsource = "./dms/cursor.conf"\n[global]\nsource = "./dms/cursor.conf"\n', '[env]\nsource = "./dms/cursor.conf"\n[global]\n# source = "./dms/cursor.conf"\n'],
        ["no final newline", "mango", undefined, "a=1\nsource=./dms/cursor.conf", "a=1\n# source=./dms/cursor.conf"]
    ]) {
        const configDir = join(directory, name.replace(/\W+/g, "-"));
        const paths = resolve.includePaths("cursor", compositor, configDir, configName);
        mkdirSync(dirname(paths.fragmentFiles[0]), { recursive: true });
        writeFileSync(paths.configFile, original);
        spawnSync("sh", ["-c", resolve.disableScriptFor("cursor", compositor, configDir, "", configName)]);
        assert.equal(readFileSync(paths.configFile, "utf8"), disabled ?? original, name);
        if (!disabled)
            continue;
        execFileSync("sh", ["-c", resolve.repairScriptFor("cursor", compositor, configDir, "", configName, dms)]);
        assert.equal(readFileSync(paths.configFile, "utf8"), original, name + " restored");
    }
});

test("animations include resolves for every compositor that writes a fragment", () => {
    for (const [compositor, configName, fragment, includeLine] of [
        ["hyprland", undefined, "/c/hypr/dms/animations.lua", 'require("dms.animations")'],
        ["mango", undefined, "/c/mango/dms/animations.conf", "source=./dms/animations.conf"],
        ["mango", "config.toml", "/c/mango/dms/animations.conf", '[global]\nsource = "./dms/animations.conf"']
    ]) {
        const paths = resolve.includePaths("animations", compositor, "/c", configName);
        assert.ok(paths, compositor);
        assert.equal(paths.fragmentFiles.join(), fragment);
        assert.equal(paths.includes.map(entry => entry.includeLine).join(), includeLine);
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
