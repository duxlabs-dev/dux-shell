import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Services/KeybindsService.qml", import.meta.url), "utf8");

function extract(name) {
    const found = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    if (!found)
        throw new Error(`${name} not found in KeybindsService.qml`);
    return found[0];
}

const calls = [];
const scope = vm.createContext({
    currentProvider: "hyprland",
    cheatsheetProvider: "",
    log: { info() {} },
    HyprlandService: { luaConfigActive: true },
    Quickshell: { execDetached: argv => calls.push(Array.from(argv)) },
    MangoService: { dispatch() {} }
});
vm.runInContext(extract("executeAction") + "\n" + extract("canExecuteAction"), scope);

test("hyprland runs the Lua dispatch as one argv entry and refuses legacy text without it", () => {
    scope.HyprlandService.luaConfigActive = true;
    const lua = 'hl.dsp.focus({ direction = "l" })';
    calls.length = 0;
    assert.equal(scope.executeAction("movefocus l", lua), true);
    assert.deepEqual(calls, [["hyprctl", "dispatch", lua]]);
    calls.length = 0;
    assert.equal(scope.executeAction("movefocus l", ""), false);
    assert.deepEqual(calls, []);
});

test("hyprland runs nothing without an active Lua config", () => {
    const lua = 'hl.dsp.focus({ direction = "l" })';
    const cases = [
        [true, lua, true],
        [true, "", false],
        [false, lua, false],
        [false, "", false]
    ];
    for (const [active, luaAction, expected] of cases) {
        scope.HyprlandService.luaConfigActive = active;
        calls.length = 0;
        assert.equal(scope.canExecuteAction("movefocus l", luaAction), expected, `can ${active} ${luaAction}`);
        assert.equal(scope.executeAction("movefocus l", luaAction), expected, `run ${active} ${luaAction}`);
        assert.equal(calls.length, expected ? 1 : 0);
    }
});

test("the shell field reads and writes the backslash escaping core uses", () => {
    const Actions = loadScript(new URL("../Common/KeybindActions.js", import.meta.url));
    const cases = [
        ["kitty --title foo", 'spawn sh -c "kitty --title foo"'],
        ["printf 'a\\n'", 'spawn sh -c "printf \'a\\\\n\'"'],
        ['grep "a b" C:\\tmp\\', 'spawn sh -c "grep \\"a b\\" C:\\\\tmp\\\\"'],
        ['echo \\"', 'spawn sh -c "echo \\\\\\""']
    ];
    for (const [command, action] of cases) {
        assert.equal(Actions.parseShellCommand(action), command, action);
        assert.equal(Actions.buildShellAction("niri", command, "sh"), action, command);
        assert.equal(Actions.getActionLabel(action, "niri"), command, action);
    }
});

test("the cheatsheet loads a custom config path when one is given", () => {
    const ctx = vm.createContext({ cheatsheetProvider: "niri", cheatsheetLoading: false, cheatsheetProcess: { running: false, command: [] } });
    vm.runInContext(extract("loadCheatsheet"), ctx);
    for (const [provider, path, expected] of [
        ["sway", "/etc/sway/config", ["dms", "keybinds", "show", "sway", "--path", "/etc/sway/config"]],
        ["", "", ["dms", "keybinds", "show", "niri"]]
    ]) {
        ctx.cheatsheetProcess.running = false;
        ctx.loadCheatsheet(provider, path);
        assert.deepEqual(Array.from(ctx.cheatsheetProcess.command), expected);
    }
});

test("niri argument fields keep quoted workspace names and land edits in the field they came from", () => {
    const Actions = loadScript(new URL("../Common/KeybindActions.js", import.meta.url));
    const edit = (action, changes) => {
        const parsed = Actions.parseCompositorActionArgs("niri", action);
        return Actions.buildCompositorAction("niri", parsed.base, Object.assign({}, parsed.args, changes));
    };
    assert.equal(edit('move-column-to-workspace "my work"', { focus: false }), 'move-column-to-workspace "my work" focus=false');
    assert.equal(edit("focus-workspace 3", { index: "my work" }), 'focus-workspace "my work"');
    assert.equal(edit('focus-workspace "a\\"b"', {}), 'focus-workspace "a\\"b"');
    assert.equal(edit("set-column-width -10%", {}), "set-column-width -10%");
    assert.deepEqual(Object.assign({}, Actions.parseCompositorActionArgs("niri", 'move-column-to-workspace "focus=false"').args), { index: "focus=false" });
});
