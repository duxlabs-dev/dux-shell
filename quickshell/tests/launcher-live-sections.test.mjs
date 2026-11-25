import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const live = loadScript(new URL("../Modals/DLauncherV2/LiveSections.js", import.meta.url));
const section = (id, priority) => ({ id, priority, items: [] });

test("cards keep the plugin's order and number repeated ids in order", () => {
    const cards = live.cards("p", [{ id: "a" }, { name: "b" }, { id: "a" }, { id: "a#2" }, { id: "a", name: "x" }], raw => ({ name: raw.name }));
    assert.deepEqual(Array.from(cards, c => c.id), ["live:p:a", "live:p:b", "live:p:a#2", "live:p:a#2#2", "live:p:a#3"]);
    assert.deepEqual(cards[1], { name: "b", id: "live:p:b", section: "live_p" });
});

test("a live section goes before the first section of higher priority", () => {
    const base = [section("pinned", 1), section("apps", 2), section("files", 3)];
    const merged = live.merge(base, [section("live_a", 1.5), section("live_b", 1.5), section("live_c", 0), section("live_d", 2), section("live_e", 9)]);
    assert.deepEqual(Array.from(merged, s => s.id), ["live_c", "pinned", "live_a", "live_b", "apps", "live_d", "files", "live_e"]);
    assert.notEqual(merged[1], base[0], "flattening writes flatStartIndex into sections, so base ones are copied");
    assert.equal(live.merge(base, []), base);
});
