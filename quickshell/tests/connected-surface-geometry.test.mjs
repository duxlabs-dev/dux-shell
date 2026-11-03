import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Common/ConnectedSurfaceGeometry.js", import.meta.url), "utf8").replace(".pragma library", "");
const geometry = vm.createContext({});
vm.runInContext(source, geometry);

test("an edit strip hung off the body rolls out with it", () => {
    const body = { x: 10, y: 40, width: 300, height: 200 };
    const cases = [
        { side: "top", overflowTop: 0, overflowBottom: 50, dy: -125, rect: { x: 10, y: 40, width: 300, height: 125 } },
        { side: "top", overflowTop: 0, overflowBottom: 50, dy: -250, rect: { x: 10, y: 40, width: 300, height: 0 } },
        { side: "bottom", overflowTop: 50, overflowBottom: 0, dy: 125, rect: { x: 10, y: 115, width: 300, height: 125 } },
        { side: "left", overflowTop: 0, overflowBottom: 50, dy: 0, rect: { x: 10, y: 40, width: 300, height: 250 } }
    ];
    for (const c of cases) {
        const rect = geometry.animatedBodyRect({
            barSide: c.side,
            bodyRect: body,
            animationOffset: { x: 0, y: c.dy },
            overflowTop: c.overflowTop,
            overflowBottom: c.overflowBottom
        }, 1);
        assert.deepEqual({ x: rect.x, y: rect.y, width: rect.width, height: rect.height }, c.rect, `${c.side} dy=${c.dy}`);
    }
});
