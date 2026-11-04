import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const binds = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/niri/binds.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), binds);

const argv = (action, provider) => {
    const out = binds.spawnArgv(action, provider);
    return out === null ? null : Array.from(out);
};

test("niri spawn runs an argument list, never a shell", () => {
    assert.deepEqual(argv("spawn alacritty", "niri"), ["alacritty"]);
    assert.deepEqual(argv('spawn "dms" "ipc" "call" "spotlight" "toggle"', "niri"), ["dms", "ipc", "call", "spotlight", "toggle"]);
    assert.deepEqual(argv('spawn notify-send "a b; rm -rf ~" $HOME', "niri"), ["notify-send", "a b; rm -rf ~", "$HOME"]);
    assert.deepEqual(argv('spawn dms ipc call brightness increment 5 ""', "niri"), ["dms", "ipc", "call", "brightness", "increment", "5", ""]);
});

test("an sh -c spawn keeps its command line as one argument, escapes undone", () => {
    assert.deepEqual(argv('spawn sh -c "chrome --app=\\"x y\\""', "niri"), ["sh", "-c", 'chrome --app="x y"']);
});

test("spawn-sh hands its one command line to sh, as niri does", () => {
    assert.deepEqual(argv('spawn-sh "grim - | wl-copy"', "niri"), ["sh", "-c", "grim - | wl-copy"]);
    assert.deepEqual(argv("spawn-sh grim - | wl-copy", "niri"), ["sh", "-c", "grim - | wl-copy"]);
});

test("other compositors keep their shell spawn", () => {
    assert.deepEqual(argv("spawn ~/bin/x && y", "hyprland"), ["sh", "-c", "~/bin/x && y"]);
    assert.deepEqual(argv("exec firefox", "hyprland"), ["sh", "-c", "firefox"]);
    assert.deepEqual(argv("spawn_shell foot", "mangowc"), ["sh", "-c", "foot"]);
});

test("a spawn with nothing to run gives an empty list, other actions null", () => {
    assert.deepEqual(argv("spawn ", "niri"), []);
    assert.equal(argv("close-window", "niri"), null);
    assert.equal(argv("spawner", "niri"), null);
    assert.equal(argv("", "niri"), null);
});

test("niri actions go to niri msg as arguments, properties as flags", () => {
    assert.deepEqual(Array.from(binds.niriActionArgv("focus-workspace 3")), ["niri", "msg", "action", "focus-workspace", "3"]);
    assert.deepEqual(Array.from(binds.niriActionArgv('focus-workspace "web; reboot"')), ["niri", "msg", "action", "focus-workspace", "web; reboot"]);
    assert.deepEqual(Array.from(binds.niriActionArgv("quit skip-confirmation=true")), ["niri", "msg", "action", "quit", "--skip-confirmation"]);
    assert.deepEqual(Array.from(binds.niriActionArgv("quit skip-confirmation=false")), ["niri", "msg", "action", "quit"]);
    assert.deepEqual(Array.from(binds.niriActionArgv('screenshot show-pointer="false"')), ["niri", "msg", "action", "screenshot", "--show-pointer=false"]);
});
