import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const bounds = loadScript(new URL("../Common/PopoutBounds.js", import.meta.url));
const solver = loadScript(new URL("../../dux-qml-common/DCommon/Common/SpringMath.js", import.meta.url));
const screen = { width: 3840, height: 2160 };
const empty = { x: 0, y: 0, width: 0, height: 0 };

function contains(outer, inner) {
    assert.ok(outer.x <= inner.x && outer.y <= inner.y && outer.x + outer.width >= inner.x + inner.width && outer.y + outer.height >= inner.y + inner.height, `${JSON.stringify(outer)} does not contain ${JSON.stringify(inner)}`);
}

function spring(bounce, stiffness = 1520, dampingRatio = 0.8) {
    return { stiffness, damping: 2 * dampingRatio * Math.sqrt(stiffness) * bounce, mass: 1 };
}

test("popup buffers cover interrupted spatial motion and shadows at every edge", () => {
    const specs = [[1520, 0.8], [800, 0.6]].flatMap(([stiffness, dampingRatio]) => [0.82, 1, 1.22].map(bounce => spring(bounce, stiffness, dampingRatio)));
    for (const spec of specs) {
        for (const [x, y, dx, dy] of [[60, 50, 0, -524], [3260, 1610, 0, 524], [40, 700, -524, 0], [3300, 600, 524, 0], [1600, 800, 32, -56]]) {
            for (const collapsedScale of [0.88, 0.96, 1]) {
                const body = { x, y, width: 500, height: 500 };
                const area = bounds.motion(screen.width, screen.height, body, empty, dx, dy, collapsedScale, 40, spec);
                let value = 0;
                let velocity = 0;
                for (let frame = 0; frame < 240; frame++) {
                    const target = Math.floor(frame / 17) % 2 === 0 ? 1 : 0;
                    const matrix = solver.coefficients(spec.stiffness, spec.damping, spec.mass, 1 / 144);
                    const displacement = value - target;
                    value = target + matrix[0] * displacement + matrix[1] * velocity;
                    velocity = matrix[2] * displacement + matrix[3] * velocity;
                    const scale = collapsedScale + (1 - collapsedScale) * value;
                    contains(area, bounds.clip({
                        x: x + dx * (1 - value) + body.width * (1 - scale) / 2 - 40,
                        y: y + dy * (1 - value) + body.height * (1 - scale) / 2 - 40,
                        width: body.width * scale + 80,
                        height: body.height * scale + 80
                    }, screen.width, screen.height));
                }
            }
        }
    }
});

test("ordinary popouts avoid a full-screen strip and retain an earlier footprint", () => {
    const body = { x: 1600, y: 60, width: 500, height: 500 };
    const area = bounds.motion(screen.width, screen.height, body, empty, 0, -16, 0.96, 40, spring(1));
    const previousStripArea = (body.width + 80) * screen.height;
    assert.ok(area.width * area.height < previousStripArea / 3);
    const origin = { x: 1400, y: 40, width: 800, height: 700 };
    const expanded = bounds.motion(screen.width, screen.height, body, origin, 0, -16, 0.96, 40, spring(1));
    contains(expanded, origin);
    contains(expanded, area);
    const retained = bounds.unite(expanded, area);
    assert.deepEqual({ ...retained }, { ...expanded });
});

test("an open surface fits the output after its resolution shrinks", () => {
    const old = {x: 2000, y: 0, width: 800, height: 2160};
    const current = {x: 1000, y: 0, width: 600, height: 1080};
    assert.deepEqual({ ...bounds.clip(bounds.unite(old, current), 1920, 1080) }, {x: 1000, y: 0, width: 920, height: 1080});
});

test("an origin outside a smaller output still yields an on-screen surface", () => {
    const result = bounds.motion(1280, 720, { x: 1500, y: 40, width: 200, height: 300 }, { x: 1600, y: 40, width: 200, height: 300 }, 0, 0, 1, 40, spring(1));
    assert.deepEqual({ ...result }, { x: 1279, y: 0, width: 1, height: 380 });
});
