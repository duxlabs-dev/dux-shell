import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Actions = loadScript(new URL("../Common/KeybindActions.js", import.meta.url));
const flag = name => Actions.getDmsActionArgs().screenshot.args.find(f => f.name === name);

test("screenshot binds are read only when every word is one the editor writes", () => {
    const cases = [
        ["spawn dms screenshot", {}],
        ["spawn dms screenshot --no-file", { save: false }],
        ["spawn dms screenshot full --no-clipboard=false --cursor=off", { clipboard: true, cursor: false }],
        ["spawn dms screenshot --no-file --no-file=false", { save: true }],
        ["spawn dms screenshot scroll --clipboard-file", { "clipboard-file": true }],
        ["spawn dms screenshot -f jpg --no-file", null],
        ["spawn dms screenshot --cursor on", null],
        ["spawn dms screenshot --filename shot\\ ", null],
        ["spawn dms screenshot --no-file | swappy -f -", null],
        ["spawn dms screenshot scroll --cursor=on", null]
    ];
    for (const [action, args] of cases) {
        const parsed = Actions.parseDmsActionArgs(action);
        assert.equal(parsed.opaque === true, args === null, action);
        if (args)
            assert.deepEqual({ ...parsed.args }, args, action);
    }
});

test("a rebuilt screenshot bind keeps its meaning", () => {
    const parsed = Actions.parseDmsActionArgs("spawn dms screenshot window --no-file --clipboard-file=false");
    const args = Object.assign({}, parsed.args, { clipboard: true, cursor: false, "clipboard-file": undefined });
    assert.equal(Actions.buildDmsAction(parsed.base, args), "spawn dms screenshot window --no-file --no-clipboard=false --cursor=off");
});

test("unset outputs follow settings unless the bind turned the other one off", () => {
    const settings = { screenshotSaveFile: false, screenshotClipboard: false };
    assert.equal(Actions.dmsFlagDefault(flag("save"), {}, settings), false);
    assert.equal(Actions.dmsFlagDefault(flag("save"), { clipboard: false }, settings), true);
    assert.equal(Actions.dmsFlagDefault(flag("clipboard"), { save: false }, settings), true);
});
