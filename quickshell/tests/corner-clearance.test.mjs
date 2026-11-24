import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const clearance = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/CornerClearance.js", import.meta.url), "utf8").replace(/^\.pragma.*$/m, ""), clearance);

// True when the screen-corner mask of radius r covers any point of a rounded corner of `radius` inset `gap`.
function overlaps(r, gap, radius) {
    const step = 0.05;
    for (let x = gap; x < r; x += step) {
        for (let y = gap; y < r; y += step) {
            const cx = gap + radius;
            const insideWindow = x >= cx || y >= cx || (x - cx) ** 2 + (y - cx) ** 2 <= radius ** 2;
            const insideMask = (x - r) ** 2 + (y - r) ** 2 > r ** 2;
            if (insideWindow && insideMask)
                return true;
        }
    }
    return false;
}

test("limit is the largest radius that clears the inset corner", () => {
    for (const [gap, radius] of [[0, 18], [4, 0], [4, 18], [8, 20], [10, 12]]) {
        const r = clearance.limit(gap, radius);
        assert.equal(overlaps(r - 0.2, gap, radius), false, `gap ${gap} radius ${radius} clears below the limit`);
        assert.equal(overlaps(r + 1, gap, radius), true, `gap ${gap} radius ${radius} overlaps above the limit`);
    }
});

test("only floating bars that reach a corner bound the screen limit", () => {
    const layout = (instance, config) => ({ instances: [{ kind: "bar", barId: "a", ...instance }], bars: [{ config: { id: "a", ...config } }] });
    const spans = config => !config.short;
    assert.equal(clearance.screenLimit([layout({ spacing: 0 }, {})], 50, 18, spans), 50);
    assert.equal(clearance.screenLimit([layout({ spacing: 4 }, { short: true })], 50, 18, spans), 50);
    assert.equal(clearance.screenLimit([layout({ spacing: 4 }, {})], 50, 18, spans), clearance.limit(4, 18));
    assert.equal(clearance.screenLimit([layout({ spacing: 4 }, { squareCorners: true })], 50, 18, spans), clearance.limit(4, 0));
});
