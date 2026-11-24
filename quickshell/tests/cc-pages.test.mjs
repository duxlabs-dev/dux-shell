import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const pages = loadScript(new URL("../Modules/ControlCenter/utils/pages.js", import.meta.url));

const plain = list => JSON.parse(JSON.stringify(list));
const pageList = list => Array.from(list, widget => pages.pageOf(widget));
const shownExcept = id => widget => widget.id !== id;

test("page count only counts tiles on the grid", () => {
    const cases = [
        [[{ id: "a" }, { id: "b", page: "3" }, { id: "c", page: -2 }, { id: "d", page: 1.5 }], undefined, 1],
        [[{ id: "a" }, { id: "b", page: 2 }], undefined, 3],
        [[{ id: "a" }, { id: "battery", page: 2 }], shownExcept("battery"), 1],
        [[{ id: "a" }, { id: "quickTiles", instanceId: "g" }, { id: "m", group: "g", page: 4 }], undefined, 1],
        [[{ id: "a" }, { id: "m", group: "gone", page: 4 }], undefined, 5]
    ];
    for (const [widgets, isShown, count] of cases)
        assert.equal(pages.pageCount(widgets, isShown), count, JSON.stringify(widgets));
});

test("compacting drops empty pages and leaves contiguous tiles untouched", () => {
    const widgets = [
        { id: "a", col: 0, row: 0 },
        { id: "quickTiles", instanceId: "g", page: 3, col: 1, row: 0 },
        { id: "m", group: "g", page: 3 },
        { id: "b", page: 5, col: 2, row: 1 },
        { id: "battery", page: 4, col: 0, row: 0 },
        { id: "battery", page: 7, col: 3, row: 2 }
    ];
    const compacted = pages.compactPages(widgets, shownExcept("battery"));
    assert.deepEqual(pageList(compacted), [0, 1, 1, 2, 2, 2]);
    assert.equal(compacted[0], widgets[0]);
    assert.deepEqual(plain(compacted[3]), { id: "b", page: 2, col: 2, row: 1 });
    assert.deepEqual(plain(compacted[4]), { id: "battery", page: 2 }, "a hidden tile on a dropped page loses its cell");
    assert.deepEqual(plain(compacted[5]), { id: "battery", page: 2 });
    assert.equal(widgets[3].page, 5, "the input is not mutated");

    const settled = pages.compactPages(compacted, shownExcept("battery"));
    assert.equal(settled, compacted);
    assert.deepEqual(plain(pages.compactPages([{ id: "a", page: 2, col: 1, row: 1 }])), [{ id: "a", col: 1, row: 1 }]);
});

test("moving to a page unplaces the tile and carries a group's members", () => {
    const widgets = [
        { id: "a", col: 0, row: 0 },
        { id: "quickTiles", instanceId: "g", col: 2, row: 0 },
        { id: "m", group: "g" },
        { id: "n", group: "g" },
        { id: "b", page: 1, col: 0, row: 0 }
    ];
    const moved = pages.movedToPage(widgets, 1, 2);
    assert.deepEqual(plain(moved.slice(1, 4)), [{ id: "quickTiles", instanceId: "g", page: 2 }, { id: "m", group: "g", page: 2 }, { id: "n", group: "g", page: 2 }]);
    assert.equal(moved[0], widgets[0]);
    assert.deepEqual(plain(pages.movedToPage(widgets, 4, 0)[4]), { id: "b" });
    assert.deepEqual(plain(pages.movedToPage(widgets, 0, 1, { col: 2, row: 1.5 })[0]), { id: "a", page: 1, col: 2, row: 1.5 });
    for (const [index, page] of [[2, 1], [0, 0], [9, 1]])
        assert.equal(pages.movedToPage(widgets, index, page), widgets, `index ${index} to page ${page}`);
});

test("the page shown after compacting is the nearest used page at its compacted index", () => {
    const widgets = [{ id: "a", page: 1 }, { id: "b", page: 3 }, { id: "battery", page: 4 }, { id: "c", page: 6 }];
    const isShown = shownExcept("battery");
    const used = pages.usedPages(widgets, isShown);
    const compacted = pages.compactPages(widgets, isShown);
    for (const [page, index] of [[0, 0], [1, 0], [2, 0], [3, 1], [4, 1], [5, 2], [6, 2], [7, 2]]) {
        const shown = pages.nearestIndex(used, page);
        assert.equal(shown, index, `page ${page}`);
        assert.equal(pages.pageOf(compacted[widgets.findIndex(widget => pages.pageOf(widget) === used[shown])]), shown);
    }
    assert.equal(pages.nearestIndex([], 3), 0);
});
