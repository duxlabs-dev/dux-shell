import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Modules/DBar/SegmentRoles.js", import.meta.url), "utf8");
const context = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma.*$/m, ""), context);
const plain = value => JSON.parse(JSON.stringify(value));
const roles = { resolve: (...args) => plain(context.resolve(...args)) };
const entry = widgetId => ({ widgetId });
const clocks = count => Array.from({ length: count }, (_, index) => entry("clock" + index));

test("runs of participating widgets get first, middle and last roles", () => {
    assert.deepEqual(roles.resolve(clocks(1), [true]), ["solo"]);
    assert.deepEqual(roles.resolve(clocks(4), [true, true, true, true]), ["first", "middle", "middle", "last"]);
    assert.deepEqual(roles.resolve(undefined, undefined), []);
});

test("spacers, separators and non-participating widgets break runs", () => {
    assert.deepEqual(roles.resolve([entry("a"), entry("spacer"), entry("b"), entry("c")], [true, true, true, true]), ["solo", "solo", "first", "last"]);
    assert.deepEqual(roles.resolve(clocks(5), [true, true, false, true, true]), ["first", "last", "solo", "first", "last"]);
});

test("hidden widgets are skipped without breaking the run", () => {
    assert.deepEqual(roles.resolve(clocks(3), [true, null, true]), ["first", "solo", "last"]);
    assert.deepEqual(roles.resolve(clocks(3), [true, true, undefined]), ["first", "last", "solo"]);
});
