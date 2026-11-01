import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const vendor = loadScript(new URL("../Common/niri/vendor.js", import.meta.url));

test("vendorKind matches Framework sys_vendor strings", () => {
    for (const text of ["Framework", "Framework\n", "Framework Computer Inc", "  framework computer inc\n"])
        assert.equal(vendor.vendorKind(text), "framework", JSON.stringify(text));
});

test("vendorKind falls back to other", () => {
    for (const text of ["LENOVO", "HP", "", "\n", null, undefined, "Frame"])
        assert.equal(vendor.vendorKind(text), "other", JSON.stringify(text));
});

test("logoFor gives a distinct asset per kind", () => {
    assert.match(vendor.logoFor("framework"), /niri-page\/framework\.svg$/);
    assert.match(vendor.logoFor("other"), /niri-page\/microslop\.svg$/);
});
