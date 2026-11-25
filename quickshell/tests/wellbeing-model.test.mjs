import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const model = loadScript(new URL("../Modules/DDash/Wellbeing/Wellbeing.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

const days = [
    { date: "2026-09-27", active: 100, apps: { firefox: 100 } },
    { date: "2026-09-29", active: 200, apps: { firefox: 50, kitty: 150 } },
    { date: "2026-10-01", active: 300, apps: { kitty: 300 } }
];
const thursday = new Date(2026, 9, 1, 15, 0, 0);

test("a week is the seven days ending on the given day, with today marked", () => {
    const week = plain(model.weekEnding(days, thursday, thursday));
    assert.deepEqual(week.map(day => day.date), ["2026-09-25", "2026-09-26", "2026-09-27", "2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"]);
    assert.deepEqual(week.map(day => day.active), [0, 0, 100, 0, 200, 0, 300]);
    assert.deepEqual(week.map(day => day.today), [false, false, false, false, false, false, true]);
    assert.equal(week[6].weekday, 4);
});

test("weeks page back from today across the retained history", () => {
    const weeks = plain(model.weeksBack(days, thursday));
    assert.equal(weeks.length, 14);
    assert.equal(weeks[13][6].date, "2026-10-01");
    assert.equal(weeks[12][6].date, "2026-09-24");
    assert.equal(weeks[12].some(day => day.today), false);
});

test("top apps aggregate across days, sort by time, and honour the limit", () => {
    assert.deepEqual(plain(model.topApps(days)), [{ appId: "kitty", seconds: 450 }, { appId: "firefox", seconds: 150 }]);
    assert.deepEqual(plain(model.topApps(days, 1)), [{ appId: "kitty", seconds: 450 }]);
    assert.deepEqual(plain(model.topApps([{ date: "2026-10-01", active: 5, apps: { idle: 0 } }])), []);
});

test("axis rounds the peak up to whole-hour ticks", () => {
    assert.deepEqual(plain(model.axis(0)), { top: 3600, ticks: [0, 1] });
    assert.deepEqual(plain(model.axis(3 * 3600 + 1)), { top: 4 * 3600, ticks: [0, 1, 2, 3, 4] });
    assert.deepEqual(plain(model.axis(5 * 3600)), { top: 6 * 3600, ticks: [0, 2, 4, 6] });
    assert.deepEqual(plain(model.axis(13 * 3600)), { top: 16 * 3600, ticks: [0, 4, 8, 12, 16] });
});

test("durations split into hours and whole minutes", () => {
    assert.deepEqual(plain(model.splitDuration(3725)), { hours: 1, minutes: 2 });
    assert.deepEqual(plain(model.splitDuration(59)), { hours: 0, minutes: 0 });
    assert.deepEqual(plain(model.splitDuration(-5)), { hours: 0, minutes: 0 });
});
