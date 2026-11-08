.pragma library
.import "../DCommon/Common/fzf.js" as Fzf

const Tier = {
    exact: 10000,
    prefix: 5000,
    wordStart: 3000,
    substring: 500,
    fuzzy: 100,
    typo: 50
};

const minQuality = 0.6;

function tokenize(text) {
    return text.toLowerCase().trim().split(/[\s\-_]+/).filter(w => w.length > 0);
}

function prepareText(text) {
    const str = String(text || "");
    return {
        text: str,
        lower: str.toLowerCase(),
        words: tokenize(str),
        runes: null,
        bonus: null
    };
}

function fzfMatch(runes, pattern, withPos) {
    return Fzf.fuzzyMatchV2(false, true, true, runes, pattern, withPos, Fzf.slab);
}

function prepareQuery(query) {
    const lower = String(query || "").toLowerCase().trim();
    const fuzzyWords = lower.split(/\s+/).filter(w => w.length > 0).map(word => {
        const pattern = Fzf.strToRunes(word).map(r => Fzf.normalizeRune(r));
        return {
            pattern: pattern,
            self: fzfMatch(Fzf.strToRunes(word), pattern, false)[0].score
        };
    });
    return {
        lower: lower,
        words: tokenize(lower),
        fuzzyWords: fuzzyWords
    };
}

function startsWords(textWords, queryWords) {
    if (queryWords.length === 0)
        return false;
    for (let i = 0; i + queryWords.length <= textWords.length; i++) {
        if (queryWords.every((word, j) => textWords[i + j].startsWith(word)))
            return true;
    }
    return false;
}

function lexicalScore(item, query) {
    if (!query.lower)
        return 0;
    if (item.lower === query.lower)
        return Tier.exact;
    if (item.lower.startsWith(query.lower))
        return Tier.prefix;
    if (startsWords(item.words, query.words))
        return Tier.wordStart;
    if (item.lower.includes(query.lower))
        return Tier.substring;
    return 0;
}

function runesOf(item) {
    if (item.runes === null)
        item.runes = Fzf.strToRunes(item.text);
    return item.runes;
}

function bonusOf(item) {
    if (item.bonus !== null)
        return item.bonus;
    const runes = runesOf(item);
    const bonus = new Array(runes.length);
    let prev = 0;
    for (let i = 0; i < runes.length; i++) {
        const cls = Fzf.charClassOf(runes[i]);
        bonus[i] = Fzf.bonusFor(prev, cls);
        prev = cls;
    }
    item.bonus = bonus;
    return bonus;
}

// An alignment spread over several words where some run of matched characters starts mid-word
// ("ets2" in "Evolu[t]ion Data [S]erver OAuth[2]") is one nobody would recognize. Vicinae's rule.
function coherent(item, positions) {
    const pos = Array.from(positions).sort((a, b) => a - b);
    const bonus = bonusOf(item);
    let boundaryInside = false;
    for (let j = pos[0] + 1; j <= pos[pos.length - 1] && !boundaryInside; j++)
        boundaryInside = bonus[j] > 0;
    if (!boundaryInside)
        return true;
    for (let k = 0; k < pos.length; k++) {
        const runStart = k === 0 || pos[k - 1] !== pos[k] - 1;
        if (runStart && bonus[pos[k]] === 0)
            return false;
    }
    return true;
}

function fuzzyScore(item, query) {
    if (query.lower.length < 2)
        return 0;
    let sum = 0;
    for (const word of query.fuzzyWords) {
        const [match, positions] = fzfMatch(runesOf(item), word.pattern, true);
        if (match.start < 0 || !coherent(item, positions))
            return 0;
        const quality = match.score / word.self;
        if (quality < minQuality)
            return 0;
        sum += Math.min(1, quality);
    }
    return Math.round(Tier.fuzzy * sum / query.fuzzyWords.length);
}

function levenshtein(s1, s2) {
    let prev = new Array(s2.length + 1);
    let curr = new Array(s2.length + 1);
    for (let j = 0; j <= s2.length; j++)
        prev[j] = j;
    for (let i = 1; i <= s1.length; i++) {
        curr[0] = i;
        for (let j = 1; j <= s2.length; j++) {
            const cost = s1[i - 1] === s2[j - 1] ? 0 : 1;
            curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
        }
        [prev, curr] = [curr, prev];
    }
    return prev[s2.length];
}

function typoScore(item, query) {
    const q = query.lower;
    if (q.length < 3 || query.words.length !== 1)
        return 0;
    const candidates = [item.lower].concat(item.words);
    if (q.length >= 4) {
        for (const word of item.words) {
            if (word.length > q.length)
                candidates.push(word.slice(0, q.length));
        }
    }
    let best = 0;
    for (const candidate of candidates) {
        const len = Math.max(candidate.length, q.length);
        const maxEdits = Math.floor(len * (1 - minQuality) + 1e-9);
        if (Math.abs(candidate.length - q.length) > maxEdits)
            continue;
        const edits = levenshtein(candidate, q);
        if (edits > maxEdits)
            continue;
        best = Math.max(best, 1 - edits / len);
    }
    return Math.round(Tier.typo * best);
}

function textScore(item, query) {
    return lexicalScore(item, query) || fuzzyScore(item, query) || typoScore(item, query);
}
