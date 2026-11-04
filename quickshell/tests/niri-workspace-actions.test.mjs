import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

// The singleton imports qs.*, which qmltestrunner cannot resolve, so its functions run here against fakes.
const source = readFileSync(new URL("../Services/NiriWorkspaceActions.qml", import.meta.url), "utf8");
const Close = loadScript(new URL("../Common/niri/sections/close.js", import.meta.url));

function actions({ windows, page = {}, niri = true, loaded = true }) {
    const sent = [];
    const dialogs = [];
    const context = vm.createContext({
        String, Close,
        I18n: { tr: text => ({ text, arg(v) { return { ...this, text: this.text.replace(/%\d/, v) }; } }) },
        Theme: { error: "red" },
        CompositorService: { isNiri: niri },
        NiriService: {
            focusedWorkspaceId: "2",
            allWorkspaces: [{ id: 1, idx: 1, name: "" }, { id: 2, idx: 2, name: "web" }],
            windows,
            send: request => sent.push(request)
        },
        NiriPageService: { get: key => (key in page ? page[key] : Close.defaults[key]) },
        _pending: null,
        confirmLoader: { active: false, loadedModal: loaded ? { showWithOptions: options => dialogs.push(options) } : null }
    });
    context.root = context;
    for (const match of source.matchAll(/^    function \w+\([^\n]*\) \{\n[\s\S]*?^    \}/gm))
        vm.runInContext(match[0], context);
    return { a: context, sent, dialogs, closed: () => sent.map(r => r.Action.CloseWindow.id) };
}

const win = (id, ws) => ({ id, workspace_id: ws });

test("below the threshold every window of the focused workspace closes, others stay", () => {
    const { a, closed, dialogs } = actions({ windows: [win(10, 2), win(11, 1), win(12, 2)] });
    assert.equal(a.closeFocusedWorkspace(), "WORKSPACE_CLOSED");
    assert.deepEqual(closed(), [10, 12]);
    assert.equal(dialogs.length, 0);
});

test("at the threshold it asks first and closes only on confirm", () => {
    const { a, closed, dialogs } = actions({ windows: [win(10, 2), win(12, 2), win(13, 2)] });
    assert.equal(a.closeFocusedWorkspace(), "WORKSPACE_CONFIRM");
    assert.equal(closed().length, 0);
    assert.equal(dialogs[0].title.text, "Close 3 windows on \"web\"?");
    assert.equal(dialogs[0].defaultButton, 1, "Enter confirms the close, not the cancel");
    dialogs[0].onConfirm();
    assert.deepEqual(closed(), [10, 12, 13]);
});

test("on the first press the dialog waits for the modal to load", () => {
    const { a, dialogs, closed } = actions({ windows: [win(10, 2), win(12, 2), win(13, 2)], loaded: false });
    assert.equal(a.closeFocusedWorkspace(), "WORKSPACE_CONFIRM");
    assert.equal(a.confirmLoader.active, true);
    a.confirmLoader.loadedModal = { showWithOptions: options => dialogs.push(options) };
    a.showPending();
    assert.equal(dialogs.length, 1);
    a.showPending();
    assert.equal(dialogs.length, 1);
    assert.equal(closed().length, 0);
});

test("0 asks for a single window, never ask closes many at once", () => {
    const always = actions({ windows: [win(10, 2)], page: { "close.askFrom": 0 } });
    assert.equal(always.a.closeFocusedWorkspace(), "WORKSPACE_CONFIRM");
    const never = actions({ windows: [win(10, 2), win(12, 2), win(13, 2), win(14, 2)], page: { "close.neverAsk": true } });
    assert.equal(never.a.closeFocusedWorkspace(), "WORKSPACE_CLOSED");
    assert.equal(never.closed().length, 4);
});

test("an empty workspace or another compositor sends nothing", () => {
    const empty = actions({ windows: [win(11, 1)] });
    assert.equal(empty.a.closeFocusedWorkspace(), "WORKSPACE_EMPTY");
    const other = actions({ windows: [win(10, 2)], niri: false });
    assert.equal(other.a.closeFocusedWorkspace(), "WORKSPACE_UNSUPPORTED_COMPOSITOR");
    assert.equal(empty.sent.length + other.sent.length, 0);
});
