import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const E = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/IslandEcho.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), E);

test("DMS's low battery warning, not another app's battery", () => {
    assert.equal(E.kind("DMS", "Low Battery Battery is at 15% - Consider charging soon"), "battery");
    assert.equal(E.kind("upower", "Battery", "Charging"), "battery", "the body is read too");
    assert.equal(E.kind("Steam", "Controller battery low"), "");
    assert.equal(E.kind("DMS", "Update available"), "");
    assert.equal(E.kind(undefined, undefined), "");
});

test("a chat about a download, a stick, a print or a VPN says something of its own", () => {
    assert.equal(E.kind("Signal", "Did the download finish?"), "");
    assert.equal(E.kind("Discord", "USB headset giveaway"), "");
    assert.equal(E.kind("Signal", "Can you print it?"), "");
    assert.equal(E.kind("Signal", "Use a VPN for that"), "");
});

test("plugging in says the battery, the other bubbles nothing an app repeats", () => {
    assert.equal(E.bubbleKind({ "source": "system", "kind": "charging" }), "battery");
    for (const kind of ["volume", "capslock", "powerprofile"])
        assert.equal(E.bubbleKind({ "source": "system", "kind": kind }), "", kind);
    assert.equal(E.bubbleKind({ "source": "notification" }), "");
    assert.equal(E.bubbleKind(null), "");
});

test("an echo never takes the island from the info it repeats", () => {
    assert.equal(E.adoptable("", false, ["battery"]), true);
    assert.equal(E.adoptable("battery", true, ["battery"]), true);
    assert.equal(E.adoptable("battery", false, []), true);
    assert.equal(E.adoptable("battery", false, ["battery"]), false);
    assert.equal(E.adoptable("battery", false, null), true);
});
