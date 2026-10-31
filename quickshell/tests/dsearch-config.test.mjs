import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const config = loadScript(new URL("../Services/DSearchConfig.js", import.meta.url));

// The head of the real ~/.config/dsearch/config.toml: a comment, top-level keys, array tables.
const real = '# DankSearch Configuration\nindex_path = "/home/u/.cache/danksearch/index"\nmax_depth = 0\n\n[[index_paths]]\n  path = "/home/u"\n  enabled = true\n';

test("a config without a semantic table gets one at the end and nothing else changes", () => {
    const { text } = config.setSemanticEnabled(real, true);
    assert.equal(text, real + "\n[semantic]\nenabled = true\n");
    assert.equal(config.readSemanticEnabled(text), true);
    assert.equal(config.readSemanticEnabled(real), false, "an enabled key of another table is not ours");
});

test("an existing key is switched in place, comments and neighbours survive", () => {
    const before = '[semantic]\n# on or off\nenabled = false # default\nthreads = 4\n\n[other]\nenabled = true\n';
    const { text } = config.setSemanticEnabled(before, true);
    assert.equal(text, '[semantic]\n# on or off\nenabled = true\nthreads = 4\n\n[other]\nenabled = true\n');
    assert.equal(config.setSemanticEnabled(text, false).text, before.replace(" # default", ""));
});

test("a semantic table without the key gets it right under the header", () => {
    const { text } = config.setSemanticEnabled("[semantic]\nthreads = 2\n", true);
    assert.equal(text, "[semantic]\nenabled = true\nthreads = 2\n");
    assert.equal(config.setSemanticEnabled("", true).text, "[semantic]\nenabled = true\n");
});

test("an inline semantic definition is refused instead of being duplicated", () => {
    assert.match(config.setSemanticEnabled("semantic = { enabled = false }\n", true).error, /inline/);
    assert.match(config.setSemanticEnabled("semantic.enabled = false\n", true).error, /inline/);
});

test("the config lives where dsearch looks for it", () => {
    assert.equal(config.configPath({ configHome: "/c", home: "/h" }), "/c/dsearch/config.toml");
    assert.equal(config.configPath({ home: "/h" }), "/h/.config/dsearch/config.toml");
});
