import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const rank = vm.createContext({});
vm.runInContext(readFileSync(new URL("../Common/PluginRanking.js", import.meta.url), "utf8").replace(".pragma library", ""), rank);

const NOW = Date.UTC(2026, 9, 10);
const DAY = 86400000;
const ago = days => new Date(NOW - days * DAY).toISOString();
const plugin = (id, extra) => Object.assign({ id, name: id, author: "a-" + id, category: "utilities", upvotes: 0, status: ["reviewed"], compositors: ["any"], screenshot: "x.png", created_at: ago(100), updated_at: ago(100) }, extra || {});
const ids = list => Array.from(list, p => p.id);

test("installed, broken, unmaintained and wrong-compositor plugins are never recommended", () => {
    const list = [plugin("mine", { installed: true, upvotes: 50 }), plugin("broken", { status: ["broken"], upvotes: 50 }), plugin("old", { status: ["unmaintained"], upvotes: 50 }), plugin("hypr", { compositors: ["hyprland"], upvotes: 50 }), plugin("ok", { upvotes: 1 })];
    assert.deepEqual(ids(rank.recommend(list, { now: NOW, compositor: "niri" })), ["ok"]);
    assert.deepEqual(ids(rank.recommend(list, { now: NOW, compositor: "hyprland" })), ["hypr", "ok"]);
});

test("a plugin similar to an installed one outranks a slightly more voted stranger", () => {
    const list = [plugin("shot", { installed: true, similar: ["capture"] }), plugin("capture", { upvotes: 3 }), plugin("stranger", { upvotes: 6, category: "media" })];
    assert.equal(rank.recommend(list, { now: NOW })[0].id, "capture");
    assert.equal(rank.reason(list[1], rank.buildTaste(list), NOW), "similar");
});

test("votes still win when the gap is large", () => {
    const list = [plugin("shot", { installed: true, similar: ["capture"] }), plugin("capture", { upvotes: 1 }), plugin("star", { upvotes: 400, category: "media" })];
    assert.equal(rank.recommend(list, { now: NOW })[0].id, "star");
});

test("trending favours votes gathered fast over the same votes gathered slowly", () => {
    const list = [plugin("veteran", { upvotes: 10, created_at: ago(400) }), plugin("rising", { upvotes: 10, created_at: ago(10) }), plugin("silent", { upvotes: 0, created_at: ago(1) })];
    assert.deepEqual(ids(rank.trendingNow(list, { now: NOW })), ["rising", "veteran"]);
});

test("a single vote on a brand-new plugin does not beat an established one", () => {
    const list = [plugin("fresh", { upvotes: 1, created_at: ago(0) }), plugin("solid", { upvotes: 30, created_at: ago(60) })];
    assert.equal(rank.trendingNow(list, { now: NOW })[0].id, "solid");
});

test("one author gets at most two places", () => {
    const list = ["a", "b", "c", "d"].map((id, i) => plugin(id, { author: "same", upvotes: 40 - i })).concat([plugin("other", { upvotes: 1 })]);
    assert.deepEqual(ids(rank.recommend(list, { now: NOW, limit: 3 })), ["a", "b", "other"]);
});

test("a short shelf is filled with the entries the author limit skipped", () => {
    const list = [1, 2, 3, 4].map(n => plugin("p" + n, { author: "same", upvotes: 10 - n }));
    assert.deepEqual(ids(rank.recommend(list, { now: NOW, limit: 3 })), ["p1", "p2", "p3"]);
    list.push(plugin("other", { upvotes: 1 }));
    assert.deepEqual(ids(rank.recommend(list, { now: NOW, limit: 3 })), ["p1", "p2", "other"]);
});

test("excluded ids are left out of every shelf", () => {
    const list = [plugin("a", { upvotes: 9, created_at: ago(2) }), plugin("b", { upvotes: 5, created_at: ago(3) })];
    const options = { now: NOW, exclude: ["a"] };
    assert.deepEqual(ids(rank.recommend(list, options)), ["b"]);
    assert.deepEqual(ids(rank.trendingNow(list, options)), ["b"]);
    assert.deepEqual(ids(rank.newArrivals(list, options)), ["b"]);
});

