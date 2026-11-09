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
        ascii: !/[^\x00-\x7f]/.test(str),
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
            text: Fzf.runesToStr(pattern),
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

function isSubsequence(text, pattern) {
    let from = 0;
    for (let i = 0; i < pattern.length; i++) {
        const at = text.indexOf(pattern[i], from);
        if (at < 0)
            return false;
        from = at + 1;
    }
    return true;
}

// A coherent alignment stays between boundaries or starts its first run at one.
function mayBeCoherent(item, pattern) {
    const bonus = bonusOf(item);
    let withinWord = 0;
    let fromBoundary = 0;
    for (let i = 0; i < item.lower.length; i++) {
        const boundary = bonus[i] > 0;
        if (boundary)
            withinWord = 0;
        if (item.lower[i] === pattern[withinWord] && ++withinWord === pattern.length)
            return true;
        if ((fromBoundary > 0 || boundary) && item.lower[i] === pattern[fromBoundary] && ++fromBoundary === pattern.length)
            return true;
    }
    return false;
}

// fzf scores a single character by its best-placed occurrence: 16 + 2 * bonus.
function singleCharQuality(item, word) {
    const bonus = bonusOf(item);
    let best = -1;
    for (let i = item.lower.indexOf(word.text); i >= 0; i = item.lower.indexOf(word.text, i + 1))
        best = Math.max(best, bonus[i]);
    return best < 0 ? 0 : (16 + 2 * best) / word.self;
}

// fzf ignores everything after the last occurrence of the final pattern character, except when
// the full input is too large for its slab and it falls back to the V1 algorithm.
function matchRunes(item, word) {
    const runes = runesOf(item);
    if (!item.ascii || runes.length * word.pattern.length > Fzf.slab.i16.length)
        return runes;
    const end = item.lower.lastIndexOf(word.text[word.text.length - 1]) + 1;
    return end === runes.length ? runes : runes.slice(0, end);
}

function wordQuality(item, word) {
    if (item.ascii && word.text.length === 1)
        return singleCharQuality(item, word);
    const [match, positions] = fzfMatch(matchRunes(item, word), word.pattern, true);
    if (match.start < 0)
        return 0;
    const quality = match.score / word.self;
    return quality < minQuality || !coherent(item, positions) ? 0 : quality;
}

function fuzzyScore(item, query) {
    if (query.lower.length < 2)
        return 0;
    // Non-ASCII input must keep fzf's rune-specific case folding and normalization.
    if (item.ascii && query.fuzzyWords.some(word => !isSubsequence(item.lower, word.text) || !mayBeCoherent(item, word.text)))
        return 0;
    let sum = 0;
    for (const word of query.fuzzyWords) {
        const quality = wordQuality(item, word);
        if (quality < minQuality)
            return 0;
        sum += Math.min(1, quality);
    }
    return Math.round(Tier.fuzzy * sum / query.fuzzyWords.length);
}

// Distances above limit are reported as limit + 1; row minimums never decrease.
function boundedLevenshtein(s1, s2, limit, prev, curr) {
    for (let j = 0; j <= s2.length; j++)
        prev[j] = j;
    for (let i = 1; i <= s1.length; i++) {
        curr[0] = i;
        let rowMin = i;
        for (let j = 1; j <= s2.length; j++) {
            const cost = s1[i - 1] === s2[j - 1] ? 0 : 1;
            curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
            rowMin = Math.min(rowMin, curr[j]);
        }
        if (rowMin > limit)
            return limit + 1;
        [prev, curr] = [curr, prev];
    }
    return prev[s2.length];
}

// Characters absent from the other string each cost at least one edit.
function exceedsEdits(candidate, q, maxEdits) {
    let missing = 0;
    for (let i = 0; i < candidate.length; i++) {
        if (q.indexOf(candidate[i]) < 0 && ++missing > maxEdits)
            return true;
    }
    missing = 0;
    for (let i = 0; i < q.length; i++) {
        if (candidate.indexOf(q[i]) < 0 && ++missing > maxEdits)
            return true;
    }
    return false;
}

function typoCandidateScore(candidate, q, prev, curr) {
    const len = Math.max(candidate.length, q.length);
    const maxEdits = Math.floor(len * (1 - minQuality) + 1e-9);
    if (Math.abs(candidate.length - q.length) > maxEdits || exceedsEdits(candidate, q, maxEdits))
        return 0;
    const edits = boundedLevenshtein(candidate, q, maxEdits, prev, curr);
    return edits > maxEdits ? 0 : 1 - edits / len;
}

function typoScore(item, query) {
    const q = query.lower;
    if (q.length < 3 || query.words.length !== 1)
        return 0;
    const prev = new Array(q.length + 1);
    const curr = new Array(q.length + 1);
    let best = typoCandidateScore(item.lower, q, prev, curr);
    for (const word of item.words)
        best = Math.max(best, typoCandidateScore(word, q, prev, curr));
    if (q.length >= 4) {
        for (const word of item.words) {
            if (word.length > q.length)
                best = Math.max(best, typoCandidateScore(word.slice(0, q.length), q, prev, curr));
        }
    }
    return Math.round(Tier.typo * best);
}

function textScore(item, query) {
    return lexicalScore(item, query) || fuzzyScore(item, query) || typoScore(item, query);
}
