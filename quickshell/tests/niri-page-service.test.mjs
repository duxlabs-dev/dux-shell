import assert from "node:assert/strict";
import test from "node:test";
import { include, section, service } from "./niri-page-fake.mjs";

test("three quick sets give one apply, nothing is sent before the timer fires", () => {
    const { s, requests, fire } = service();
    s.set("t.width", 1);
    s.set("t.width", 2);
    s.set("t.width", 3);
    assert.equal(requests.length, 0);
    fire();
    const applies = requests.filter(r => r.method === "niri.config.apply");
    assert.equal(applies.length, 1);
    assert.deepEqual(JSON.parse(JSON.stringify(applies[0].params)),
        { fragment: "niri.kdl", content: "layout {\n    width 3\n}\n" + include, baseHash: "h0", extra: { "niri-custom.kdl": "" } });
    assert.equal(s.get("t.width"), 3);
});

test("a key with no KDL is confirmed at once, without an apply, once niri.kdl is known", () => {
    const { s, fire, methods } = service({ "niri.config.apply": [undefined, { error: "invalid: bad width" }] });
    s.Registry.sections = [{ id: "t", defaults: { "t.width": 4, "t.local": true }, stored: { "t.width": "page", "t.local": "page" },
        toKdl: state => [{ block: "layout", lines: ["width " + state["t.width"]] }] }];
    s.set("t.local", false);
    fire();
    assert.deepEqual(methods(), ["niri.config.read", "niri.config.apply"], "niri.kdl unknown: applied as before");
    s.set("t.local", true);
    assert.equal(s.applyTimer.running, false, "same niri.kdl: nothing to apply");
    s.set("t.width", 5);
    s.set("t.local", false);
    assert.equal(s.applyTimer.restarts, 3, "an apply pending takes the local key with it");
    fire();
    assert.equal(s.get("t.width"), 4, "refused: the width goes back");
    assert.equal(s.get("t.local"), true, "the local key confirmed without an apply stays");
    s.setCustom("t", "x");
    assert.equal(s.applyTimer.running, true, "custom text is a fragment of its own");
});

test("a changed fragment is read again and retried once", () => {
    const { s, events, fire, requests, methods } = service({
        "niri.config.read": [{ result: { hash: "h0" } }, { result: { hash: "h9" } }],
        "niri.config.apply": [{ error: "changed" }]
    });
    s.set("t.width", 6);
    fire();
    assert.deepEqual(methods(), ["niri.config.read", "niri.config.apply", "niri.config.read", "niri.config.apply"]);
    assert.equal(requests[3].params.baseHash, "h9");
    assert.deepEqual(events, [["applied", 1]]);

    const twice = service({ "niri.config.apply": [{ error: "changed" }, { error: "changed" }] });
    twice.s.set("t.width", 6);
    twice.fire();
    assert.equal(twice.requests.filter(r => r.method === "niri.config.apply").length, 2);
    assert.deepEqual(twice.events, [["refused", "changed"]]);
    assert.equal(twice.s.get("t.width"), 4);
});

test("an invalid config puts the last accepted state back and exposes niri's message", () => {
    const { s, events, fire } = service({ "niri.config.apply": [{ result: { version: 1, hash: "h1" } }, { error: "invalid: width must be positive" }] });
    s.set("t.width", 6);
    fire();
    s.set("t.width", -1);
    s.set("t.width", -2);
    fire();
    assert.equal(s.get("t.width"), 6);
    assert.equal(s._lastError, "width must be positive");
    assert.deepEqual(events, [["applied", 1], ["refused", "width must be positive"]]);
    assert.equal(s._busy, false);
});

test("a refusal keeps niri's first useful reason, never the quoted config", () => {
    // What niri validate prints for a config with two errors.
    const output = "Error:   × error loading config\n  ├─▶ error parsing\n  ╰─▶ error parsing KDL\n\n"
        + "Error:   × Unsupported value, only numbers are recognized\n   ╭─[niri.kdl:1:1]\n 1 │ layout {\n 2 │     gaps \"secret\"\n"
        + "   ·          ──┬─\n   ·            ╰── unsupported value\n   ╰────\n"
        + "Error:   × unexpected node `widht`\n   ╭─[niri.kdl:3:1]\n 4 │         widht 4\n   ╰────\n";
    const cases = [
        [output, "Unsupported value, only numbers are recognized"],
        ["Error:   × error loading config\n  ╰─▶ cannot read niri-custom.kdl\n", "cannot read niri-custom.kdl"],
        ["error: bad\n", "error: bad"],
        ["Error: bad", "bad"]
    ];
    for (const [niri, want] of cases) {
        const { s, warnings, events, fire } = service({ "niri.config.apply": [{ error: "invalid: " + niri }] });
        s.set("t.width", 6);
        fire();
        assert.equal(s._lastError, want);
        assert.deepEqual(events, [["refused", want]]);
        assert.deepEqual(warnings, ["niri config refused: " + want]);
    }
    const plain = service({ "niri.config.apply": [{ error: "reload failed" }] });
    plain.s.set("t.width", 6);
    plain.fire();
    assert.equal(plain.s._lastError, "reload failed");
});

