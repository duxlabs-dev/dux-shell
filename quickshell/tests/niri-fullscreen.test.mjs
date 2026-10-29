import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../Services/NiriFullscreen.js', import.meta.url), 'utf8');
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library\s*/, ''), context);
const detect = context.isFullscreenOnScreen;

function fixture() {
    return {
        workspaces: [
            { id: 1, output: 'A', is_active: true, active_window_id: 10 },
            { id: 2, output: 'A', is_active: false, active_window_id: 20 },
            { id: 3, output: 'B', is_active: true, active_window_id: 30 }
        ],
        windows: [
            { id: 10, workspace_id: 1, app_id: 'browser', title: 'Video', is_focused: false },
            { id: 20, workspace_id: 2, app_id: 'editor', title: 'Notes', is_focused: false },
            { id: 30, workspace_id: 3, app_id: 'terminal', title: 'Shell', is_focused: true }
        ],
        toplevels: [
            { appId: 'browser', title: 'Video', screens: [{ name: 'A' }], fullscreen: true, activated: false },
            { appId: 'editor', title: 'Notes', screens: [{ name: 'A' }], fullscreen: false, activated: false },
            { appId: 'terminal', title: 'Shell', screens: [{ name: 'B' }], fullscreen: false, activated: true }
        ]
    };
}

function run(f, screen = 'A') {
    return detect(screen, f.workspaces, f.windows, f.toplevels);
}

test('fullscreen remains detected when keyboard focus is on another monitor', () => {
    const f = fixture();
    assert.equal(run(f), true);
    assert.equal(run(f, 'B'), false);
});

test('switching workspaces ignores fullscreen windows on the inactive workspace', () => {
    const f = fixture();
    f.workspaces[0].is_active = false;
    f.workspaces[1].is_active = true;
    assert.equal(run(f), false);
});

test('selecting another window in the same workspace stops fullscreen hiding', () => {
    const f = fixture();
    f.windows[1].workspace_id = 1;
    f.workspaces[0].active_window_id = 20;
    assert.equal(run(f), false);
});

test('closing or moving the active window does not use stale workspace state', () => {
    const f = fixture();
    f.windows[0].workspace_id = 3;
    assert.equal(run(f), false);
    f.windows.shift();
    assert.equal(run(f), false);
});

test('leaving fullscreen updates the result without a focus change', () => {
    const f = fixture();
    assert.equal(run(f), true);
    f.toplevels[0].fullscreen = false;
    assert.equal(run(f), false);
});

test('equal app IDs and titles on different monitors are not ambiguous', () => {
    const f = fixture();
    Object.assign(f.windows[2], { app_id: 'browser', title: 'Video' });
    Object.assign(f.toplevels[2], { appId: 'browser', title: 'Video' });
    assert.equal(run(f), true);
    assert.equal(run(f, 'B'), false);
});

test('equal titles across workspaces on the same monitor do not guess a match', () => {
    const f = fixture();
    Object.assign(f.windows[1], { app_id: 'browser', title: 'Video' });
    Object.assign(f.toplevels[1], { appId: 'browser', title: 'Video' });
    assert.equal(run(f), false);
});

test('keyboard focus can disambiguate equal titles on the same monitor', () => {
    const f = fixture();
    Object.assign(f.windows[1], { app_id: 'browser', title: 'Video' });
    Object.assign(f.toplevels[1], { appId: 'browser', title: 'Video' });
    f.windows[0].is_focused = true;
    f.toplevels[0].activated = true;
    assert.equal(run(f), true);
});

test('duplicate or missing Wayland candidates keep the bar available', () => {
    const f = fixture();
    f.toplevels.push({ ...f.toplevels[0] });
    assert.equal(run(f), false);
    f.toplevels = [];
    assert.equal(run(f), false);
});

test('transient title or output mismatches do not hide the bar', () => {
    const f = fixture();
    f.toplevels[0].title = 'Changing title';
    assert.equal(run(f), false);
    f.toplevels[0].title = 'Video';
    f.toplevels[0].screens = [];
    assert.equal(run(f), false);
});

test('empty workspaces, disconnected outputs and missing data are safe', () => {
    const f = fixture();
    assert.equal(run(f, 'disconnected'), false);
    f.workspaces[0].active_window_id = null;
    assert.equal(run(f), false);
    assert.equal(detect('', [], [], []), false);
    assert.equal(detect('A', null, [], []), false);
    assert.equal(detect('A', [], [], undefined), false);
});

test('ending fullscreen auto-hide clears IPC reveal before the next fullscreen', () => {
    const body = readFileSync(new URL('../Modules/DBar/DBarBody.qml', import.meta.url), 'utf8');
    const handler = body.match(/onAutoHideChanged: \{([\s\S]*?)\n        \}/)?.[1];
    assert.ok(handler, 'DBar auto-hide change handler exists');
    const calls = [];
    const state = vm.createContext({
        autoHide: false,
        barConfig: { id: 'main' },
        SettingsData: { setBarIpcReveal: (...args) => calls.push(args) },
        evaluateReveal: () => calls.push(['evaluate'])
    });
    vm.runInContext(handler, state);
    assert.deepEqual(calls, [['main', false], ['evaluate']]);

    calls.length = 0;
    state.autoHide = true;
    vm.runInContext(handler, state);
    assert.deepEqual(calls, [['evaluate']]);
});

test('fullscreen-only hiding keeps the bar exclusive zone', () => {
    const body = readFileSync(new URL('../Modules/DBar/DBarBody.qml', import.meta.url), 'utf8');
    const expression = body.match(/readonly property real surfaceExclusiveZone: (.+)$/m)?.[1];
    assert.ok(expression, 'DBar exclusive-zone binding exists');

    const state = vm.createContext({
        isIsland: false,
        islandFree: false,
        islandHost: null,
        barConfig: { visible: true, autoHide: false, bottomGap: 0 },
        barWindow: { effectiveBarThickness: 40, reserveExclusiveWhenAutoHidden: false },
        effectiveSpacing: 4,
        usesFrameBarChrome: false,
        topBarCore: { autoHide: true },
        SettingsData: { islandReserveThickness: () => 0 }
    });
    assert.equal(vm.runInContext(expression, state), 44);

    state.barConfig.autoHide = true;
    assert.equal(vm.runInContext(expression, state), -1);
});
