import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const health = loadScript(new URL("../Common/niri/health.js", import.meta.url));

test("a dormant DMS fragment is the finding the page acts on by itself", () => {
    const findings = [
        { kind: "unused-rule", subject: "x", files: ["dms/windowrules.kdl"], fix: undefined },
        { kind: "not-included", subject: "dms/input.kdl", files: ["dms/input.kdl"], fix: "add-include" }
    ];
    assert.equal(health.dormant(findings)?.subject, "dms/input.kdl");
});

test("findings without the include fix leave nothing to act on", () => {
    assert.equal(health.dormant([{ kind: "override", subject: "Mod+T", fix: undefined }]), null);
    assert.equal(health.dormant([{ kind: "not-included", subject: "dms/input.kdl", fix: "other" }]), null);
    assert.equal(health.dormant([]), null);
    assert.equal(health.dormant(undefined), null);
});

test("a subject outside the dms fragments is never acted on", () => {
    assert.equal(health.dormant([{ kind: "not-included", subject: "elsewhere.kdl", fix: "add-include" }]), null);
});

test("the IPC fragment parameter is the subject without its dms folder", () => {
    assert.equal(health.fragmentOf("dms/input.kdl"), "input.kdl");
    assert.equal(health.fragmentOf("dms/cursor.kdl"), "cursor.kdl");
});
