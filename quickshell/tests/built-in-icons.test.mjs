import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const BuiltInIcons = loadScript(new URL("../Common/BuiltInIcons.js", import.meta.url));

test("every built-in launcher icon is drawn in the given tones", () => {
    const service = readFileSync(new URL("../Services/AppSearchService.qml", import.meta.url), "utf8");
    const names = Array.from(service.matchAll(/_builtInIcon\("(\w+)"\)/g), match => match[1]);
    assert.equal(names.length, 5);
    for (const name of names) {
        const url = BuiltInIcons.url(name, ["#eef4ff", "#9ecaff", "#004e84"]);
        assert.ok(url.startsWith("data:image/svg+xml;utf8,%3Csvg"));
        const svg = decodeURIComponent(url.slice(url.indexOf(",") + 1));
        assert.match(svg, /stop-color="#eef4ff".*stop-color="#9ecaff".*fill="#004e84"><path d="M/);
        assert.ok(svg.includes('fill="url(#b)"') && !svg.includes("undefined"), name);
    }
});

test("Dux Labs app icons take every tone, other icon names stay with the theme", () => {
    const tones = ["#eef4ff", "#9ecaff", "#004e84", "#3f8fd6", "#00396a"];
    for (const id of ["dev.duxlabs.calendar", "dev.duxlabs.files", "dev.duxlabs.edit"]) {
        const svg = decodeURIComponent(BuiltInIcons.duxAppUrl(id, tones).split(",")[1]);
        assert.ok(svg.includes('fill="url(#b)"') && svg.includes(`fill="${tones[2]}"`), id);
        assert.ok(!/\{\d\}|undefined/.test(svg), id);
    }
    assert.match(decodeURIComponent(BuiltInIcons.duxAppUrl("dev.duxlabs.calendar", tones)), /fill="#3f8fd6".*fill="#00396a"/);
    assert.equal(BuiltInIcons.duxAppUrl("dev.duxlabs.connect", tones), "");
});
