import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { loadScript } from "./qml-script.mjs";

const format = loadScript(new URL("../Common/Format.js", import.meta.url));

// QML's JS engine provides QString-style String.prototype.arg(); the plain vm
// realm does not. Install a minimal equivalent (replace the lowest-numbered
// %n per call) so format helpers behave as they do in the shell.
vm.runInContext("String.prototype.arg = function() { let out = this.toString(); for (let i = 0; i < arguments.length; i++) out = out.replace(/%(\\d+)/, String(arguments[i])); return out; }", format);

const HOUR_MS = 60 * 60 * 1000;

test("formatRemaining returns zeroText at or below zero", () => {
    assert.equal(format.formatRemaining(-5, "Off", "%1 min", "%1 h", "%1 h %2 m"), "Off");
});

test("formatRemaining formats minutes below an hour, rounding up", () => {
    assert.equal(format.formatRemaining(30 * 1000, "", "%1 min", "%1 h", "%1 h %2 m"), "1 min");
});

test("formatRemaining formats whole hours without minutes", () => {
    assert.equal(format.formatRemaining(2 * HOUR_MS, "", "%1 min", "%1 h", "%1 h %2 m"), "2 h");
});

test("formatRemaining rounds 59m59s up to one hour, not 60 min", () => {
    assert.equal(format.formatRemaining(59 * 60 * 1000 + 59000, "", "%1 min", "%1 h", "%1 h %2 m"), "1 h");
});

test("formatRemaining formats hours and minutes together", () => {
    assert.equal(format.formatRemaining(2 * HOUR_MS + 5 * 60 * 1000, "", "%1 min", "%1 h", "%1 h %2 m"), "2 h 5 m");
});