test("new arrivals are the last two weeks, newest first", () => {
    const list = [plugin("month", { created_at: ago(30) }), plugin("week", { created_at: ago(6) }), plugin("today", { created_at: ago(0.2) }), plugin("undated", { created_at: "" })];
    assert.deepEqual(ids(rank.newArrivals(list, { now: NOW })), ["today", "week"]);
});

test("picks are stable within their period, differ from each other and rotate", () => {
    const list = [];
    for (let i = 0; i < 60; i++)
        list.push(plugin("p" + i, { upvotes: 60 - i }));
    const day = rank.pickOfTheDay(list, NOW);
    const week = rank.pickOfTheWeek(list, NOW);
    assert.equal(rank.pickOfTheDay(list, NOW + 5 * 3600000).id, day.id);
    assert.notEqual(day.id, week.id);
    const monday = Date.UTC(2026, 9, 5);
    const weekIds = new Set([0, 1, 2, 3, 4, 5, 6].map(d => rank.pickOfTheWeek(list, monday + d * DAY).id));
    assert.equal(weekIds.size, 1);
    const days = new Set();
    for (let d = 0; d < 30; d++)
        days.add(rank.pickOfTheDay(list, NOW + d * DAY).id);
    assert.ok(days.size >= 12, "30 days gave only " + days.size + " different picks");
    const weeks = new Set();
    for (let w = 0; w < 12; w++)
        weeks.add(rank.pickOfTheWeek(list, NOW + w * 7 * DAY).id);
    assert.ok(weeks.size >= 5, "12 weeks gave only " + weeks.size + " different picks");
});

test("picks need a review and a screenshot, and survive an empty list", () => {
    assert.equal(rank.pickOfTheDay([], NOW), null);
    assert.equal(rank.pickOfTheWeek([plugin("raw", { status: [] }), plugin("blind", { screenshot: "" })], NOW), null);
});

test("no taste, no dates, no votes: still a deterministic order", () => {
    const list = [{ id: "b" }, { id: "a" }, { id: "c", upvotes: 1 }];
    assert.deepEqual(ids(rank.recommend(list, { now: NOW })), ["c", "a", "b"]);
});

test("an upvote is posted to the reactions of the plugin's GitHub issue only", () => {
    assert.equal(rank.issueReactionsPath("https://github.com/duxlabs-dev/dux-plugin-registry/issues/42"), "repos/duxlabs-dev/dux-plugin-registry/issues/42/reactions");
    assert.equal(rank.issueReactionsPath("https://github.com/a/b.c/issues/7#issuecomment-1"), "repos/a/b.c/issues/7/reactions");
    for (const url of ["", undefined, "https://example.com/a/b/issues/1", "https://github.com/a/b/pull/1", "https://github.com/a/b/issues/1/../../x", "https://github.com/a/b/issues/1 -f x=y", "http://github.com/a/b/issues/1", "https://github.com/../b/issues/1", "https://github.com/a/../issues/1", "https://github.com/./b/issues/1", "https://github.com/a/./issues/1"])
        assert.equal(rank.issueReactionsPath(url), "");
    assert.equal(rank.issueReactionsPath("https://github.com/a/.github/issues/3"), "repos/a/.github/issues/3/reactions");
});

test("the upvote count follows each click without double counting a vote the registry already has", () => {
    const click = (state, removed, created) => rank.nextUpvoteDelta(state, removed, created);
    // New vote, taken back, voted again.
    let delta = click(0, false, true);
    assert.equal(rank.upvoteCount(10, delta), 11);
    delta = click(delta, true, false);
    assert.equal(rank.upvoteCount(10, delta), 10);
    delta = click(delta, false, true);
    assert.equal(rank.upvoteCount(10, delta), 11);
    // The account had already voted before this session: GitHub answers 200, the registry count already holds it.
    delta = click(0, false, false);
    assert.equal(rank.upvoteCount(10, delta), 10);
    delta = click(delta, true, false);
    assert.equal(rank.upvoteCount(10, delta), 9);
    // A stale registry count never shows below zero.
    assert.equal(rank.upvoteCount(0, click(0, true, false)), 0);
    assert.equal(rank.upvoteCount(undefined, undefined), 0);
});

