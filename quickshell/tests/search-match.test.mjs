import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const search = loadScript(new URL("../Common/SearchMatch.js", import.meta.url));
const fzf = search.Fzf;

function unfilteredFuzzyScore(item, query) {
    if (query.lower.length < 2)
        return 0;
    let sum = 0;
    for (const word of query.fuzzyWords) {
        const [match, positions] = fzf.fuzzyMatchV2(false, true, true, search.runesOf(item), word.pattern, true, fzf.slab);
        if (match.start < 0 || !search.coherent(item, positions))
            return 0;
        const quality = match.score / word.self;
        if (quality < 0.6)
            return 0;
        sum += Math.min(1, quality);
    }
    return Math.round(100 * sum / query.fuzzyWords.length);
}

function levenshtein(a, b) {
    const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
    for (let j = 1; j <= b.length; j++)
        d[0][j] = j;
    for (let i = 1; i <= a.length; i++) {
        for (let j = 1; j <= b.length; j++)
            d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    return d[a.length][b.length];
}

function unboundedTypoScore(item, query) {
    const q = query.lower;
    if (q.length < 3 || query.words.length !== 1)
        return 0;
    const candidates = [item.lower, ...item.words];
    if (q.length >= 4)
        candidates.push(...item.words.filter(word => word.length > q.length).map(word => word.slice(0, q.length)));
    let best = 0;
    for (const candidate of candidates) {
        const len = Math.max(candidate.length, q.length);
        const edits = levenshtein(candidate, q);
        if (edits <= Math.floor(len * 0.4 + 1e-9))
            best = Math.max(best, 1 - edits / len);
    }
    return Math.round(50 * best);
}

test("fuzzy shortcuts preserve fzf scores across boundaries, repeated letters and word orders", () => {
    const names = ["Config Editor", "config.ini", "Git Browser", "alphaBeta", "abc xyz", "x f g", "ba-ab", "a_b_a", "aXbYc", "zebra crossing zone zz", "Éditeur", "myÉditeurTool", "İstanbul", "Öab", "ßab", "𝒜ab", "áb"];
    const queries = ["gi", "et", "ac", "ax", "fg", "aa", "aba", "ab", "ba", "a b", "b a", "a x", "x a", "x b", "c z", "zz", "zc", "a_b", "a-b", "ed", "é b", "ib", "oa", "sa", "𝒜b"];
    for (const name of names) {
        const item = search.prepareText(name);
        for (const text of queries) {
            const query = search.prepareQuery(text);
            // fzf's backtracking reads cells left by earlier calls; compare from the same slab state.
            fzf.slab.i16.fill(0);
            const expected = unfilteredFuzzyScore(item, query);
            fzf.slab.i16.fill(0);
            assert.equal(search.fuzzyScore(item, query), expected, `${name}: ${text}`);
        }
    }
});

test("typo bounds never drop a candidate within the edit budget", () => {
    const names = ["firefox", "Fire Fox", "git status", "gti", "tig", "abcdef", "abcdefghij", "bacd efgh", "network manager"];
    const queries = ["firfox", "fierfox", "frefox", "git", "gti", "tgi", "stauts", "abcd", "bacd", "abdcef", "fedcba", "netwrk", "managre", "gtx", "firefax", "xyz"];
    for (const name of names) {
        const item = search.prepareText(name);
        for (const text of queries) {
            const query = search.prepareQuery(text);
            assert.equal(search.typoScore(item, query), unboundedTypoScore(item, query), `${name}: ${text}`);
        }
    }
});

test("ASCII prefilters use normalized patterns and leave non-ASCII case folding to fzf", () => {
    for (const [name, query, expected] of [["Éditeur", "ed", 100], ["myÉditeurTool", "ed", 95], ["İstanbul", "ib", 75], ["abc xyz", "áx", 91], ["alphaBeta", "a b", 97], ["alphaBeta", "b a", 97], ["config.ini", "gi", 0]])
        assert.equal(search.textScore(search.prepareText(name), search.prepareQuery(query)), expected, `${name}: ${query}`);
});
