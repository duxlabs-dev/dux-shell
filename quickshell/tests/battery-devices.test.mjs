import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const devices = loadScript(new URL("../Common/BatteryDevices.js", import.meta.url));

const plain = (value) => JSON.parse(JSON.stringify(value));

const MOUSE = 5;
const KEYBOARD = 6;

function device(type, model, percentage, extra = {}) {
    return { type, model, name: model, icon: type === MOUSE ? "mouse" : "keyboard", percentage, charging: false, unknown: percentage === 0, low: percentage > 0 && percentage <= 20, ...extra };
}

function keyed(list) {
    const keys = plain(devices.deviceKeys(list));
    return list.map((dev, index) => ({ ...dev, key: keys[index] }));
}

const SYSTEM = { percentage: 80, charging: false, low: false, unknown: false };

// The ramp BatteryService.levelColor used before it moved into BatteryDevices.js.
function legacyRamp(batteryLevel, isCharging, lowThreshold, criticalThreshold) {
    const hasBatteryReading = batteryLevel > 0;
    const atOrBelow = (level, threshold) => level > 0 && level <= threshold;
    if (isCharging)
        return "success";
    if (hasBatteryReading && atOrBelow(batteryLevel, criticalThreshold))
        return "critical";
    if (hasBatteryReading && atOrBelow(batteryLevel, lowThreshold))
        return "warning";
    if (batteryLevel <= lowThreshold * 2)
        return "caution";
    return "success";
}

test("levelRamp matches the legacy battery color for every level", () => {
    for (const [low, critical] of [[20, 5], [30, 10], [5, 5], [40, 5], [10, 10]]) {
        for (const charging of [false, true]) {
            for (let level = 0; level <= 100; level++)
                assert.equal(devices.levelRamp(level, charging, low, critical), legacyRamp(level, charging, low, critical), `${level} ${charging} ${low}/${critical}`);
        }
    }
});

test("entries keep the saved order and skip the ones switched off", () => {
    const live = keyed([device(MOUSE, "MX", 50), device(KEYBOARD, "K1", 60)]);
    const saved = [{ id: "6:K1:0", on: true }, { id: "system", on: true }, { id: "5:MX:0", on: false }];
    const items = devices.resolveBarEntries(saved, SYSTEM, live);
    assert.deepEqual(plain(items.map(i => i.id)), ["6:K1:0", "system"]);
    assert.equal(items[0].kind, "device");
    assert.equal(items[0].percentage, 60);
    assert.equal(items[0].iconName, "keyboard");
});

test("a device that is not connected is skipped", () => {
    const items = devices.resolveBarEntries([{ id: "system" }, { id: "5:MX:0" }], SYSTEM, []);
    assert.deepEqual(plain(items.map(i => i.id)), ["system"]);
});

test("lowOnly hides entries above the threshold and treats a reading of 0 as unknown", () => {
    const live = keyed([device(MOUSE, "MX", 0), device(KEYBOARD, "K1", 10), device(MOUSE, "Big", 90)]);
    const saved = [{ id: "system", lowOnly: true }, { id: "5:MX:0", lowOnly: true }, { id: "6:K1:0", lowOnly: true }, { id: "5:Big:0", lowOnly: true }];
    assert.deepEqual(plain(devices.resolveBarEntries(saved, SYSTEM, live).map(i => i.id)), ["6:K1:0"]);

    const lowSystem = { ...SYSTEM, percentage: 10, low: true };
    assert.deepEqual(plain(devices.resolveBarEntries(saved, lowSystem, live).map(i => i.id)), ["system", "6:K1:0"]);

    // A low flag next to a reading of 0 is never trusted.
    const zero = [{ ...device(MOUSE, "MX", 0), low: true }];
    assert.deepEqual(plain(devices.resolveBarEntries([{ id: "5:MX:0", lowOnly: true }], SYSTEM, keyed(zero)).map(i => i.id)), []);
    const zeroSystem = { percentage: 0, charging: false, low: true, unknown: true };
    assert.deepEqual(plain(devices.resolveBarEntries([{ id: "system", lowOnly: true }], zeroSystem, []).map(i => i.id)), []);
});

