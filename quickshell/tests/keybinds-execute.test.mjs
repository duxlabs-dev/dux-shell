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

const Binds = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/niri/binds.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), Binds);

const Keymaps = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/niri/keymaps.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), Keymaps);

const calls = [];
const logged = [];
const scope = vm.createContext({
    Binds,
    currentProvider: "hyprland",
    cheatsheetProvider: "",
    log: { info: (...args) => logged.push(args.join(" ")) },
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

test("niri spawn runs its argument list without a shell and logs only the action name", () => {
    scope.currentProvider = "niri";
    calls.length = 0;
    logged.length = 0;
    assert.equal(scope.executeAction('spawn notify-send "a; rm -rf ~"'), true);
    assert.deepEqual(calls, [["notify-send", "a; rm -rf ~"]]);
    assert.deepEqual(logged, ["Executing keybind action: spawn"]);
    calls.length = 0;
    assert.equal(scope.executeAction("focus-workspace 2"), true);
    assert.deepEqual(calls, [["niri", "msg", "action", "focus-workspace", "2"]]);
    scope.currentProvider = "hyprland";
});

const groupsScope = vm.createContext({ _flatCache: [] });
vm.runInContext(extract("bindKeyData") + "\n" + extract("bindGroups") + "\n" + extract("keysForAction"), groupsScope);

function conflictBind(key, conflictAction) {
    return {
        key: key,
        action: "spawn foot",
        desc: "Foot",
        source: "dms-default",
        cooldownMs: 250,
        flags: "lock",
        allowWhenLocked: true,
        allowInhibiting: false,
        repeat: false,
        conflict: { key: key, action: conflictAction, source: "config" }
    };
}

test("a conflict on each key of one action plans one double per key, undo fields kept", () => {
    const groups = groupsScope.bindGroups({
        "Execute": [conflictBind("Mod+T", "spawn alacritty"), conflictBind("Mod+Return", "spawn kitty"), conflictBind("Mod+F", "spawn fuzzel")]
    }, ["Execute"]);
    const plan = Array.from(Keymaps.doubleBinds(groups, "Super"));
    assert.deepEqual(plan.map(b => b.key), ["Mod+T", "Mod+Return", "Mod+F"]);
    assert.deepEqual({ ...plan[0] }, {
        key: "Mod+T",
        action: "spawn foot",
        desc: "Foot",
        cooldownMs: 250,
        flags: "lock",
        allowWhenLocked: true,
        allowInhibiting: false,
        repeat: false,
        trigger: "",
        releaseAction: ""
    });
});

test("keys of one action group apart when their release action differs", () => {
    const groups = groupsScope.bindGroups({
        "Execute": [
            { key: "Mod+V", action: "spawn a", source: "dms" },
            { key: "Mod+B", action: "spawn a", trigger: "both", releaseAction: "spawn b", source: "dms" },
            { key: "Mod+N", action: "spawn a", trigger: "both", releaseAction: "spawn b", source: "dms" }
        ]
    }, ["Execute"]);
    assert.deepEqual(Array.from(groups, g => [g.releaseAction, g.keys.map(k => k.key).join(" ")]), [["", "Mod+V"], ["spawn b", "Mod+B Mod+N"]]);
});

test("a conflict on a press and release key keeps its release action and the group description", () => {
    const groups = groupsScope.bindGroups({
        "Execute": [
            { key: "Mod+B", action: "spawn a", trigger: "both", releaseAction: "spawn b", desc: "Hold", source: "dms" },
            { key: "Mod+M", action: "spawn a", trigger: "both", releaseAction: "spawn b", source: "dms", conflict: { key: "Mod+M", action: "spawn c", source: "config" } }
        ]
    }, ["Execute"]);
    assert.equal(groups.length, 2);
    assert.equal(groups[1].releaseAction, "spawn b");
    assert.equal(groups[1].desc, "Hold");
});

test("the clean-up record keeps trigger, release action and pass-through for the undo", () => {
    const groups = groupsScope.bindGroups({
        "Execute": [
            { key: "Mod+T", action: "spawn alacritty", source: "config" },
            { key: "Super+T", action: "spawn foot", trigger: "release", passThrough: true, source: "dms" },
            { key: "Mod+M", action: "spawn a", trigger: "both", releaseAction: "spawn b", passThrough: false, source: "dms-default", conflict: { key: "Mod+M", action: "spawn c", source: "config" } }
        ]
    }, ["Execute"]);
    const plan = Array.from(Keymaps.doubleBinds(groups, "Super")).map(b => [b.key, b.trigger, b.releaseAction, b.passThrough]);
    assert.deepEqual(plan, [["Super+T", "release", "", true], ["Mod+M", "both", "spawn b", false]]);
});

test("one conflict plans one double and the other keys of the action stay together", () => {
    const groups = groupsScope.bindGroups({
        "Execute": [conflictBind("Mod+T", "spawn alacritty"), { key: "Mod+Return", action: "spawn foot", desc: "Foot", source: "dms-default" }]
    }, ["Execute"]);
    assert.deepEqual(Array.from(Keymaps.doubleKeys(groups, "Super")), ["Mod+T"]);
    assert.equal(groups.length, 2);
    groupsScope._flatCache = groups;
    assert.deepEqual(Array.from(groupsScope.keysForAction("spawn foot")), ["Mod+T", "Mod+Return"]);
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