test("a card is marked new for two weeks, then updated for a week after a release", () => {
    assert.equal(rank.recency(plugin("a", { created_at: ago(3), updated_at: ago(1) }), NOW), "new");
    assert.equal(rank.recency(plugin("b", { created_at: ago(90), updated_at: ago(2) }), NOW), "updated");
    assert.equal(rank.recency(plugin("c", { created_at: ago(90), updated_at: ago(30) }), NOW), "");
    assert.equal(rank.recency(plugin("d", { created_at: undefined, updated_at: undefined }), NOW), "");
});

test("the reaction id is read from a gh reply, so the vote can be taken back", () => {
    const body = JSON.stringify({ id: 987, node_id: "x", user: { login: "someone", id: 5 }, content: "+1" });
    assert.equal(rank.reactionId("HTTP/2.0 201 Created\r\nEtag: \"a{b\"\r\n\r\n" + body), 987);
    assert.equal(rank.reactionId("HTTP/2.0 201 Created\r\nServer: github.com\r\n\r\n" + body), 987);
    assert.equal(rank.reactionId("HTTP/2.0 200 OK\n\n" + body), 987);
    for (const reply of ["", undefined, "HTTP/2.0 401 Unauthorized\n\n{\"message\":\"Bad credentials\"}", "HTTP/2.0 200 OK\n\n{\"id\":3,\"content\":\"heart\"}", "{not json"])
        assert.equal(rank.reactionId(reply), 0);
});

test("a plugin limited to other compositors names them, a portable one names none", () => {
    assert.deepEqual(Array.from(rank.unsupportedOn(plugin("a", { compositors: ["hyprland", "sway"] }), "niri")), ["hyprland", "sway"]);
    assert.deepEqual(Array.from(rank.unsupportedOn(plugin("b", { compositors: ["niri"] }), "niri")), []);
    assert.deepEqual(Array.from(rank.unsupportedOn(plugin("c", { compositors: ["any"] }), "niri")), []);
    assert.deepEqual(Array.from(rank.unsupportedOn(plugin("d", { compositors: ["hyprland"] }), "")), []);
    assert.deepEqual(Array.from(rank.unsupportedOn(plugin("e", { compositors: undefined }), "niri")), []);
});

test("quick filters keep only the plugins matching every set filter", () => {
    const here = plugin("a", { compositors: ["niri"], firstParty: true, created_at: ago(2), updated_at: ago(1) });
    const elsewhere = plugin("b", { compositors: ["hyprland"], firstParty: false, created_at: ago(200), updated_at: ago(100) });
    assert.equal(rank.matchesFilters(elsewhere, {}, "niri", NOW), true);
    assert.equal(rank.matchesFilters(elsewhere, null, "niri", NOW), true);
    assert.equal(rank.matchesFilters(here, { usable: true, fresh: true, official: true }, "niri", NOW), true);
    assert.equal(rank.matchesFilters(elsewhere, { usable: true }, "niri", NOW), false);
    assert.equal(rank.matchesFilters(elsewhere, { fresh: true }, "niri", NOW), false);
    assert.equal(rank.matchesFilters(elsewhere, { official: true }, "niri", NOW), false);
    assert.equal(rank.matchesFilters(here, { usable: true }, "hyprland", NOW), false);
});

test("lists that are not real arrays (QML sequences) are still read", () => {
    const seq = items => Object.assign(Object.create(null), items, { length: items.length });
    assert.equal(rank.isUsable(plugin("a", { compositors: seq(["hyprland"]) }), "niri"), false);
    assert.equal(rank.isUsable(plugin("b", { status: seq(["broken"]) }), "niri"), false);
    assert.deepEqual(Array.from(rank.unsupportedOn(plugin("c", { compositors: seq(["hyprland"]) }), "niri")), ["hyprland"]);
});

const found = (list, query) => ids(list.filter(p => rank.searchRank(p, rank.searchPlan(list, query)) > 0));

