.pragma library
.import "../KeyUtils.js" as KeyUtils

var maxSettings = 8;
var maxBinds = 3;

// Filler words of a plain phrase: "more space" ranks on "space" alone.
var stopWords = new Set(["more", "less", "the", "a", "an", "of", "to", "my", "some", "bigger", "smaller", "big", "small", "change", "set", "how", "i", "want"]);

function fold(text) {
    return String(text || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[’']/g, " ");
}

// First word of each group is its canonical form.
var ALIAS_GROUPS = [
    ["delete", "del", "remove"],
    ["super", "mod", "win", "meta", "logo", "mod4"]
];
var ALIASES = {};
for (var groupIndex = 0; groupIndex < ALIAS_GROUPS.length; groupIndex++) {
    const group = ALIAS_GROUPS[groupIndex];
    for (var wordIndex = 0; wordIndex < group.length; wordIndex++)
        ALIASES[group[wordIndex]] = group;
}

function distance(a, b) {
    if (a === b)
        return 0;
    if (!a.length)
        return b.length;
    if (!b.length)
        return a.length;
    let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
    for (let i = 1; i <= a.length; i++) {
        const row = [i];
        for (let j = 1; j <= b.length; j++)
            row[j] = Math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        prev = row;
    }
    return prev[b.length];
}

// One or two typos per word, no library: short words only afford one edit.
// Typos are measured on each word's canonical alias form, so "supr" still
// hangs on "Mod" (canonical "super").
function wordsMatch(a, b) {
    if (a === b)
        return true;
    const group = ALIASES[a];
    if (group && group.includes(b))
        return true;
    const ca = group ? group[0] : a;
    const cb = ALIASES[b] ? ALIASES[b][0] : b;
    if (ca.length < 3 || cb.length < 3)
        return false;
    const cap = Math.min(ca.length, cb.length) <= 5 ? 1 : 2;
    return distance(ca, cb) <= cap;
}

function tokensOf(text) {
    return fold(text).split(/[^a-z0-9]+/).filter(word => word && !stopWords.has(word));
}

// Bind haystack: every key part plus the action and description words.
function bindTokens(group) {
    const tokens = [];
    for (const entry of group.keys || []) {
        for (const part of fold(entry.key).split("+")) {
            const trimmed = part.trim();
            if (trimmed)
                tokens.push(trimmed);
        }
    }
    return tokens.concat(tokensOf((group.action || "") + " " + (group.desc || "")));
}

function matchTokens(queryTokens, hayTokens) {
    return queryTokens.every(word => hayTokens.some(hay => wordsMatch(word, hay)));
}

function isCombo(query) {
    return /^\s*(super|mod|mod4|mod1|ctrl|control|alt|shift|win|meta|logo)\s*\+/i.test(query) || /[^+\s]\s*\+\s*[^+\s]/.test(query);
}

function bindsFor(combo, binds, modKey, modSymbol) {
    const want = KeyUtils.normalizeKeyCombo(combo.replace(/\s+/g, ""), modKey, modSymbol);
    return binds.filter(group => (group.keys || []).some(entry => KeyUtils.normalizeKeyCombo(entry.key, modKey, modSymbol) === want));
}

// KeybindsService.bindGroups keeps each conflicting key of one action in its own entry:
// merge them back per action so a result and its key count stay action-level.
// Copies: the flat binds belong to the service cache.
function perAction(groups) {
    const merged = [];
    const byAction = {};
    for (const group of groups) {
        const action = group.action || "";
        if (byAction[action]) {
            byAction[action].keys = byAction[action].keys.concat(group.keys || []);
        } else {
            byAction[action] = Object.assign({}, group, { keys: Array.from(group.keys || []) });
            merged.push(byAction[action]);
        }
    }
    return merged;
}

// Matches the English title and its translation, so every language finds its own words.
function score(entry, query, tokens, translate) {
    const titles = [fold(entry.title), fold(translate(entry.title))];
    if (titles.some(title => title.startsWith(query)))
        return 4;
    if (titles.some(title => title.includes(query)))
        return 3;
    const hay = titles.join(" ") + " " + fold((entry.words || []).join(" ")) + " " + fold(entry.key);
    return tokens.every(word => hay.includes(word)) ? 2 : 0;
}

// modules: the registry entries ({id, search}); options: {sections: allowed menu ids or null, binds: KeybindsService flat binds, modKey, modSymbol, translate: title translator}.
// Returns {kind: "setting", section, key, title} and {kind: "bind", combo, binds} results, best first.
function find(text, modules, options) {
    const raw = String(text || "").trim();
    const query = fold(raw).trim();
    if (!query)
        return [];
    const opts = options || {};
    const binds = opts.binds || [];
    const translate = opts.translate || (title => title);
    const results = [];
    const fuzzyTokens = tokensOf(raw);
    const combo = isCombo(raw);
    if (combo) {
        let hits = bindsFor(raw, binds, opts.modKey, opts.modSymbol);
        // Combos typed loose ("supr + space") fall back on the fuzzy tokens
        // only when the exact normalized combo found nothing.
        if (!hits.length && fuzzyTokens.length)
            hits = binds.filter(group => (group.keys || []).length && matchTokens(fuzzyTokens, bindTokens(group)));
        // A split action hides its other keys behind other entries: pull every entry of each hit action
        const hitActions = new Set(Array.from(hits, group => group.action || ""));
        const same = binds.filter(group => hitActions.has(group.action || ""));
        results.push({ kind: "bind", combo: raw, binds: perAction(same) });
    }

    const words = query.split(/\s+/).filter(word => word && !stopWords.has(word));
    const tokens = words.length ? words : [query];
    const scored = [];
    for (const module of modules || []) {
        if (opts.sections && !opts.sections.includes(module.id))
            continue;
        for (const entry of module.search || []) {
            const value = score(entry, query, tokens, translate);
            if (value)
                scored.push({ value: value, order: scored.length, result: { kind: "setting", section: module.id, key: entry.key, title: entry.title } });
        }
    }
    scored.sort((a, b) => b.value - a.value || a.order - b.order);
    for (const item of scored.slice(0, maxSettings))
        results.push(item.result);

    if (combo)
        return results;
    const named = perAction(binds.filter(group => (group.keys || []).length && (fold(group.desc).includes(query) || fold(group.action).includes(query) || (fuzzyTokens.length && matchTokens(fuzzyTokens, bindTokens(group))))));
    for (const group of named.slice(0, maxBinds))
        results.push({ kind: "bind", combo: group.keys[0].key, binds: [group] });
    return results;
}
