import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

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