test("an unknown reading is never low and a charging device is not low", () => {
    const live = keyed([device(MOUSE, "MX", 0, { low: true })]);
    const items = devices.resolveBarEntries([{ id: "5:MX:0" }], SYSTEM, live);
    assert.equal(items[0].unknown, true);
    assert.equal(items[0].low, false);
});

test("device parts default to shown and keep what was saved", () => {
    const live = keyed([device(MOUSE, "MX", 50)]);
    const [plainItem] = devices.resolveBarEntries([{ id: "5:MX:0" }], SYSTEM, live);
    assert.equal(plainItem.entry.icon, true);
    assert.equal(plainItem.entry.percent, true);
    const [custom] = devices.resolveBarEntries([{ id: "5:MX:0", icon: false, percent: "no" }], SYSTEM, live);
    assert.equal(custom.entry.icon, false);
    assert.equal(custom.entry.percent, true);
});

test("editorRows keep absent saved devices and append unsaved live ones off", () => {
    const live = keyed([device(MOUSE, "MX", 50), device(KEYBOARD, "K1", 60)]);
    const saved = [{ id: "5:Gone:0", on: true, icon: false, name: "Old mouse", iconName: "mouse" }, { id: "system", on: true }, { id: "5:MX:0", on: true, percent: false }];
    const rows = plain(devices.editorRows(saved, live)).map(({ raw, ...row }) => row);
    assert.deepEqual(rows.map(r => r.id), ["5:Gone:0", "system", "5:MX:0", "6:K1:0"]);
    assert.deepEqual(rows[0], { id: "5:Gone:0", kind: "device", name: "Old mouse", iconName: "mouse", present: false, on: true, icon: false, percent: true, lowOnly: false });
    assert.equal(rows[1].kind, "system");
    assert.equal(rows[1].present, true);
    assert.equal(rows[2].present, true);
    assert.equal(rows[2].name, "MX");
    assert.equal(rows[2].percent, false);
    assert.deepEqual(rows[3], { id: "6:K1:0", kind: "device", name: "K1", iconName: "keyboard", present: true, on: false, icon: true, percent: true, lowOnly: false });
});

test("editorRows always has the system row, off when the list lacked it", () => {
    const rows = plain(devices.editorRows([{ id: "5:MX:0" }], keyed([device(MOUSE, "MX", 50)])));
    assert.deepEqual(rows.map(r => [r.id, r.on]), [["system", false], ["5:MX:0", true]]);
    assert.deepEqual(plain(devices.editorRows(undefined, [])).map(r => [r.id, r.on]), [["system", true]]);
});

test("entryForRow writes the persisted shape", () => {
    const rows = devices.editorRows([{ id: "system", lowOnly: true }, { id: "5:Gone:0", name: "Old", iconName: "mouse", icon: false }], []);
    assert.deepEqual(plain(devices.entryForRow(rows[0])), { id: "system", on: true, lowOnly: true });
    assert.deepEqual(plain(devices.entryForRow(rows[1])), { id: "5:Gone:0", on: true, icon: false, percent: true, lowOnly: false, name: "Old", iconName: "mouse" });
});

test("a saved list round-trips through the editor", () => {
    const live = keyed([device(MOUSE, "MX", 50)]);
    const saved = [{ id: "5:MX:0", on: true, icon: true, percent: false, lowOnly: true, name: "MX", iconName: "mouse" }, { id: "system", on: false, lowOnly: false }];
    const written = devices.editorRows(saved, live).map(devices.entryForRow);
    assert.deepEqual(plain(written), saved);
});

test("fields the editor does not know survive an edit", () => {
    const saved = [{ id: "system", on: true, future: 1 }, { id: "5:Gone:0", name: "Old", iconName: "mouse", extra: { a: 1 } }];
    const rows = devices.editorRows(saved, []);
    rows[1].on = false;
    const written = plain(rows.map(devices.entryForRow));
    assert.equal(written[0].future, 1);
    assert.deepEqual(written[1].extra, { a: 1 });
    assert.equal(written[1].on, false);
    assert.equal(plain(devices.entryForRow({ id: "5:X:0", on: true })).extra, undefined);
});
