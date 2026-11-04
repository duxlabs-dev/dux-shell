import assert from "node:assert/strict";
import test from "node:test";
import { include, look, ring, service } from "./niri-page-fake.mjs";

test("a theme colour reaches niri.kdl as hex whoever applies, and follows a theme change", () => {
    const { s, settings, requests, fire } = service();
    s.Registry.sections = [look];
    const sent = () => requests.filter(r => r.method === "niri.config.apply").map(r => r.params.content);
    s.set("look.ringColor", "secondary");
    fire();
    assert.deepEqual(sent(), [ring("#112233")]);
    assert.equal(s.sectionKdl("windows"), ring("#112233").replace(include, ""));

    s.followTheme();
    assert.equal(s.applyTimer.running, false);
    s.themeColors = { secondary: "#778899", tertiary: "#445566" };
    s.followTheme();
    fire();
    assert.deepEqual(sent(), [ring("#112233"), ring("#778899")]);
    // The theme apply is not a page change: undo still goes back to before the colour was picked.
    s.undo();
    assert.equal(settings.niriPage["look.ringColor"], undefined);

    const plain = service({ "niri.config.read": [{ result: { content: ring("#aabbcc"), hash: "h0" } }] });
    plain.s.Registry.sections = [look];
    plain.settings.niriPage = { "look.ringColor": "#aabbcc" };
    plain.s.themeColors = { secondary: "#778899" };
    plain.s.followTheme();
    assert.equal(plain.s.applyTimer.running, false);
});

test("the first theme change of a session compares with niri.kdl as read, not with an empty send", () => {
    for (const [onDisk, applies] of [[ring("#778899"), false], [ring("#112233"), true]]) {
        const { s, settings, requests } = service({ "niri.config.read": [{ result: { content: onDisk, hash: "h0" } }] });
        s.Registry.sections = [look];
        settings.niriPage = { "look.ringColor": "secondary" };
        s.themeColors = { secondary: "#778899", tertiary: "#445566" };
        s.followTheme();
        assert.deepEqual(requests.map(r => r.method), ["niri.config.read"]);
        assert.equal(s.applyTimer.running, applies, onDisk);
    }
});

test("a theme change writes nothing until the page holds a saved setting", () => {
    for (const page of [{}, { "custom.news-seen": "25.08" }]) {
        const { s, settings, requests } = service();
        settings.niriPage = page;
        s.followTheme();
        assert.deepEqual(requests, []);
        assert.equal(s.applyTimer.running, false);
    }
    const { s, settings, methods, fire } = service();
    settings.niriPage = { "t.width": 6 };
    s.followTheme();
    fire();
    assert.deepEqual(methods(), ["niri.config.read", "niri.config.apply"]);
});

test("a failed theme read leaves an apply in progress alone", () => {
    const { s, settings, events, warnings } = service({ "niri.config.read": [{ error: "socket closed" }] });
    const page = { "t.width": 6 };
    settings.niriPage = page;
    s._confirmed = {};
    s._busy = true;
    s._again = true;
    s.applyTimer.restart();
    s.followTheme();
    assert.equal(s._busy, true);
    assert.equal(s._again, true);
    assert.equal(s.applyTimer.running, true);
    assert.equal(settings.niriPage, page);
    assert.deepEqual(events, []);
    assert.equal(warnings.length, 1);
});

test("a theme change outside a niri session asks nothing", () => {
    const { s, requests } = service();
    s.CompositorService.isNiri = false;
    s.followTheme();
    assert.deepEqual(requests, []);
    assert.equal(s.applyTimer.running, false);
});
