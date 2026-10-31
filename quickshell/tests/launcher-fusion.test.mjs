import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const scorer = loadScript(new URL("../Modals/DLauncherV2/Scorer.js", import.meta.url));

const action = (id, name, keywords = []) => ({ id, type: "action", name, keywords, subtitle: "Now: On" });
const app = (id, name, keywords = []) => ({ id, type: "app", name, keywords });
const hits = (...pairs) => pairs.map(([id, score]) => ({ id, score }));
const ids = result => Array.from(result.entries, entry => entry.item.id);

test("an entry only the model finds is listed, in the model's order", () => {
    const night = action("nightlight", "Night Light");
    const close = action("close", "Close window");
    const result = scorer.fuseCatalog([], [close, night], "gözlerim yoruldu", hits(["nightlight", 0.74], ["close", 0.71]), null);
    assert.deepEqual(ids(result), ["nightlight", "close"]);
});

test("a name the user typed is not overruled by a better semantic rank", () => {
    const terminal = app("terminal", "Terminal");
    const kitty = app("kitty", "Kitty", ["gpu terminal"]);
    const result = scorer.fuseCatalog([terminal, kitty], [kitty], "terminal", hits(["kitty", 0.75]), null);
    assert.deepEqual(ids(result), ["terminal", "kitty"]);
});

test("agreement of both rankings beats the top of one of them", () => {
    const a = app("a", "A", ["x"]);
    const b = app("b", "B", ["x"]);
    const c = app("c", "C");
    const result = scorer.fuseCatalog([a, b], [c, b], "x", hits(["c", 0.75], ["b", 0.72]), null);
    assert.deepEqual(ids(result), ["b", "a", "c"]);
});

test("usage settles a tie between otherwise equal entries", () => {
    const a = app("a", "A", ["x"]);
    const b = app("b", "B", ["x"]);
    const usage = item => ({ b: 3 })[item.id] || 0;
    const tied = scorer.fuseCatalog([a, b], [b, a], "x", hits(["b", 0.75], ["a", 0.74]), null);
    assert.deepEqual(ids(tied), ["a", "b"]);
    const withUsage = scorer.fuseCatalog([a, b], [b, a], "x", hits(["b", 0.75], ["a", 0.74]), usage);
    assert.deepEqual(ids(withUsage), ["b", "a"]);
});

test("fusion hands back copies so a cached item never keeps a fused score", () => {
    const cached = app("a", "A", ["x"]);
    const result = scorer.fuseCatalog([cached], [], "x", hits(["a", 0.75]), null);
    assert.equal(cached._preScored, undefined);
    assert.ok(result.entries[0].item._preScored > 0 && result.entries[0].item !== cached);
});

test("a hit that resolved to no item is neither ranked nor counted for the margin", () => {
    const dark = action("dark", "Dark mode");
    const result = scorer.fuseCatalog([], [dark], "karanlık", hits(["gone", 0.8], ["dark", 0.75]), null);
    assert.deepEqual(Array.from(result.hits, hit => hit.id), ["dark"]);
});

// Scores of the real model on the shell's own action catalog (see Fusion.semanticFloor).
function confident(query, ranking, lexicalItems, rival = 0) {
    const items = ranking.map(([id]) => action(id, id.toUpperCase() + " action"));
    const lexical = lexicalItems.map(id => items.find(item => item.id === id));
    return scorer.actionsConfident(scorer.fuseCatalog(lexical, items, query, hits(...ranking), null), rival);
}

test("semantic confidence: clear winners go first, near-ties and unrelated queries do not", () => {
    assert.equal(confident("karanlık", [["dark", 0.718], ["dnd", 0.676]], []), true);
    assert.equal(confident("bildirimleri sustur", [["dnd", 0.803], ["bt", 0.707]], []), true);
    assert.equal(confident("ekran görüntüsü al", [["shot", 0.784], ["rec", 0.762]], []), false, "margin 0.022 and no typed word");
    assert.equal(confident("hello world", [["lamp", 0.626], ["shot", 0.619]], []), false, "below the floor, nothing is listed");
    assert.equal(confident("pdf", [["shot", 0.651], ["bright", 0.641]], []), false);
});

test("a typed word backs a close call, a score under the floor never counts", () => {
    const rows = [["vol", 0.76], ["lock", 0.75]];
    const items = [action("vol", "Volume", ["sesli"]), action("lock", "Lock screen")];
    const supported = scorer.fuseCatalog([items[0]], items, "ses", hits(...rows), null);
    assert.equal(scorer.actionsConfident(supported, 0), true);
    assert.equal(scorer.actionsConfident(scorer.fuseCatalog([items[0]], items, "ses", hits(["vol", 0.69], ["lock", 0.5]), null), 0), false);
    assert.deepEqual(Array.from(scorer.fuseCatalog([], items, "x", hits(["vol", 0.69]), null).entries), [], "a hit under the floor is not even listed");
});

test("a typed action name goes first unless an app was typed more completely", () => {
    const dark = action("dark", "Dark mode");
    const fused = scorer.fuseCatalog([dark], [], "dark", [], null);
    assert.equal(scorer.actionsConfident(fused, 0), true, "no model needed");
    assert.equal(scorer.actionsConfident(fused, 10000), false, "an app named exactly dark");
});

test("a semantic winner stays below an application the user spelled out", () => {
    assert.equal(confident("terminal", [["term", 0.75], ["x", 0.6]], [], 5000), false);
});

test("the fused top must be the model's top", () => {
    const weak = action("weak", "Weak", ["qwerty"]);
    const best = action("best", "Best");
    const fused = scorer.fuseCatalog([weak], [best, weak], "q", hits(["best", 0.78], ["weak", 0.72]), null);
    assert.equal(fused.entries[0].item.id, "weak");
    assert.equal(scorer.actionsConfident(fused, 0), false);
});

test("without semantic hits the classic score of an action ignores its state text", () => {
    const item = action("a", "Wi-Fi");
    item.subtitle = "Now: On";
    assert.equal(scorer.textScore(item, "on"), 0);
    assert.ok(scorer.textScore(item, "wi") > 0);
});

test("rows that share an id are told apart by their own key", () => {
    const wifi = { id: "settings_nav:40:a", _key: "wifi", type: "setting", name: "Wi-Fi", keywords: [] };
    const saved = { id: "settings_nav:40:a", _key: "saved", type: "setting", name: "Saved networks", keywords: [] };
    const result = scorer.fuseCatalog([wifi, saved], [], "w", hits(), null);
    assert.deepEqual(Array.from(result.entries, entry => entry.id).sort(), ["saved", "wifi"]);
});

test("the lexical floor for actions keeps fuzzy keyword matches out but not a typed substring", () => {
    const fuzzy = scorer.textScore({ name: "Bluetooth", keywords: ["kulaklik"], type: "action" }, "karanlik");
    const substring = scorer.textScore({ name: "Wi-Fi", keywords: ["wireless network"], type: "action" }, "network");
    assert.ok(fuzzy > 0 && fuzzy < scorer.Fusion.minLexical);
    assert.ok(substring >= scorer.Fusion.minLexical);
});