test("search reads name, author, category, capabilities and dependencies", () => {
    const list = [plugin("clock", { name: "World Clock", author: "Ada" }), plugin("shot", { name: "Quick Capture", capabilities: ["launcher"], dependencies: ["grim"] }), plugin("music", { name: "Tunes", category: "media" })];
    assert.deepEqual(found(list, "clock"), ["clock"]);
    assert.deepEqual(found(list, "ada"), ["clock"]);
    assert.deepEqual(found(list, "launcher"), ["shot"]);
    assert.deepEqual(found(list, "grim"), ["shot"]);
    assert.deepEqual(found(list, "media"), ["music"]);
    assert.deepEqual(found(list, "quick launcher"), ["shot"]);
    assert.deepEqual(found(list, ""), ["clock", "shot", "music"]);
});

test("a typo is forgiven, accents and camelCase do not matter", () => {
    const list = [plugin("wallpaperCarousel", { name: "Wallpaper Carousel" }), plugin("cafe", { name: "Café Timer" }), plugin("dockerManager", { name: "dockerManager" })];
    assert.deepEqual(found(list, "walpaper"), ["wallpaperCarousel"]);
    assert.deepEqual(found(list, "wallpapre"), ["wallpaperCarousel"]);
    assert.deepEqual(found(list, "carousle"), ["wallpaperCarousel"]);
    assert.deepEqual(found(list, "cafe"), ["cafe"]);
    assert.deepEqual(found(list, "manager"), ["dockerManager"]);
    assert.deepEqual(found(list, "dokcer"), ["dockerManager"]);
});

test("a camelCase name, id or author typed as one word still matches", () => {
    const list = [plugin("orbitBluetooth", { author: "AvengeMedia" }), plugin("clock", { name: "World Clock", author: "Ada" })];
    assert.deepEqual(found(list, "avengemedia"), ["orbitBluetooth"]);
    assert.deepEqual(found(list, "orbitbluetooth"), ["orbitBluetooth"]);
    assert.deepEqual(found(list, "orbitbluetoth"), ["orbitBluetooth"]);
    assert.deepEqual(found(list, "avenge"), ["orbitBluetooth"]);
    assert.deepEqual(found(list, "media"), ["orbitBluetooth"]);
    assert.deepEqual(found(list, "bluetooth"), ["orbitBluetooth"]);
});

test("a name without camelCase is indexed once", () => {
    const words = Array.from(rank._searchText(plugin("clock", { name: "World Clock" })).words);
    assert.equal(words.filter(w => w === "world").length, 1);
});

test("a huge query is cut to its first eight whole words of at most 100 characters", () => {
    const list = [plugin("orbitBluetooth", { name: "Orbit Bluetooth" }), plugin("weather", { name: "Weather" }), plugin("clock", { name: "World Clock" })];
    const tokens = query => Array.from(rank.searchPlan(list, query), t => t.token);
    assert.equal(tokens("aA".repeat(5000)).length, 8);
    assert.deepEqual(tokens("orbit " + "blutooth ".repeat(3000)), ["orbit", "blutooth", "blutooth", "blutooth", "blutooth", "blutooth", "blutooth", "blutooth"]);
    assert.deepEqual(found(list, "orbit " + "blutooth ".repeat(3000)), ["orbitBluetooth"]);
    assert.deepEqual(tokens("x".repeat(200)), ["x".repeat(100)]);
    assert.deepEqual(tokens("clock" + " ".repeat(94) + "weather"), ["clock"]);
    assert.deepEqual(ids(rank.closest(list, "weather ".repeat(8) + "qqqqqqqq qqqqqqqq", 4)), ["weather"]);
});

test("a correctly typed word never picks up look-alikes", () => {
    const list = [plugin("dark", { name: "Dark Mode" }), plugin("dank", { name: "Dank Clock" }), plugin("lock", { name: "Lock" })];
    assert.deepEqual(found(list, "dark"), ["dark"]);
    assert.deepEqual(found(list, "lock"), ["dank", "lock"]);
    assert.deepEqual(found(list, "zzzzzz"), []);
    assert.deepEqual(found(list, "do"), []);
});

