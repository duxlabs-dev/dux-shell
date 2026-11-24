import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const state = loadScript(new URL("../Common/LockTransitionState.js", import.meta.url));

test("secure-first: lock request engages session lock directly, no chrome-hide detour", () => {
    assert.equal(state.next("idle", "lockRequested", true), "securingLock");
    assert.equal(state.next("securingLock", "secure", true), "lockVisible");
});

test("secure-first holds for reduced motion too", () => {
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
    assert.equal(state.next("securingLock", "reset", true), "idle");
    assert.equal(state.next("fadingLockUi", "reset", true), "idle");
    assert.equal(state.next("restoringWorkspaces", "reset", true), "idle");
});

test("external unlock skips lock UI fade", () => {
    assert.equal(state.next("fadingLockUi", "externalUnlock", true), "restoringWorkspaces");
    assert.equal(state.next("lockVisible", "externalUnlock", true), "restoringWorkspaces");
});

test("secure then lock UI then unlock then restore then reveal chrome", () => {
    assert.equal(state.next("idle", "lockRequested", true), "securingLock");
    assert.equal(state.next("securingLock", "secure", true), "lockVisible");
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
    assert.equal(state.next("securingLock", "externalUnlock", true), "restoringWorkspaces");
    assert.equal(state.next("restoringWorkspaces", "workspaceUnavailable", true), "revealingChrome");
});

test("pre-visible reset still returns to idle", () => {
    assert.equal(state.next("securingLock", "reset", true), "idle");
    assert.equal(state.next("restoringWorkspaces", "reset", true), "idle");
});

test("reset cancels workspace phases", () => {
    assert.equal(state.next("restoringWorkspaces", "reset", true), "idle");
});

test("no phase holds an input grab now that the pre-lock chrome fade is gone", () => {
    assert.equal(state.shouldHoldInputSurface("securingLock"), false);
    assert.equal(state.shouldHoldInputSurface("lockVisible"), false);
    assert.equal(state.shouldHoldInputSurface("fadingLockUi"), false);
    assert.equal(state.shouldHoldInputSurface("restoringWorkspaces"), false);
});
