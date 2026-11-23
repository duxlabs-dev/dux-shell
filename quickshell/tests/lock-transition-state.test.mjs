import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const state = loadScript(new URL("../Common/LockTransitionState.js", import.meta.url));

test("transition lock path follows chrome hide before session lock", () => {
    assert.equal(state.next("idle", "lockRequested", true), "hidingChrome");
    assert.equal(state.next("hidingChrome", "chromeHidden", true), "movingWorkspaces");
    assert.equal(state.next("securingLock", "secure", true), "lockVisible");
});

test("disabled transition locks without hiding chrome", () => {
    assert.equal(state.next("idle", "lockRequested", false), "securingLock");
    assert.equal(state.next("securingLock", "secure", false), "lockVisible");
});

test("unlock keeps session locked until lock UI fade finishes", () => {
    assert.equal(state.next("lockVisible", "unlockRequested", true), "fadingLockUi");
    assert.equal(state.shouldKeepSessionLocked("fadingLockUi"), true);
    assert.equal(state.shouldShowLockUi("fadingLockUi"), false);
    assert.equal(state.next("fadingLockUi", "lockUiFadedOut", true), "restoringWorkspaces");
    assert.equal(state.next("revealingChrome", "chromeShown", true), "idle");
});

test("cancel and reset return to idle", () => {
    assert.equal(state.next("hidingChrome", "fadeCancelled", true), "idle");
    assert.equal(state.next("securingLock", "reset", true), "idle");
    assert.equal(state.next("fadingLockUi", "reset", true), "idle");
});

test("external unlock skips lock UI fade", () => {
    assert.equal(state.next("fadingLockUi", "externalUnlock", true), "restoringWorkspaces");
    assert.equal(state.next("lockVisible", "externalUnlock", true), "restoringWorkspaces");
});

test("workspace move precedes session lock", () => {
    assert.equal(state.next("idle", "lockRequested", true), "hidingChrome");
    assert.equal(state.next("hidingChrome", "chromeHidden", true), "movingWorkspaces");
    assert.equal(state.next("movingWorkspaces", "workspaceMoved", true), "securingLock");
    assert.equal(state.next("securingLock", "secure", true), "lockVisible");
});

test("workspace unavailable falls back to session lock", () => {
    assert.equal(state.next("hidingChrome", "workspaceUnavailable", true), "securingLock");
    assert.equal(state.next("movingWorkspaces", "workspaceUnavailable", true), "securingLock");
});

test("local unlock restores workspace before revealing chrome", () => {
    assert.equal(state.next("lockVisible", "unlockRequested", true), "fadingLockUi");
    assert.equal(state.next("fadingLockUi", "lockUiFadedOut", true), "restoringWorkspaces");
    assert.equal(state.next("restoringWorkspaces", "workspaceRestored", true), "revealingChrome");
    assert.equal(state.next("revealingChrome", "chromeShown", true), "idle");
    assert.equal(state.shouldKeepSessionLocked("fadingLockUi"), true);
    assert.equal(state.shouldKeepSessionLocked("restoringWorkspaces"), false);
    assert.equal(state.shouldShowLockUi("restoringWorkspaces"), false);
});

test("external unlock enters restore phase from either pre-restore phase", () => {
    assert.equal(state.next("lockVisible", "externalUnlock", true), "restoringWorkspaces");
    assert.equal(state.next("fadingLockUi", "externalUnlock", true), "restoringWorkspaces");
    assert.equal(state.next("restoringWorkspaces", "workspaceUnavailable", true), "revealingChrome");
});

test("external unlock resets pre-visible workspace phases", () => {
    assert.equal(state.next("movingWorkspaces", "externalUnlock", true), "restoringWorkspaces");
    assert.equal(state.next("securingLock", "externalUnlock", true), "restoringWorkspaces");
});

test("pre-visible reset still returns to idle", () => {
    assert.equal(state.next("movingWorkspaces", "reset", true), "idle");
    assert.equal(state.next("securingLock", "reset", true), "idle");
});

test("reset cancels workspace phases", () => {
    assert.equal(state.next("movingWorkspaces", "reset", true), "idle");
    assert.equal(state.next("restoringWorkspaces", "reset", true), "idle");
});

test("input surface is held only while hiding chrome", () => {
    assert.equal(state.shouldHoldInputSurface("hidingChrome"), true);
    assert.equal(state.shouldHoldInputSurface("securingLock"), false);
    assert.equal(state.shouldHoldInputSurface("lockVisible"), false);
});
