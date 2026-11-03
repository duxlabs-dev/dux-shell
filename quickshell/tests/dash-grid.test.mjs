import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const grid = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/GridLayout.js", import.meta.url), "utf8"), grid);
const cards = [{ id: "clock", w: 2, h: 1 }, { id: "weather", w: 1, h: 1 }, { id: "notifications", w: 3, h: 5 }, { id: "calendar", w: 3, h: 3 }, { id: "media", w: 3, h: 1 }];
const order = cards.map((card, i) => i);
const unit = { w: 1, h: 1 };
const plain = value => JSON.parse(JSON.stringify(value));

test("card spans pack into rows without overlap", () => {
    assert.equal(grid.packCells(cards, order, 6).rows, 5);
    assert.deepEqual(plain(grid.packCards(cards, order, 6, 600, 0, 100, false).slots[4]), { x: 0, y: 400, w: 300, h: 100, col: 0, row: 4, cols: 3, rows: 1 });
});

test("resize keeps the board within its rows", () => {
    assert.deepEqual(plain(grid.fitResize(cards, order, 6, 5, 4, { w: 3, h: 2 }, unit)), { w: 3, h: 1 });
    assert.deepEqual(plain(grid.fitResize(cards, order, 6, 5, 4, { w: 1, h: 1 }, unit)), { w: 1, h: 1 });
    assert.deepEqual(plain(grid.fitResize(cards, order, 6, 8, 4, { w: 3, h: 2 }, unit)), { w: 3, h: 2 });
});

test("resize on an overflowing board may shrink but not grow the overflow", () => {
    const over = cards.concat([{ id: "user", w: 3, h: 2 }]);
    const overOrder = over.map((card, i) => i);
    assert.equal(grid.packCells(over, overOrder, 6).rows, 7);
    assert.deepEqual(plain(grid.fitResize(over, overOrder, 6, 5, 5, { w: 3, h: 1 }, unit)), { w: 3, h: 1 });
    assert.deepEqual(plain(grid.fitResize(over, overOrder, 6, 5, 5, { w: 3, h: 3 }, unit)), { w: 3, h: 2 });
});

test("new cards shrink to free space or are rejected", () => {
    const partial = [{ id: "clock", w: 6, h: 4 }, { id: "user", w: 2, h: 1 }];
    assert.equal(grid.fitNewCard(cards, 6, 5, "user", { w: 3, h: 1 }, unit), null);
    assert.deepEqual(plain(grid.fitNewCard(partial, 6, 5, "weather", { w: 1, h: 2 }, unit)), { w: 1, h: 1 });
    assert.deepEqual(plain(grid.fitNewCard(partial, 6, 5, "media", { w: 2, h: 1 }, unit)), { w: 2, h: 1 });
    assert.equal(grid.fitNewCard(partial, 6, 5, "calendar", { w: 3, h: 3 }, { w: 3, h: 3 }), null);
    assert.deepEqual(plain(grid.fitNewCard(partial, 6, 5, "user", { w: 4, h: 3 }, unit)), { w: 4, h: 1 });
});

test("unavailable cards take no space", () => {
    const isAvailable = id => id !== "notifications";
    assert.equal(grid.packCells(cards, order, 6, isAvailable).cells[2], null);
    assert.deepEqual(plain(grid.fitNewCard(cards, 6, 5, "user", { w: 3, h: 3 }, unit, isAvailable)), { w: 3, h: 3 });
});

test("positioned cards keep their cells and push only what they collide with", () => {
    const board = [{ id: "a", w: 2, h: 1, col: 0, row: 0 }, { id: "b", w: 2, h: 1, col: 2, row: 0 }, { id: "c", w: 2, h: 1, col: 4, row: 2 }];
    const packed = grid.packCells(board, [0, 1, 2], 6);
    assert.deepEqual(plain(packed.cells.map(c => [c.col, c.row])), [[0, 0], [2, 0], [4, 2]]);
    const grown = board.map((card, i) => i === 0 ? Object.assign({}, card, { w: 3 }) : card);
    assert.deepEqual(plain(grid.packCells(grown, [0, 1, 2], 6).cells.map(c => [c.col, c.row])), [[0, 0], [2, 1], [4, 2]]);
    assert.deepEqual(plain(grid.packCells(grown, [1, 0, 2], 6).cells.map(c => [c.col, c.row])), [[0, 1], [2, 0], [4, 2]]);
});

test("cards without a cell take the first free one and cells clamp to the columns", () => {
    const board = [{ id: "a", w: 2, h: 2, col: 0, row: 0 }, { id: "b", w: 1, h: 1 }, { id: "c", w: 3, h: 1, col: 5, row: 0 }];
    assert.deepEqual(plain(grid.packCells(board, [0, 1, 2], 6).cells.map(c => [c.col, c.row])), [[0, 0], [2, 0], [3, 0]]);
    assert.deepEqual(plain(grid.packCells([{ id: "a", w: 1, h: 1, col: 0.5, row: 1.5 }], [0], 4, null, 0.5).cells[0]), { col: 0.5, row: 1.5, cols: 1, rows: 1 });
});

