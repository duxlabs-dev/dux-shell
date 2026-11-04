import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const news = loadScript(new URL("../Common/niri/news.js", import.meta.url));

// The loader runs the module in a vm realm: spread before comparing, or the arrays fail on their prototype.
const keysOf = (seen, running) => [...news.newKeys(seen, running)];

test("between 25.11 and 26.04 only the blur keys are new", () => {
    assert.deepEqual(keysOf("25.11", "26.04"), ["look.blurOn", "look.blurStrength", "look.xray", "look.barXray"]);
});

test("nothing seen yet: every key up to the running version is new", () => {
    const keys = news.newKeys("", "25.11");
    assert.ok(keys.includes("columns.altTab"));
    assert.ok(!keys.includes("look.blurOn"), "26.04 keys do not exist in niri 25.11");
    assert.ok(news.newKeys("25.11", "26.04").length < news.newKeys("", "26.04").length);
});

test("the same or an unknown running version shows nothing", () => {
    assert.deepEqual(keysOf("26.04", "26.04"), []);
    assert.deepEqual(keysOf("25.11", ""), []);
    assert.deepEqual(keysOf("25.11", "unknown"), []);
});

test("a running version older than the keys' version shows nothing for them", () => {
    assert.ok(!news.newKeys("", "25.11").includes("look.blurOn"));
});

test("isNew answers per key", () => {
    assert.equal(news.isNew("look.blurOn", "25.11", "26.04"), true);
    assert.equal(news.isNew("columns.altTab", "25.11", "26.04"), false);
    assert.equal(news.isNew("look.blurOn", "25.11", "25.11"), false);
});

test("every mapped version parses and every key is a page key", () => {
    for (const version of news.versions()) {
        assert.ok(news.parseVersion(version), `version ${version} parses`);
        for (const key of news.introduced[version])
            assert.match(key, /^[a-z]+\.[A-Za-z0-9.]+$/);
    }
});
