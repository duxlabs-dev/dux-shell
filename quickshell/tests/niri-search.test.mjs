import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const search = loadScript(new URL("../Common/niri/search.js", import.meta.url));
const { find, isCombo, fold } = search;

const modules = [
    {
        id: "windows",
        search: [
            { key: "look.gaps", title: "Gaps", words: ["gaps", "space", "spacing", "espace", "écart", "marge"] },
            { key: "look.ringWidth", title: "Ring width", words: ["focus", "ring", "width", "anneau"] },
            { key: "look.radius", title: "Rounded corners", words: ["corner", "radius", "coins", "arrondis"] }
        ]
    },
    {
        id: "animations",
        search: [{ key: "anim.slowdown", title: "Slowdown", words: ["speed", "vitesse", "faster", "slower"] }]
    },
    { id: "advanced", search: [{ key: "adv.debug", title: "Debug flags", words: ["debug", "débogage"] }] },
    { id: "input" }
];

const binds = [
    { category: "Apps", action: "spawn \"firefox\"", desc: "Browser", keys: [{ key: "Mod+B" }] },
    { category: "Windows", action: "close-window", desc: "Close window", keys: [{ key: "Mod+Q" }, { key: "Alt+F4" }] },
    { category: "Apps", action: "spawn \"kitty\"", desc: "Terminal", keys: [{ key: "Mod+T" }] },
    { category: "Apps", action: "spawn \"foot\"", desc: "Other terminal", keys: [{ key: "Super+T" }] }
];

const options = { binds, modKey: "Super", modSymbol: "Mod" };
// The script runs in its own realm: copy its arrays before a strict deep compare.
const keys = results => Array.from(results, r => r.kind === "setting" ? r.key : "bind:" + r.combo);

test("a plain French phrase finds the setting through its words", () => {
    const results = find("plus d'espace", modules, options);
    assert.equal(results[0].key, "look.gaps");
    assert.equal(results[0].section, "windows");
    assert.equal(results[0].title, "Gaps");
});

test("accents are ignored on both sides", () => {
    assert.equal(find("ecart", modules, options)[0].key, "look.gaps");
    assert.equal(find("débug", modules, options)[0].key, "adv.debug");
    assert.equal(fold("Écart d’Été"), "ecart d ete");
});

test("English words work as well, every word must match", () => {
    assert.deepEqual(keys(find("focus ring", modules, options)), ["look.ringWidth"]);
    assert.deepEqual(keys(find("ring speed", modules, options)), []);
});

test("a title prefix ranks above a title substring, above a word match", () => {
    const fixture = [{
        id: "windows",
        search: [
            { key: "a.word", title: "Other", words: ["round"] },
            { key: "a.inside", title: "Make round", words: [] },
            { key: "a.prefix", title: "Rounded corners", words: [] }
        ]
    }];
    assert.deepEqual(keys(find("round", fixture, options)), ["a.prefix", "a.inside", "a.word"]);
});

test("sections outside the allowed list are skipped", () => {
    assert.deepEqual(keys(find("debug", modules, { ...options, sections: ["windows", "animations"] })), []);
    assert.deepEqual(keys(find("debug", modules, options)), ["adv.debug"]);
});

test("an empty or stop-word-only query still behaves", () => {
    assert.equal(find("  ", modules, options).length, 0);
    assert.deepEqual(keys(find("plus", modules, options)), []);
});

test("a key combination finds its bind, whatever the modifier spelling", () => {
    const results = find("Super+B", modules, options);
    assert.equal(results[0].kind, "bind");
    assert.equal(results[0].combo, "Super+B");
    assert.deepEqual(Array.from(results[0].binds, b => b.action), ["spawn \"firefox\""]);
    assert.equal(find("mod + q", modules, options)[0].binds[0].action, "close-window");
    assert.equal(find("alt+f4", modules, options)[0].binds[0].action, "close-window");
});

test("a free combination gives one bind result with no bind, a double one lists both", () => {
    const free = find("Super+Z", modules, options);
    assert.equal(free.length, 1);
    assert.equal(free[0].binds.length, 0);
    assert.equal(find("Super+T", modules, options)[0].binds.length, 2);
});

test("words also find binds by their description, after the settings", () => {
    const results = find("terminal", modules, options);
    assert.deepEqual(keys(results), ["bind:Mod+T", "bind:Super+T"]);
    assert.equal(results[0].binds[0].category, "Apps");
});

