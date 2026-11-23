import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const helper = loadScript(new URL("../Common/LockWorkspaceState.js", import.meta.url));

test("findLockWorkspaceTarget skips saved and occupied records", () => {
    const saved = {
        screenName: "eDP-1",
        workspaceRecord: { id: 1, name: "1", output: "eDP-1" },
        workspaceKey: 1
    };
    const workspaces = [
        saved.workspaceRecord,
        { id: 2, name: "2", output: "eDP-1" },
        { id: 3, name: "3", output: "eDP-1" }
    ];
    const occupied = new Set([2]);
    assert.equal(helper.findLockWorkspaceTarget(saved, workspaces, ws => occupied.has(ws.id)), workspaces[2]);
});

test("findLockWorkspaceTarget returns null when no unoccupied record exists", () => {
    const saved = { screenName: "eDP-1", workspaceRecord: { id: 1, name: "1", output: "eDP-1" }, workspaceKey: 1 };
    const workspaces = [saved.workspaceRecord, { id: 2, name: "2", output: "eDP-1" }];
    assert.equal(helper.findLockWorkspaceTarget(saved, workspaces, () => true), null);
});

test("findLockWorkspaceTarget returns the source record unchanged", () => {
    const saved = { screenName: "eDP-1", workspaceRecord: { id: 1, name: "1", output: "eDP-1" }, workspaceKey: 1 };
    const target = { id: 4, name: "4", output: "eDP-1", active: true };
    assert.equal(helper.findLockWorkspaceTarget(saved, [saved.workspaceRecord, target], () => false), target);
});

test("compareWorkspaceRecords ignores mutable focus fields", () => {
    assert.equal(helper.compareWorkspaceRecords(
        { id: 2, name: "2", output: "eDP-1", active: true, focused: true },
        { id: 2, name: "2", output: "eDP-1", active: false, focused: false }
    ), true);
});

test("compareWorkspaceRecords rejects different identities", () => {
    assert.equal(helper.compareWorkspaceRecords(
        { id: 2, name: "2", output: "eDP-1" },
        { id: 3, name: "3", output: "eDP-1" }
    ), false);
});

test("compareWorkspaceRecords rejects null records", () => {
    assert.equal(helper.compareWorkspaceRecords(null, { id: 2 }), false);
    assert.equal(helper.compareWorkspaceRecords({ id: 2 }, null), false);
});

test("nextHyprlandLockWorkspaceId picks smallest unused positive id", () => {
    const workspaces = [
        { id: 1, name: "1" },
        { id: 2, name: "2" }
    ];
    assert.equal(helper.nextHyprlandLockWorkspaceId(workspaces, undefined), 3);
});

test("nextHyprlandLockWorkspaceId reserves saved id even when missing from workspaces", () => {
    const workspaces = [{ id: 2, name: "2" }];
    assert.equal(helper.nextHyprlandLockWorkspaceId(workspaces, 1), 3);
});

test("nextHyprlandLockWorkspaceId ignores named id -1 workspaces", () => {
    const workspaces = [{ id: -1, name: "dms-lock-temp" }];
    assert.equal(helper.nextHyprlandLockWorkspaceId(workspaces, undefined), 1);
});

test("nextHyprlandLockWorkspaceId respects idx collision", () => {
    const workspaces = [{ id: 5, idx: 1, name: "5" }];
    assert.equal(helper.nextHyprlandLockWorkspaceId(workspaces, undefined), 2);
});

test("nextHyprlandLockWorkspaceId reserves ids chosen for earlier screens", () => {
    const workspaces = [{ id: 1, name: "1" }, { id: 2, name: "2" }];
    assert.equal(helper.nextHyprlandLockWorkspaceId(workspaces, undefined, [3, 4]), 5);
});

test("nextI3LockWorkspaceName returns unique temporary names", () => {
    assert.equal(helper.nextI3LockWorkspaceName([]), "dms-lock-temp");
    assert.equal(helper.nextI3LockWorkspaceName(["dms-lock-temp"]), "dms-lock-temp-2");
    assert.equal(helper.nextI3LockWorkspaceName(["dms-lock-temp", "dms-lock-temp-2"]), "dms-lock-temp-3");
});

test("isReservedWorkspaceTarget matches records by stable identity", () => {
    const reserved = [{ id: 9, name: "dms-lock-temp", output: "eDP-1" }];
    assert.equal(helper.isReservedWorkspaceTarget({ id: 9, name: "dms-lock-temp", output: "HDMI-A-1" }, reserved), true);
    assert.equal(helper.isReservedWorkspaceTarget({ id: 10, name: "2", output: "eDP-1" }, reserved), false);
});
