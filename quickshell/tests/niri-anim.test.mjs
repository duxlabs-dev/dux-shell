import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const Anim = loadScript(new URL("../Common/niri/anim.js", import.meta.url));

const spring = (damping, stiffness, epsilon) => Object.assign({}, Anim.niri["window-movement"], { kind: "spring", damping, stiffness, epsilon });

test("lists the 11 niri animations with niri's own defaults", () => {
    assert.equal(Anim.names.length, 11);
    assert.deepEqual([...Anim.names.filter(n => Anim.niri[n].kind === "curve")], ["window-open", "window-close", "screenshot-ui-open"]);
    assert.equal(Anim.niri["exit-confirmation-open-close"].damping, 0.6);
    assert.equal(Anim.niri["exit-confirmation-open-close"].stiffness, 500);
    assert.equal(Anim.niri["window-open"].curve, "ease-out-expo");
});

test("a critically damped spring never overshoots and settles at 1", () => {
    const s = Anim.samples(spring(1, 800, 0.0001));
    assert.equal(s[0], 0);
    assert.ok(Math.max(...s) <= 1);
    assert.ok(Math.abs(s[s.length - 1] - 1) < 0.001);
});

test("a spring below damping 1 bounces past the target", () => {
    assert.ok(Math.max(...Anim.samples(spring(0.4, 800, 0.0001))) > 1.1);
});

test("a stiffer spring settles sooner, a lower epsilon later", () => {
    const soft = Anim.samples(spring(1, 400, 0.0001)).length;
    assert.ok(Anim.samples(spring(1, 1600, 0.0001)).length < soft);
    assert.ok(Anim.samples(spring(1, 400, 0.01)).length < soft);
});

test("an overdamped spring stays under 1 and still ends", () => {
    const s = Anim.samples(spring(3, 800, 0.001));
    assert.ok(Math.max(...s) <= 1);
    assert.ok(s.length < Anim.maxMs);
});

test("a curve lasts its duration, one sample per ms, ends at 1", () => {
    const s = Anim.samples(Anim.niri["window-open"]);
    assert.equal(s.length, 151);
    assert.equal(s[0], 0);
    assert.equal(s[150], 1);
    const lin = Anim.samples(Object.assign({}, Anim.niri["window-open"], { curve: "linear", ms: 100 }));
    assert.equal(lin[50], 0.5);
    assert.ok(Anim.samples(Anim.niri["window-close"])[75] > 0.5);
});

test("kdl lines: a spring keeps decimals niri parses as floats, a curve quotes its name", () => {
    assert.deepEqual([...Anim.kdlLines(spring(1, 800, 0.0001))], ["spring damping-ratio=1.0 stiffness=800 epsilon=0.0001"]);
    assert.deepEqual([...Anim.kdlLines(spring(0.55, 600, 0.01))], ["spring damping-ratio=0.55 stiffness=600 epsilon=0.01"]);
    assert.deepEqual([...Anim.kdlLines(Anim.niri["window-close"])],["duration-ms 150", "curve \"ease-out-quad\""]);
});

test("changed looks only at the kind in use", () => {
    const def = Anim.niri["window-open"];
    assert.equal(Anim.changed(def, def), false);
    assert.equal(Anim.changed(Object.assign({}, def, { stiffness: 1400 }), def), false);
    assert.equal(Anim.changed(Object.assign({}, def, { ms: 300 }), def), true);
    assert.equal(Anim.changed(Object.assign({}, def, { kind: "spring" }), def), true);
});

test("presets and the style they make", () => {
    const of = style => name => Anim.preset(style, name);
    assert.equal(Anim.styleOf(of("default")), "default");
    assert.equal(Anim.styleOf(of("snappy")), "snappy");
    assert.equal(Anim.styleOf(of("bouncy")), "bouncy");
    assert.equal(Anim.preset("snappy", "window-open").ms, 100);
    assert.equal(Anim.preset("bouncy", "workspace-switch").damping, 0.55);
    assert.equal(Anim.styleOf(name => name === "window-open" ? Object.assign({}, Anim.niri[name], { ms: 400 }) : Anim.niri[name]), "");
});
