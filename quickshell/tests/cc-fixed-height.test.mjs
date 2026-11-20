import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const layout = loadScript(new URL("../Common/ControlCenterLayout.js", import.meta.url));
const grid = loadScript(new URL("../Common/GridLayout.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

test("dock pills narrow into half-column gaps without displacing their neighbors", () => {
    const items = [{ id: "top", w: 7, h: 1, col: 0, row: 0 }, { id: "neighbor", w: 3.5, h: 1, col: 0, row: 1 }];
    const widget = { id: "new", w: 4, h: 1 };
    for (const mirror of [false, true]) {
        const packed = grid.packCards(items, [0, 1], 7, 496, 8, 64, mirror, null, 0.5, true);
        for (const geometry of [packed, grid.shrinkRows(packed, [false, true], 36)]) {
            for (const rowLimit of [0, 2]) {
                for (const col of [3.5, 5, 6.5]) {
                    const logicalX = col * 72 + 4;
                    const x = mirror ? geometry.width - logicalX : logicalX;
                    const y = geometry.slots[1].y + geometry.slots[1].h / 2;
                    const fit = layout.externalPlacement(widget, geometry, x, y, 400, rowLimit, size => size);
                    assert.deepEqual(plain(fit), { id: "new", w: 3.5, h: 1, col: 3.5, row: 1 });
                    const trial = items.concat([{ ...widget, ...fit }]);
                    const cells = grid.packCells(trial, [2, 0, 1], 7, null, 0.5, true).cells;
                    const saved = grid.placedItems(trial, cells);
                    assert.deepEqual(plain(layout.paginate(saved, 7, rowLimit)), trial);
                }
            }
        }
    }
    assert.equal(widget.w, 4, "fitting a preview must not change the default for the next hover");
});

test("occupied half-width columns size incoming pills before preview and pagination", () => {
    const items = [
        { id: "top", w: 7, h: 1, col: 0, row: 0 },
        { id: "left", w: 3.5, h: 1, col: 0, row: 1 },
        { id: "right", w: 3.5, h: 1, col: 3.5, row: 1 },
        { id: "bottom-left", w: 3.5, h: 1, col: 0, row: 2 },
        { id: "bottom-right", w: 3.5, h: 1, col: 3.5, row: 2 }
    ];
    for (const mirror of [false, true]) {
        const packed = grid.packCards(items, [0, 1, 2, 3, 4], 7, 496, 8, 64, mirror, null, 0.5, true);
        for (const geometry of [packed, grid.shrinkRows(packed, items.map(() => true), 36)]) {
            for (const rowLimit of [0, 3]) {
                for (const index of [1, 2]) {
                    const slot = geometry.slots[index];
                    const fit = layout.externalPlacement({ id: "new", w: 4, h: 1 }, geometry, slot.x + slot.w / 2, slot.y + slot.h / 2, 400, rowLimit, size => size);
                    assert.equal(fit?.w, 3.5, "a filled column must use its width before displacing any tiles");
                    assert.deepEqual([fit.col, fit.row, fit.h], [items[index].col, 1, 1]);
                    const trial = items.concat([fit]);
                    const cells = grid.packCells(trial, [5, 0, 1, 2, 3, 4], 7, null, 0.5, true).cells;
                    const saved = layout.paginate(grid.placedItems(trial, cells), 7, rowLimit);
                    const other = index === 1 ? 2 : 1;
                    assert.deepEqual(plain(saved[other]), items[other], "the neighboring column must stay in place");
                    assert.deepEqual(Array.from(saved.slice(0, 5), item => [item.w, item.h]), items.map(item => [item.w, item.h]));
                    assert.equal(saved[5].w, 3.5, "the committed tile must retain the preview width");
                    assert.deepEqual(Array.from(saved.filter(item => item.page), item => item.id), rowLimit ? [items[index + 2].id] : []);
                }
            }
        }
    }
    const guards = [{ w: 3.5, h: 1, col: 0, row: 0 }, { w: 3.5, h: 1, col: 3.5, row: 0 }];
    const packed = grid.packCards(guards, [0, 1], 7, 496, 8, 64, false, null, 0.5, true);
    assert.equal(layout.externalPlacement({ w: 1, h: 1 }, packed, 50, 20, 400, 2, size => size), null);
    assert.equal(layout.externalPlacement({ w: 4, h: 2 }, packed, 50, 20, 400, 2, size => size), null);
    assert.equal(layout.externalPlacement({ w: 4, h: 1 }, packed, 50, 20, 400, 2, () => ({ w: 4, h: 1 })), null);
    assert.equal(layout.externalPlacement({ w: 4, h: 1 }, packed, 50, 20, 400, 2, () => ({ w: 3.5, h: 2 })), null);
    const icons = grid.packCards([{ w: 1, h: 1, col: 0, row: 0 }], [0], 7, 496, 8, 64, false, null, 0.5, true);
    assert.equal(layout.externalPlacement({ w: 4, h: 1 }, icons, 20, 20, 400, 2, size => size), null);
});

test("dock pills dropped into an open row center under the pointer like their ghost", () => {
    const items = [{ id: "top", w: 7, h: 1, col: 0, row: 0 }, { id: "left", w: 3.5, h: 1, col: 0, row: 1 }, { id: "right", w: 3.5, h: 1, col: 3.5, row: 1 }];
    for (const mirror of [false, true]) {
        const geometry = grid.packCards(items, [0, 1, 2], 7, 496, 8, 64, mirror, null, 0.5, true);
        const y = geometry.totalHeight + 20;
        for (const [logicalX, col] of [[180, 0.5], [20, 0], [480, 3]]) {
            const x = mirror ? geometry.width - logicalX : logicalX;
            const fit = layout.externalPlacement({ id: "new", w: 4, h: 1 }, geometry, x, y, 400, 0, size => size);
            assert.deepEqual([fit?.col, fit?.row, fit?.w], [col, 2, 4]);
        }
    }
});

test("dock fitting leaves full-width insertion unchanged and rejects reserved rows and incompatible minimum sizes", () => {
    const items = [{ w: 4, h: 1, col: 0, row: 0 }, { w: 3, h: 1, col: 0, row: 1 }];
    const packed = grid.packCards(items, [0, 1], 4, 280, 8, 64, false, null, 0.5, true);
    const widget = { w: 4, h: 1 };
    assert.equal(layout.externalPlacement(widget, packed, 20, 20, 400, 2, size => size), null);
    assert.equal(layout.externalPlacement(widget, packed, 250, 80, 400, 2, () => ({ w: 2, h: 1 })), null);
    assert.equal(layout.externalPlacement(widget, packed, 250, 80, 400, 2, () => ({ w: 1, h: 2 })), null);
    const compressed = grid.shrinkRows(packed, [true, true], 36);
    assert.equal(layout.externalPlacement(widget, compressed, 250, 200, 400, 2, size => size), null);
});

test("overflow previews retain the tile that owns the resize grab", () => {
    const items = Array.from({ length: 4 }, (_, row) => ({ w: 4, h: row === 3 ? 2 : 1, col: 0, row }));
    const packed = grid.packCards(items, [3, 0, 1, 2], 4, 280, 8, 64, false, null, 0.5, true);
    const preview = layout.pageLayout(packed, 4, 3);
    assert.ok(preview.slots[3], "the active delegate must retain its pointer grab");
    assert.equal(preview.totalHeight, 280, "the overflow must not grow the panel");
    assert.equal(preview.commitSlots[3].rows, 2);
});

test("fixed gravity never settles a dragged fractional tile beyond the last row", () => {
    const items = [[0, 0, 1.5, 1], [1.5, 0, 1.5, 1], [0, 1, 2, 1.5], [3, 0, 1, 1.5], [2, 1.5, 1.5, 2], [0, 2.5, 1, 1]].map(([col, row, w, h], i) => ({ id: String(i), col, row, w, h }));
    const cells = grid.packCells(items, items.map((_, i) => i), 4, null, 0.5, true).cells;
    const order = grid.interactionOrder(items, cells, 0, false);
    const pack = trial => grid.packCells(trial, order, 4, null, 0.5, true).cells;
    const target = { col: 0, row: 3 };
    const changed = items.map((item, i) => i === 0 ? { ...item, ...target } : item);
    const result = pack(grid.dropInto(changed, cells, 0, target, pack, 0.5, 4));
    assert.ok(result[0].row + result[0].rows <= 4);
    assert.equal(items[0].row, 0);
});

test("dragging below a short auto layout does not throw when gravity has no trial rows", () => {
    const items = [{ w: 1, h: 1, col: 0, row: 0 }];
    const cells = grid.packCells(items, [0], 4, null, 0.5, true).cells;
    const changed = [{ ...items[0], row: 20 }];
    assert.doesNotThrow(() => grid.dropInto(changed, cells, 0, { col: 0, row: 20 }, trial => grid.packCells(trial, [0], 4, null, 0.5, true).cells, 0.5));
});

test("compressed fixed pages reject drops in shared height reserve but keep unfilled rows usable", () => {
    const items = Array.from({ length: 4 }, () => ({ w: 4, h: 1 }));
    const full = grid.packCards(items, [0, 1, 2, 3], 4, 280, 8, 64, false, null, 0.5, true);
    const compressed = grid.shrinkRows(full, [true, true, true, true], 36);
    assert.equal(layout.heightForRows([compressed, full], 4, 64, 8), 280);
    assert.equal(grid.inRows(compressed, 270, 4), false);
    assert.equal(grid.inRows(compressed, 160, 4), true);
    const short = grid.shrinkRows(grid.packCards(items.slice(0, 1), [0], 4, 280, 8, 64, false, null, 0.5, true), [true], 36);
    assert.equal(grid.inRows(short, 90, 2), true, "an actual empty fixed row remains a drop target");
    assert.equal(grid.inRows(short, 200, 2), false);
    assert.equal(grid.inRows(short, 200, 0), true, "auto height remains unrestricted");
});

test("fixed previews hide spilled tiles while retaining their commit cells", () => {
    const items = [
        { id: "top", w: 4, h: 1, col: 0, row: 0 },
        { id: "pill", w: 1, h: 1, col: 0, row: 1 },
        { id: "new", w: 4, h: 1, col: 0, row: 1 }
    ];
    for (const mirror of [false, true]) {
        const packed = grid.packCards(items, [2, 0, 1], 4, 280, 8, 64, mirror, null, 0.5, true);
        for (const geometry of [packed, grid.shrinkRows(packed, [true, true, true], 48)]) {
            const preview = layout.pageLayout(geometry, 2);
            assert.equal(preview.slots[1], null);
            assert.ok(preview.totalHeight < geometry.totalHeight);
            const saved = layout.paginate(grid.placedItems(items, preview.commitSlots), 4, 2);
            assert.equal(saved[1].page, 1);
            assert.deepEqual(saved.filter(widget => !widget.page).map(widget => widget.id), items.filter((_, i) => preview.slots[i]).map(widget => widget.id));
            assert.equal(new Set(saved.map(widget => widget.id)).size, 3);
        }
        assert.equal(layout.pageLayout(packed, 0), packed, "auto previews remain unrestricted");
    }
});

test("add placements validate both dimensions after a size clamp", () => {
    const items = [{ w: 4, h: 1, col: 0, row: 0 }, { w: 3, h: 1, col: 0, row: 1 }];
    const geometry = grid.packCards(items, [0, 1], 4, 280, 8, 64, false, null, 0.5, true);
    const room = { layout: geometry, rowLimit: 2 };
    const pill = layout.placedInRoom({ w: 4, h: 1 }, 4, 3, 1, room, size => size);
    assert.deepEqual(plain(pill), { w: 1, h: 1, col: 3, row: 1 });
    assert.equal(layout.placedInRoom({ w: 4, h: 1 }, 4, 3, 1, room, size => ({ w: size.w, h: 2 })), null);
    assert.equal(layout.placedInRoom({ w: 4, h: 1 }, 4, 3, 1, room, () => ({ w: 2, h: 1 })), null);
    const vertical = layout.placedInRoom({ w: 1, h: 2 }, 4, 3, 1, { layout: geometry, rowLimit: 3 }, size => size);
    assert.deepEqual(plain(vertical), { w: 1, h: 2, col: 3, row: 1 });
    const blocked = grid.packCards(items.concat([{ w: 1, h: 1, col: 3, row: 2 }]), [0, 1, 2], 4, 280, 8, 64, false, null, 0.5, true);
    assert.equal(layout.placedInRoom({ w: 1, h: 2 }, 4, 3, 1, { layout: blocked, rowLimit: 3 }, size => size), null);
});

test("growing consolidates sparse pages in one pass and settles idempotently", () => {
    const widgets = [
        { id: "a", w: 4, h: 1, col: 0, row: 0 },
        { id: "b", page: 2, w: 4, h: 1 },
        { id: "c", page: 3, w: 4, h: 1 }
    ];
    const result = layout.paginate(widgets, 4, 3, undefined, true);
    assert.deepEqual(Array.from(result, widget => widget.page ?? 0), [0, 0, 0]);
    assert.equal(layout.paginate(result, 4, 3, undefined, true), result);
});

test("fixed drops stay inside the row budget and preserve tiles above an open last row", () => {
    const items = [{ id: "top", w: 7, h: 1, col: 0, row: 0 }];
    for (const mirror of [false, true]) {
        const slots = grid.packCards(items, [0], 7, 496, 8, 64, mirror, null, 0.5, true);
        for (const geometry of [slots, grid.shrinkRows(slots, [true], 48)]) {
            for (const w of [1, 3.5, 4]) {
                const target = grid.cellAt(geometry, 0, 300, w, 1, 2);
                assert.equal(target.row, 1);
                const trial = items.concat([{ id: "new", w, h: 1, ...target }]);
                const cells = grid.packCells(trial, [1, 0], 7, null, 0.5, true).cells;
                const result = layout.paginate(grid.placedItems(trial, cells), 7, 2);
                assert.deepEqual(plain(result), [items[0], { id: "new", w, h: 1, col: target.col, row: 1 }]);
            }
        }
        assert.ok(grid.cellAt(slots, 0, 300, 4, 1).row > 1, "auto height retains unrestricted targeting");
    }
});

test("fixed add hints exclude reserved space without hiding an available last row", () => {
    const items = [{ id: "top", w: 4, h: 1, col: 0, row: 0 }];
    const slots = grid.packCards(items, [0], 4, 280, 8, 64, false, null, 0.5, true);
    assert.equal(grid.freeCellAt(slots, 10, 80, 400, 2)?.row, 1);
    const full = grid.packCards(items.concat([{ id: "bottom", w: 4, h: 1, col: 0, row: 1 }]), [0, 1], 4, 280, 8, 64, false, null, 0.5, true);
    assert.equal(grid.freeCellAt(full, 10, 160, 400, 2), null);
    assert.equal(grid.freeCellAt(full, 10, 160, 400)?.row, 2);
});

test("fixed rows preserve compressed tile heights and borrow them on short and empty pages", () => {
    const full = grid.packCards([{ w: 4, h: 1 }, { w: 4, h: 1 }], [0, 1], 4, 280, 8, 64, false, null, 0.5, true);
    const short = grid.packCards([{ w: 4, h: 1 }], [0], 4, 280, 8, 64, false, null, 0.5, true);
    const empty = grid.packCards([], [], 4, 280, 8, 64, false, null, 0.5, true);
    const compressed = grid.shrinkRows(full, [true, true], 48);
    const shortCompressed = grid.shrinkRows(short, [true], 48);
    assert.equal(layout.heightForRows([compressed, shortCompressed, empty], 2, 64, 8), 104);
    assert.equal(layout.heightForRows([compressed, shortCompressed, empty], 3, 64, 8), 176);
    assert.equal(layout.heightForRows([compressed, short, empty], 2, 64, 8), 104);
    const height = rows => layout.heightForRows([compressed, shortCompressed, empty], rows, 64, 8);
    assert.equal(grid.nearestStep(rows => 100 + height(rows), 2, 1, 4, 239), 2);
    assert.equal(grid.nearestStep(rows => 100 + height(rows), 2, 1, 4, 241), 3);
    assert.equal(grid.nearestStep(rows => 800 - height(rows), 2, 1, 4, 661), 2);
    assert.equal(grid.nearestStep(rows => 800 - height(rows), 2, 1, 4, 659), 3);
});

test("short pages do not add unused height to a full fixed page", () => {
    const full = grid.packCards([{ w: 4, h: 1 }, { w: 4, h: 1 }], [0, 1], 4, 280, 8, 64, false, null, 0.5, true);
    const short = grid.packCards([{ w: 4, h: 1 }], [0], 4, 280, 8, 64, false, null, 0.5, true);
    const mixed = grid.shrinkRows(full, [true, false], 48);
    assert.equal(layout.heightForRows([mixed, short], 2, 64, 8), mixed.totalHeight);
    assert.equal(layout.heightForRows([short, mixed], 2, 64, 8), mixed.totalHeight);
    assert.equal(layout.heightForRows([mixed, short], 3, 64, 8), mixed.totalHeight + 72);
});

test("fixed height spills tiles before the next page's tiles and carries group members", () => {
    const widgets = [
        { id: "a", w: 4, h: 1, col: 0, row: 0 },
        { id: "quickTiles", instanceId: "group", w: 4, h: 1, col: 0, row: 1 },
        { id: "member", group: "group" },
        { id: "b", page: 1, w: 4, h: 1, col: 0, row: 0 }
    ];
    const result = plain(layout.paginate(widgets, 4, 1));
    assert.deepEqual(result.map(widget => widget.page ?? 0), [0, 1, 1, 2]);
    assert.equal(result[1].row, 0);
    assert.equal(result[3].row, 0);
    assert.equal(widgets[1].page, undefined);
    assert.equal(layout.paginate(result, 4, 1), result, "settled layouts do not cause another settings write");
});

test("growing pulls whole top bands back, preserving their columns and half-row sizes", () => {
    const widgets = [
        { id: "a", w: 4, h: 1, col: 0, row: 0 },
        { id: "left", page: 1, w: 2, h: 0.5, col: 0, row: 0 },
        { id: "right", page: 1, w: 2, h: 1, col: 2, row: 0 },
        { id: "below", page: 1, w: 4, h: 1, col: 0, row: 1 }
    ];
    const result = plain(layout.paginate(widgets, 4, 2, undefined, true));
    assert.deepEqual(result.map(widget => widget.page ?? 0), [0, 0, 0, 1]);
    assert.deepEqual(result.slice(1, 3).map(widget => [widget.col, widget.row, widget.h]), [[0, 1, 0.5], [2, 1, 1]]);
    assert.equal(result[3].row, 0, "the remaining page settles after its top band leaves");
});

test("oversized tiles fit, unavailable tiles stay saved, and orphaned members remain on the grid", () => {
    const widgets = [
        { id: "tall", w: 8, h: 5 },
        { id: "hidden", page: 1, w: 4, h: 1 },
        { id: "orphan", group: "missing", w: 2, h: 1 }
    ];
    const result = plain(layout.paginate(widgets, 4, 2, widget => widget.id !== "hidden"));
    assert.deepEqual([result[0].w, result[0].h], [4, 2]);
    assert.deepEqual(result[1], widgets[1]);
    assert.equal(result[2].page, 1);
    assert.equal(result[2].row, 0);
});

test("spilled pills keep their visual order when saved array order differs", () => {
    const widgets = [
        { id: "top", w: 4, h: 1, col: 0, row: 0 },
        { id: "right", w: 2, h: 1, col: 2, row: 1 },
        { id: "left", w: 2, h: 1, col: 0, row: 1 },
        { id: "next", page: 1, w: 2, h: 1, col: 0, row: 0 }
    ];
    const result = plain(layout.paginate(widgets, 4, 1));
    assert.deepEqual(result.slice(1, 3).map(widget => [widget.page, widget.col, widget.row]), [[1, 2, 0], [1, 0, 0]]);
    assert.equal(result[3].page, 2);
});

test("a resize rebuilt from its grab snapshot returns to the original layout", () => {
    const base = [
        { id: "a", w: 2, h: 1, col: 0, row: 0 },
        { id: "b", w: 2, h: 1, col: 2, row: 0 },
        { id: "c", w: 4, h: 1, col: 0, row: 1 },
        { id: "d", page: 1, w: 4, h: 1, col: 0, row: 0 }
    ];
    assert.deepEqual(Array.from(layout.paginate(base, 4, 1), widget => widget.page ?? 0), [0, 0, 1, 2]);
    assert.deepEqual(plain(layout.paginate(base, 4, 2)), base);
    assert.deepEqual(Array.from(layout.paginate(base, 4, 3, undefined, true), widget => widget.page ?? 0), [0, 0, 0, 0]);
});

test("fixed pagination keeps every shown tile inside the row budget without overlapping", () => {
    for (const columns of [4, 6, 8]) {
        for (const rows of [1, 2, 3]) {
            const widgets = Array.from({ length: 18 }, (_, i) => ({ id: `tile${i}`, w: i % 3 + 1, h: i % 2 ? 1 : 1.5, page: i % 4 }));
            const result = plain(layout.paginate(widgets, columns, rows));
            assert.equal(new Set(result.map(widget => widget.id)).size, widgets.length);
            for (const page of new Set(result.map(widget => widget.page ?? 0))) {
                const items = result.filter(widget => (widget.page ?? 0) === page);
                const packed = grid.packCells(items, items.map((_, i) => i), columns, null, 0.5, true);
                assert.ok(packed.rows <= rows, `${columns} columns, ${rows} rows, page ${page}`);
                assert.deepEqual(plain(packed.cells).map(cell => [cell.col, cell.row]), items.map(widget => [widget.col, widget.row]));
            }
        }
    }
});

test("fixed pages reorder within the last row without spilling a tile", () => {
    const drag = (items, index, target, rowLimit) => {
        const cells = grid.packCells(items, items.map((_, i) => i), 7, null, 0.5, true).cells;
        const order = grid.interactionOrder(items, cells, index, false);
        const pack = trial => grid.packCells(trial, order, 7, null, 0.5, true).cells;
        const changed = items.map((item, i) => i === index ? { ...item, ...target } : item);
        return plain(pack(grid.dropInto(changed, cells, index, target, pack, 0.5, rowLimit))).map(cell => [cell.col, cell.row]);
    };
    const pills = [[0, 0], [3.5, 0], [0, 1], [3.5, 1], [0, 2], [3.5, 2]].map(([col, row], i) => ({ id: String(i), w: 3.5, h: 1, col, row }));
    for (const [index, other] of [[4, 5], [5, 4], [2, 3]]) {
        const placed = drag(pills, index, { col: pills[other].col, row: pills[other].row }, 3);
        assert.deepEqual([placed[index], placed[other]], [[pills[other].col, pills[other].row], [pills[index].col, pills[index].row]], `swap ${index} with ${other}`);
    }
    const stack = [0, 1, 2].map(row => ({ id: String(row), w: 7, h: 1, col: 0, row }));
    assert.deepEqual(drag(stack, 0, { col: 0, row: 2 }, 3), [[0, 2], [0, 0], [0, 1]], "the last row takes a tile dragged onto it");
});
