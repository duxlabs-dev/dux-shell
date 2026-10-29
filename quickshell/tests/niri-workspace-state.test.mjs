import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../Services/NiriService.qml', import.meta.url), 'utf8');

function service() {
    const context = vm.createContext({
        workspaces: {
            1: { id: 1, idx: 1, output: 'A', is_active: true, is_focused: true, active_window_id: 10 },
            2: { id: 2, idx: 1, output: 'B', is_active: true, is_focused: false, active_window_id: 20 }
        },
        windows: [
            { id: 10, workspace_id: 1, is_focused: true },
            { id: 11, workspace_id: 1, is_focused: false },
            { id: 20, workspace_id: 2, is_focused: false },
            { id: 21, workspace_id: 2, is_focused: false }
        ],
        allWorkspaces: [],
        lastFocusedWindowId: 10,
        updateCurrentOutputWorkspaces() {}
    });
    context.root = context;
    // Execute the actual JS event handlers with their QML property storage mocked.
    for (const name of ['setWorkspaces', 'updateWorkspace', 'handleWorkspacesChanged', 'handleWindowFocusChanged', 'handleWorkspaceActiveWindowChanged']) {
        const match = source.match(new RegExp(`    function ${name}\\([^]*?(?=\\n    function )`));
        assert.ok(match, `event handler ${name} exists`);
        vm.runInContext(match[0], context);
    }
    return context;
}

test('numeric focus IDs update string-keyed workspace storage', () => {
    const s = service();
    s.handleWindowFocusChanged({ id: 11 });
    assert.equal(s.workspaces[1].active_window_id, 11);
    assert.equal(s.allWorkspaces.find(ws => ws.id === 1).active_window_id, 11);
    assert.equal(s.windows.find(w => w.id === 11).is_focused, true);
    assert.equal(s.workspaces[2].active_window_id, 20);
});

test('active-window events update the correct workspace without stealing focus', () => {
    const s = service();
    s.handleWorkspaceActiveWindowChanged({ workspace_id: 2, active_window_id: 21 });
    assert.equal(s.workspaces[2].active_window_id, 21);
    assert.equal(s.windows.find(w => w.id === 10).is_focused, true);
    assert.equal(s.windows.find(w => w.id === 21).is_focused, false);
    assert.equal(s.lastFocusedWindowId, 10);
});

test('focused workspace active-window events preserve normal focus updates', () => {
    const s = service();
    s.handleWorkspaceActiveWindowChanged({ workspace_id: 1, active_window_id: 11 });
    assert.equal(s.workspaces[1].active_window_id, 11);
    assert.equal(s.windows.find(w => w.id === 11).is_focused, true);
    assert.equal(s.lastFocusedWindowId, 11);
});

test('fresh workspace snapshots replace stale active-window IDs, including null', () => {
    const s = service();
    s.handleWorkspacesChanged({ workspaces: [
        { ...s.workspaces[1], active_window_id: 11 },
        { ...s.workspaces[2], active_window_id: null }
    ] });
    assert.equal(s.workspaces[1].active_window_id, 11);
    assert.equal(s.workspaces[2].active_window_id, null);
});
