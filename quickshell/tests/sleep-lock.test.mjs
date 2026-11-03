import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const sleepLock = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/SleepLock.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), sleepLock);

test("lock-before-sleep waits until the session lock is actually up", () => {
    assert.equal(sleepLock.shouldWaitForLock(true, false), true, "lock requested and not yet secure");
    assert.equal(sleepLock.shouldWaitForLock(true, true), false, "already locked, sleep immediately");
    assert.equal(sleepLock.shouldWaitForLock(false, false), false, "setting off, do not delay sleep");
});