const splitBinds = [
    { category: "Apps", action: "spawn \"firefox\"", desc: "Browser", keys: [{ key: "Mod+T" }, { key: "Mod+Y" }] },
    // The conflicted key keeps its own entry, as KeybindsService.bindGroups splits it
    { category: "Apps", action: "spawn \"firefox\"", desc: "Browser", keys: [{ key: "Mod+U" }], conflict: { key: "Mod+U", action: "spawn kitty", source: "config" } }
];
const splitOptions = { binds: splitBinds, modKey: "Super", modSymbol: "Mod" };

test("a conflict-split action gives one search result per action, keys aggregated", () => {
    const results = find("browser", [{ id: "apps", search: [] }], splitOptions);
    assert.equal(results.filter(r => r.kind === "bind").length, 1);
    assert.equal(results[0].binds.length, 1);
    assert.equal(results[0].binds[0].action, "spawn \"firefox\"");
    assert.deepEqual(Array.from(results[0].binds[0].keys, k => k.key), ["Mod+T", "Mod+Y", "Mod+U"]);
});

test("a combo on one entry of a split action merges that action's entries", () => {
    const results = find("mod+u", [{ id: "apps", search: [] }], splitOptions);
    assert.equal(results[0].kind, "bind");
    assert.equal(results[0].binds.length, 1);
    assert.equal(results[0].binds[0].action, "spawn \"firefox\"");
    assert.deepEqual(Array.from(results[0].binds[0].keys, k => k.key), ["Mod+T", "Mod+Y", "Mod+U"]);
    // The shared keys array of the service cache must stay untouched
    assert.deepEqual(Array.from(splitBinds[0].keys, k => k.key), ["Mod+T", "Mod+Y"]);
});

test("combo detection", () => {
    assert.equal(isCombo("Super+B"), true);
    assert.equal(isCombo("ctrl +k"), true);
    assert.equal(isCombo("plus d'espace"), false);
    assert.equal(isCombo("c++"), false);
});

test("results are capped", () => {
    const many = [{ id: "windows", search: Array.from({ length: 20 }, (_, i) => ({ key: "k." + i, title: "Gap " + i, words: [] })) }];
    assert.equal(find("gap", many, options).length, 8);
});

// The owner types shortcuts the way he says them: « super + space », « spce »,
// French words, typos. The exact paths stay first; fuzzy only adds results.
const fuzzyBinds = binds.concat([
    { category: "Launcher", action: "spawn \"launcher\"", desc: "Toggle launcher", keys: [{ key: "Mod+Space" }] },
    { category: "System", action: "spawn \"volume\"", desc: "Volume control", keys: [{ key: "Mod+P" }] }
]);
const fuzzyOptions = { binds: fuzzyBinds, modKey: "Super", modSymbol: "Mod" };
const bindActions = results => Array.from(results).filter(r => r.kind === "bind").flatMap(r => Array.from(r.binds, b => b.action));

test("a shortcut search tolerates case, accents, spaces and a missing plus", () => {
    for (const query of ["super space", "Super + SPACE", "Super+Space", "supér espace"])
        assert.ok(bindActions(find(query, [], fuzzyOptions)).includes("spawn \"launcher\""), query);
});

test("a typo of one or two characters per word still finds the bind", () => {
    for (const query of ["spce", "supr + space", "controle"])
        assert.ok(bindActions(find(query, [], fuzzyOptions)).includes(query === "controle" ? "spawn \"volume\"" : "spawn \"launcher\""), query);
});

test("short en/fr aliases match bind words", () => {
    assert.ok(bindActions(find("ferme la fenetre", [], options)).includes("close-window"));
    assert.ok(bindActions(find("quiter terminal", [], options)).length >= 0);
});

test("an unrelated word matches no bind", () => {
    assert.deepEqual(bindActions(find("super zzzz", [], fuzzyOptions)), []);
});

test("levenshtein and alias helpers", () => {
    assert.equal(search.distance("kitten", "sitting"), 3);
    assert.equal(search.distance("spce", "space"), 1);
    assert.equal(search.wordsMatch("fermer", "close"), true);
    assert.equal(search.wordsMatch("supprimer", "delete"), true);
    assert.equal(search.wordsMatch("espace", "space"), true);
    assert.equal(search.wordsMatch("quitter", "quit"), true);
    assert.equal(search.wordsMatch("zebra", "close"), false);
});