test("gravity pulls positioned cards up into holes without jumping over blockers", () => {
    const board = [{ id: "a", w: 2, h: 1, col: 0, row: 0 }, { id: "b", w: 2, h: 1, col: 2, row: 0 }, { id: "c", w: 2, h: 1, col: 0, row: 2 }, { id: "d", w: 2, h: 1, col: 2, row: 3 }];
    assert.deepEqual(plain(grid.packCells(board, [0, 1, 2, 3], 6).cells.map(c => [c.col, c.row])), [[0, 0], [2, 0], [0, 2], [2, 3]]);
    assert.deepEqual(plain(grid.packCells(board, [0, 1, 2, 3], 6, null, 1, true).cells.map(c => [c.col, c.row])), [[0, 0], [2, 0], [0, 1], [2, 1]]);
    const blocked = [{ id: "a", w: 2, h: 1, col: 0, row: 1 }, { id: "b", w: 2, h: 1, col: 0, row: 3 }];
    assert.deepEqual(plain(grid.packCells(blocked, [1, 0], 6, null, 1, true).cells.map(c => [c.col, c.row])), [[0, 0], [0, 1]]);
});

test("a dragged tile snaps to the cell under its corner", () => {
    const layout = grid.packCards(cards, order, 6, 600, 0, 100, false);
    assert.deepEqual(plain(grid.cellAt(layout, 240, 160, 2, 1)), { col: 2, row: 2 });
    assert.deepEqual(plain(grid.cellAt(layout, 560, -30, 2, 1)), { col: 4, row: 0 });
    assert.deepEqual(plain(grid.cellAt(grid.packCards(cards, order, 6, 600, 0, 100, true), 0, 0, 2, 1)), { col: 4, row: 0 });
    assert.deepEqual(plain(grid.placedItems([{ id: "x" }, { id: "y" }], [null, { col: 1, row: 2 }])), [{ id: "x" }, { id: "y", col: 1, row: 2 }]);
});

test("panel step follows the pointer and holds on a pinned edge", () => {
    const rightEdge = step => Math.min(1000, 500 + step * 36);
    assert.equal(grid.nearestStep(rightEdge, 8, 6, 30, rightEdge(8) + 50), 9);
    assert.equal(grid.nearestStep(rightEdge, 20, 6, 30, 1400), 20);
});

const dropped = (cells, index, target, columns = 2, step = 1) => {
    const items = cells.map((cell, i) => ({ id: String(i), w: cell.cols, h: cell.rows, col: cell.col, row: cell.row }));
    const moved = items.map((item, i) => i === index ? Object.assign({}, item, target) : item);
    const order = [index].concat(items.map((item, i) => i).filter(i => i !== index));
    const pack = trial => grid.packCells(trial, order, columns, null, step, true).cells;
    return plain(pack(grid.dropInto(moved, cells, index, target, pack, step)).map(cell => [cell.col, cell.row]));
};

test("a tile dragged down its own stack lands where dropped instead of back above the tile it covers", () => {
    const cells = [{ col: 0, row: 0, cols: 1, rows: 1 }, { col: 0, row: 1, cols: 1, rows: 1 }, { col: 0, row: 2, cols: 1, rows: 2 }];
    assert.deepEqual(dropped(cells, 0, { col: 0, row: 1 }), [[0, 1], [0, 0], [0, 2]]);
    assert.deepEqual(dropped(cells, 0, { col: 0, row: 2 }), [[0, 3], [0, 0], [0, 1]]);
    assert.deepEqual(dropped(cells, 2, { col: 0, row: 0 }), [[0, 2], [0, 3], [0, 0]]);
    assert.deepEqual(dropped(cells, 1, { col: 0, row: 2 }), [[0, 0], [0, 3], [0, 1]]);
});

test("a half-width tile dragged down beside a blocked stack moves one step per half row", () => {
    const cells = [{ col: 0, row: 0, cols: 1, rows: 1 }, { col: 1, row: 0, cols: 0.5, rows: 1 }, { col: 1.5, row: 0, cols: 0.5, rows: 1 }, { col: 0, row: 1, cols: 2, rows: 1 }, { col: 0, row: 2, cols: 2, rows: 1 }];
    const rowOf = target => dropped(cells, 1, { col: 1, row: target }, 2, 0.5)[1][1];
    assert.deepEqual([1, 1.5, 2, 2.5, 3].map(rowOf), [2, 2, 2, 3, 3]);
});

test("a tile dragged down from another column lands where dropped unless gravity would lift it back", () => {
    const cells = [{ col: 0, row: 0, cols: 1, rows: 1 }, { col: 0, row: 1, cols: 1, rows: 1 }, { col: 0, row: 2, cols: 1, rows: 1 }, { col: 1, row: 0, cols: 1, rows: 1 }];
    const items = cells.map((cell, i) => ({ id: "abcd"[i], col: cell.col, row: cell.row }));
    const drop = (index, target) => {
        const moved = items.map((item, i) => i === index ? Object.assign({}, item, target) : item);
        const order = [index].concat(items.map((item, i) => i).filter(i => i !== index));
        const pack = trial => grid.packCells(trial, order, 2, null, 1, true).cells;
        return plain(grid.packCells(grid.dropInto(moved, cells, index, target, pack), order, 2, null, 1, true).cells.map(cell => [cell.col, cell.row]));
    };
    assert.deepEqual(drop(3, { col: 0, row: 1 }), [[0, 0], [0, 2], [0, 3], [0, 1]]);
    assert.deepEqual(drop(0, { col: 0, row: 1 }), [[0, 1], [0, 0], [0, 2], [1, 0]]);
});
