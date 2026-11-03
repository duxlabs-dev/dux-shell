import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const context = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/WindowRuleMerge.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), context);
const plain = value => JSON.parse(JSON.stringify(value));

test("an edit keeps fields the editor does not own and clears the ones it does", () => {
    const stored = {
        "idleinhibit": "focus",
        "forcergbx": true,
        "focusRingColor": "#ff0000",
        "noGlow": true,
        "opacity": 0.5
    };
    assert.deepEqual(plain(context.carry(stored, ["noGlow", "opacity", "monitor"])), {
        "idleinhibit": "focus",
        "forcergbx": true,
        "focusRingColor": "#ff0000"
    });
    assert.equal(stored.noGlow, true);
    assert.deepEqual(plain(context.carry(null, ["opacity"])), {});
});
