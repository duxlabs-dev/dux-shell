import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const source = readFileSync(new URL("../Common/Theme.qml", import.meta.url), "utf8");
const theme = vm.createContext({ barHeight: 48, iconSize: 24, iconSizeLarge: 32 });
for (const name of ["snapEven", "barWidgetThickness", "barThickness", "barIconSize"]) {
    const fn = source.match(new RegExp(`^    function ${name}\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}`, "m"));
    vm.runInContext(fn[0], theme);
}

test("zero widget inset fills bars independently of size and display scale", () => {
    for (const dpr of [1, 1.25, 1.5, 2]) {
        for (const size of [-8, 0, 2, 12, 24]) {
            const thickness = theme.barThickness(size, dpr);
            assert.equal(theme.barWidgetThickness(size, dpr, 0, thickness), thickness);
        }
        assert.equal(theme.barWidgetThickness(2, dpr, 0, 51), 51);
    }
});

test("widget inset changes widget thickness without changing the bar", () => {
    for (const size of [2, 12, 24]) {
        const thickness = theme.barThickness(size, 1);
        const minimum = theme.barWidgetThickness(size, 1);
        assert.equal(theme.barWidgetThickness(size, 1, 4, thickness), thickness - 8);
        assert.equal(theme.barWidgetThickness(size, 1, 8, thickness), Math.max(minimum, thickness - 16));
        assert.equal(theme.barWidgetThickness(size, 1, -1, thickness), theme.barWidgetThickness(size, 1));
    }
});

test("large insets preserve room for icons at the current bar size", () => {
    for (const dpr of [1, 1.25, 1.5, 2]) {
        for (const size of [-8, 0, 2, 12, 24]) {
            const thickness = theme.barThickness(size, dpr);
            const widget = theme.barWidgetThickness(size, dpr, 100, thickness);
            assert.equal(widget, theme.barWidgetThickness(size, dpr));
            assert.ok(widget >= theme.barIconSize(thickness, 0, false, 1));
        }
    }
});
