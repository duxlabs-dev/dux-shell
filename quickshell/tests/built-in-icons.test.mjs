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