test("closest proposes the nearest names when nothing matches", () => {
    const list = [plugin("weather", { name: "Weather", upvotes: 2 }), plugin("feather", { name: "Feather", upvotes: 9 }), plugin("notes", { name: "Notes" })];
    assert.deepEqual(ids(rank.closest(list, "wether", 3)), ["weather", "feather"]);
    assert.deepEqual(ids(rank.closest(list, "qqqqqqqq", 3)), []);
    assert.deepEqual(ids(rank.closest(list, "", 3)), []);
    assert.equal(rank.closest(list, "eather", 1).length, 1);
});

test("byAuthor lists one author's plugins whatever the case", () => {
    const list = [plugin("a", { author: "Jane Example" }), plugin("b", { author: "jane example " }), plugin("c", { author: "Other" }), plugin("d", { author: "AvengeMedia" }), plugin("e", { author: "avengemedia" }), plugin("f", { author: "Avenge Media" }), plugin("g", { author: "示例 作者" }), plugin("h", { author: "Avenge-Media" })];
    assert.deepEqual(ids(rank.byAuthor(list, "示例作者")), ["g"]);
    assert.deepEqual(ids(rank.byAuthor(list, "Jane Example")), ["a", "b"]);
    assert.deepEqual(ids(rank.byAuthor(list, "AvengeMedia")), ["d", "e", "f", "h"]);
    assert.deepEqual(ids(rank.byAuthor(list, "avengemedia")), ["d", "e", "f", "h"]);
    assert.deepEqual(ids(rank.byAuthor(list, "Avenge Media")), ["d", "e", "f", "h"]);
    assert.deepEqual(ids(rank.byAuthor(list, "Avenge-Media")), ["d", "e", "f", "h"]);
    assert.deepEqual(ids(rank.byAuthor(list, "")), []);
});

test("permissions that reach outside the plugin come first", () => {
    assert.deepEqual(Array.from(rank.sortPermissions(["settings_read", "settings_write", "network", "process"])), ["process", "network", "settings_read", "settings_write"]);
    assert.equal(rank.permissionIsSensitive("shell_execute"), true);
    assert.equal(rank.permissionIsSensitive("settings_read"), false);
});

test("dependencies are checked by command, libraries stay unknown", () => {
    const deps = ["curl", "jq", "wl-clipboard", "qt6-websockets", "imagemagick"];
    const states = rank.dependencyStates(deps, ["curl", "wl-copy", "convert"], ["curl", "jq", "wl-copy", "magick", "convert"]);
    assert.deepEqual(Array.from(states, s => s.name + ":" + s.state), ["curl:ok", "jq:missing", "wl-clipboard:ok", "qt6-websockets:unknown", "imagemagick:ok"]);
    // Before the lookup answers, or when it fails, nothing is reported missing.
    assert.deepEqual(Array.from(rank.dependencyStates(deps, [], []), s => s.state), ["unknown", "unknown", "unknown", "unknown", "unknown"]);
    assert.deepEqual(Array.from(rank.dependencyStates(["imagemagick"], [], ["magick"]), s => s.state), ["unknown"]);
    assert.deepEqual(Array.from(rank.dependencyCommands("lib; rm -rf")), []);
});

test("the report link is prefilled and only built for GitHub repositories", () => {
    const url = rank.issueReportUrl({ id: "clock", name: "World Clock", version: "1.2.0", repo: "https://github.com/ada/clock" }, { dms: "1.4.0", compositor: "niri" });
    assert.ok(url.startsWith("https://github.com/ada/clock/issues/new?title=%5BWorld%20Clock%5D%20&body="));
    const body = decodeURIComponent(url.split("&body=")[1]);
    assert.ok(body.includes("World Clock (`clock`) v1.2.0") && body.includes("**DMS:** 1.4.0") && body.includes("**Compositor:** niri"));
    assert.equal(rank.issueReportUrl({ id: "x", repo: "https://example.org/x" }, {}), "");
    assert.equal(rank.shareUrl({ issueUrl: "https://github.com/a/b/issues/1", repo: "https://github.com/a/b" }), "https://github.com/a/b/issues/1");
    assert.equal(rank.shareUrl({ repo: "javascript:alert(1)" }), "");
});