test("undo applies the previous page with its custom text", () => {
    const { s, requests, fire } = service({ "niri.config.history": [{ result: [{ n: 2 }, { n: 1 }] }] });
    s.set("t.width", 6);
    s.setCustom("t", "extra 1");
    fire();
    s.undo();
    assert.equal(requests.some(r => r.method === "niri.config.restore"), false);
    const applies = requests.filter(r => r.method === "niri.config.apply");
    assert.equal(applies.length, 2);
    assert.equal(applies[1].params.content, "layout {\n    width 4\n}\n" + include);
    assert.equal(applies[1].params.extra["niri-custom.kdl"], "");
    assert.equal(s.get("t.width"), 4);
});

test("undo and restore report instead of doing nothing", () => {
    const { s, events, requests } = service();
    s.undo();
    s._busy = true;
    s.restore(1, null);
    assert.equal(requests.length, 0);
    assert.deepEqual(events, [["refused", "Nothing to undo"], ["refused", "Please wait..."]]);
    assert.equal(s._lastError, "Please wait...");
});

test("SettingsData keys stay out of niri.kdl, custom text comes last", () => {
    const { s, settings, requests, fire } = service();
    settings.niriPage = { "t.gaps": 3 };
    s.set("t.gaps", 12);
    assert.equal(settings.niriLayoutGapsOverride, 12);
    assert.equal(s.applyTimer.restarts, 0);
    s.set("t.width", 5);
    s.setCustom("t", "extra 1");
    fire();
    const params = requests.find(r => r.method === "niri.config.apply").params;
    assert.equal(params.content, "layout {\n    width 5\n}\n" + include);
    assert.equal(params.extra["niri-custom.kdl"], "extra 1\n");
    assert.equal(s.sectionKdl("t"), "layout {\n    width 5\n}\n");
});

test("sectionKdl gathers every module registered under the section id", () => {
    const { s, settings } = service();
    const other = { id: "t", defaults: { "u.on": false }, stored: {}, toKdl: state => [{ block: null, lines: state["u.on"] ? ["prefer-no-csd"] : [] }] };
    s.Registry.sections = [section, other];
    settings.niriPage = { "t.width": 5, "u.on": true };
    assert.equal(s.sectionKdl("t"), "prefer-no-csd\nlayout {\n    width 5\n    on true\n}\n");
});

test("a key NiriService already writes goes through its setter, never niri.kdl", () => {
    const { s, settings } = service();
    const calls = [];
    s.NiriService = { layoutXrayEnabled: true, setLayoutXray(v) { calls.push(v); this.layoutXrayEnabled = v; } };
    s.Registry.sections = [{ id: "t", defaults: { "t.xray": true }, stored: { "t.xray": "NiriService:layoutXrayEnabled:setLayoutXray" }, toKdl: () => [] }];
    assert.equal(s.get("t.xray"), true);
    assert.equal(s.isModified("t.xray"), false);
    s.set("t.xray", false);
    assert.deepEqual(calls, [false]);
    assert.equal(s.get("t.xray"), false);
    assert.equal(s.isModified("t.xray"), true);
    assert.deepEqual(settings.niriPage, {});
    assert.equal(s.applyTimer.restarts, 0);
    s.reset("t.xray");
    assert.deepEqual(calls, [false, true]);
    assert.equal("t.xray" in s.Page.pageState(s.Registry.sections, { "t.xray": false }), false);
});

test("a key SessionData already writes goes through it, never niri.kdl", () => {
    const { s, settings } = service();
    const calls = [];
    const seen = () => JSON.stringify(calls);
    s.SessionData = {
        showConfigReloadToast: true,
        set(key, value) {
            calls.push([key, value]);
            this[key] = value;
        },
        resetToDefault(keys) {
            calls.push(keys);
            this.showConfigReloadToast = true;
        }
    };
    s.SessionSpec = { SPEC: { showConfigReloadToast: { def: true } } };
    s.Registry.sections = [{ id: "t", defaults: {}, stored: { "t.toast": "SessionData:showConfigReloadToast" }, toKdl: () => [] }];
    assert.equal(s.get("t.toast"), true);
    assert.equal(s.isModified("t.toast"), false);
    s.set("t.toast", false);
    assert.equal(seen(), JSON.stringify([["showConfigReloadToast", false]]));
    assert.equal(s.get("t.toast"), false);
    assert.equal(s.isModified("t.toast"), true);
    assert.deepEqual(settings.niriPage, {});
    assert.equal(s.applyTimer.restarts, 0);
    s.reset("t.toast");
    assert.equal(seen(), JSON.stringify([["showConfigReloadToast", false], ["showConfigReloadToast"]]));
    assert.equal(s.get("t.toast"), true);
});

test("get reads the computed state, it does not rebuild it for every row", () => {
    const { s, settings } = service();
    settings.niriPage = { "t.width": 7 };
    s.builds = 0;
    for (let row = 0; row < 12; row++)
        assert.equal(s.get("t.width"), 7);
    assert.ok(s.builds <= 1, s.builds + " rebuilds");
});
