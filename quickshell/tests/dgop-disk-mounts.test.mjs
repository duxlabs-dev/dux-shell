import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Services/DgopService.qml", import.meta.url), "utf8");

function service() {
    const requests = [];
    const context = vm.createContext({
        dgopAvailable: true,
        diskMountsRequested: false,
        diskMounts: [],
        refCount: 0,
        enabledModules: [],
        SettingsData: { controlCenterWidgets: [{ id: "diskUsage", enabled: true }] },
        DMSService: { sendRequest: (method, params, callback) => requests.push({ method, params, callback }) },
        log: { warn() {} },
        statsUpdated() {},
        deviceHistory: {}
    });
    const methods = ["initializeDiskMounts", "hasModule", "parseData", "releaseUnusedData", "removeDeviceHistory"];
    const found = [];
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^    \}/gm)) {
        if (!methods.includes(match[1]))
            continue;
        found.push(match[1]);
        vm.runInContext(match[0], context);
    }
    assert.deepEqual(found.sort(), [...methods].sort());
    return { context, requests };
}

test("disk startup fetch waits for the backend and requires an enabled disk widget", () => {
    const { context, requests } = service();
    context.dgopAvailable = false;
    context.initializeDiskMounts();
    context.dgopAvailable = true;
    context.SettingsData.controlCenterWidgets = [{ id: "wifi" }, { id: "diskUsage", enabled: false }];
    context.initializeDiskMounts();
    assert.equal(requests.length, 0);
    assert.equal(context.diskMountsRequested, false);
    context.SettingsData.controlCenterWidgets = [{ id: "diskUsage", mountPath: "/" }, { id: "diskUsage", mountPath: "/home" }];
    context.initializeDiskMounts();
    assert.equal(requests.length, 1);
    assert.equal(requests[0].method, "dgop.meta");
    assert.deepEqual(Array.from(requests[0].params.modules), ["diskmounts"]);
});

test("disk startup fetch is asynchronous, runs once, and acquires no polling references", () => {
    const { context, requests } = service();
    const mounts = [{ mount: "/", used: "24G", size: "100G", percent: "24%" }];
    context.initializeDiskMounts();
    context.initializeDiskMounts();
    assert.equal(requests.length, 1);
    assert.equal(context.diskMounts.length, 0);
    assert.equal(context.refCount, 0);
    assert.equal(context.enabledModules.length, 0);
    requests[0].callback({ result: { diskmounts: mounts } });
    assert.equal(context.diskMounts, mounts);
    context.releaseUnusedData();
    context.initializeDiskMounts();
    assert.equal(context.diskMounts, mounts);
    assert.equal(context.refCount, 0);
    assert.equal(requests.length, 1);
});

test("active disk subscribers supply the initial snapshot without a startup request", () => {
    const { context, requests } = service();
    const mounts = [{ mount: "/home", used: "42G" }];
    context.refCount = 1;
    context.enabledModules = ["diskmounts"];
    context.initializeDiskMounts();
    assert.equal(requests.length, 0);
    context.parseData({ diskmounts: mounts });
    context.refCount = 0;
    context.enabledModules = [];
    context.releaseUnusedData();
    context.initializeDiskMounts();
    assert.equal(context.diskMounts, mounts);
    assert.equal(requests.length, 0);
});

test("a delayed startup response preserves a newer subscriber snapshot", () => {
    const { context, requests } = service();
    context.initializeDiskMounts();
    context.refCount = 1;
    context.enabledModules = ["diskmounts"];
    const mounts = [{ mount: "/", used: "25G" }];
    context.parseData({ diskmounts: mounts });
    context.refCount = 0;
    context.enabledModules = [];
    context.releaseUnusedData();
    requests[0].callback({ result: { diskmounts: [{ mount: "/", used: "24G" }] } });
    assert.equal(context.diskMounts, mounts);
});

test("a failed startup request does not retry or acquire references", () => {
    const { context, requests } = service();
    context.initializeDiskMounts();
    requests[0].callback({ error: "unavailable" });
    context.initializeDiskMounts();
    assert.equal(requests.length, 1);
    assert.equal(context.diskMounts.length, 0);
    assert.equal(context.refCount, 0);
});
