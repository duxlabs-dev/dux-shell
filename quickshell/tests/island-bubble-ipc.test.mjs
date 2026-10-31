import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const ipc = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/IslandBubbleIpc.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), ipc);

test("a bubble is named as the status lists it, and found by that name for its IPC", () => {
    const sides = { "machine": { "id": "system", "source": "system", "kind": "volume" }, "apps": [
        { "id": "notification:7", "source": "notification" }, { "id": "script:backup:1", "source": "plugin", "kind": "live" },
        { "id": "script:sync:2", "source": "plugin", "kind": "live" }, { "source": "media" }] };
    // Two scripts' bubbles of one kind keep a name each; one without an id goes by its source.
    assert.deepEqual(sides.apps.map(ipc.bubbleName), ["notification:7", "script:backup:1", "script:sync:2", "media"]);
    assert.equal(ipc.bubbleNamed(sides, "machine").kind, "volume");
    assert.equal(ipc.bubbleNamed(sides, "script:sync:2"), sides.apps[2], "the second bubble of a kind is reached");
    assert.equal(ipc.bubbleNamed(sides, "script:backup:1"), sides.apps[1]);
    assert.equal(ipc.bubbleNamed(sides, "plugin"), null, "a plugin bubble goes by its token");
    assert.equal(ipc.bubbleNamed(null, "machine"), null);
    assert.equal(ipc.bubbleNamed({ "apps": [] }, "media"), null);
});

test("the bubble IPC opens or puts away the bubble it names, the second of a kind too, and says what it could not", () => {
    const done = [];
    const sides = { "machine": { "id": "system", "source": "system", "kind": "volume" }, "apps": [
        { "id": "script:backup:1", "source": "plugin", "kind": "live" }, { "id": "script:sync:2", "source": "plugin", "kind": "live" }] };
    const body = { "bubbleSides": sides, "bringBubble": b => done.push("open " + b.id), "dismissBubble": b => done.push("dismiss " + b.id) };
    assert.equal(ipc.ipcBubble(body, "open", "script:sync:2", "DP-1"), "DANK_ISLAND_BUBBLE_OPEN: script:sync:2\tDP-1");
    assert.equal(ipc.ipcBubble(body, "dismiss", "script:backup:1", "DP-1"), "DANK_ISLAND_BUBBLE_DISMISS: script:backup:1\tDP-1");
    assert.equal(ipc.ipcBubble(body, "dismiss", "machine", "DP-1"), "DANK_ISLAND_BUBBLE_DISMISS: machine\tDP-1");
    assert.deepEqual(done, ["open script:sync:2", "dismiss script:backup:1", "dismiss system"]);
    assert.equal(ipc.ipcBubble(body, "open", "script:gone:9", "DP-1"), "DANK_ISLAND_BUBBLE_UNKNOWN: script:gone:9");
    assert.equal(ipc.ipcBubble(body, "shake", "machine", "DP-1"), "DANK_ISLAND_BUBBLE_ACTION_UNKNOWN: shake");
    assert.equal(ipc.ipcBubble(null, "open", "machine", ""), "DANK_ISLAND_UNAVAILABLE");
    assert.equal(done.length, 3, "nothing runs on a refusal");
});

test("the keyboard turns a bubble's tile and holds its card open as the pointer does, and says when the bubble cannot", () => {
    const done = [];
    const sides = { "machine": { "id": "system", "source": "system", "kind": "volume" }, "apps": [{ "id": "notification:7", "source": "notification" }] };
    const body = { "bubbleSides": sides, "bringBubble": () => done.push("open"), "dismissBubble": () => done.push("dismiss"),
        "pressBubble": (b, action) => done.push(`${action} ${b.id}`) && b.source !== "system" };
    assert.equal(ipc.ipcBubble(body, "tile", "notification:7", "DP-1"), "DANK_ISLAND_BUBBLE_TILE: notification:7\tDP-1");
    assert.equal(ipc.ipcBubble(body, "card", "notification:7", "DP-1"), "DANK_ISLAND_BUBBLE_CARD: notification:7\tDP-1");
    assert.equal(ipc.ipcBubble(body, "card", "machine", "DP-1"), "DANK_ISLAND_BUBBLE_UNAVAILABLE: machine");
    assert.deepEqual(done, ["tile notification:7", "card notification:7", "card system"]);
});
