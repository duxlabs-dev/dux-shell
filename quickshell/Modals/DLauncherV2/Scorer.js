.pragma library

const Weights = {
    exactMatch: 10000,
    prefixMatch: 5000,
    wordBoundary: 3000,
    substring: 500,
    genericPrefix: 800,
    generic: 400,
    id: 350,
    fuzzy: 100,
    frecency: 2000,
    typeBonus: {
        app: 1000,
        plugin: 900,
        setting: 850,
        clipboard: 825,
        file: 800,
        action: 600
    }
};

// Rank fusion of lexical, semantic and usage rankings for catalog entries.
// k is small on purpose: the lists are a handful of rows long and the model's
// cosine scores sit close together (0.6 to 0.8), so rank 1 against rank 5 must
// still matter, which k = 60 would flatten. Lexical and semantic count the same:
// an agreement between them beats either alone. Usage only breaks ties, so it
// weighs half and never admits an entry on its own.
var Fusion = {
    k: 10,
    lexicalWeight: 1,
    semanticWeight: 1,
    usageWeight: 0.5,
    // Typed name found at a word start (or better): the model must not overrule it.
    strongLexical: Weights.wordBoundary,
    // Measured through the real launcher with embeddinggemma-2 int8 on the shell's own
    // catalogs (31 actions): 13 Turkish queries with a matching action scored 0.718 to
    // 0.818 on the right one, 11 queries without any action 0.621 to 0.673. Below the floor
    // a hit is noise and neither shows nor counts. The runner-up margin of the right
    // action was 0.022 to 0.096 (12 of 13 at 0.03 or more), of the unrelated top hit at
    // most 0.014. Re-measure when the catalog grows: more neighbours shrink margins.
    semanticFloor: 0.70,
    // A typo-level fuzzy match of a keyword scores 30 at most ("karanlik" against "kulaklik"
    // lists Bluetooth); a substring of a keyword scores 150.
    minLexical: 150,
    semanticMargin: 0.03,
    // Above every classic score so fused entries keep their order inside a section.
    scoreBase: 20000
};

function tokenize(text) {
    return text.toLowerCase().trim().split(/[\s\-_]+/).filter(function (w) {
        return w.length > 0;
    });
}

function hasWordBoundaryMatch(text, query) {
    var textWords = tokenize(text);
    var queryWords = tokenize(query);

    if (queryWords.length === 0)
        return false;
    if (queryWords.length > textWords.length)
        return false;

    for (var i = 0; i <= textWords.length - queryWords.length; i++) {
        var allMatch = true;
        for (var j = 0; j < queryWords.length; j++) {
            if (!textWords[i + j].startsWith(queryWords[j])) {
                allMatch = false;
                break;
            }
        }
        if (allMatch)
            return true;
    }
    return false;
}

function levenshteinDistance(s1, s2) {
    var len1 = s1.length;
    var len2 = s2.length;
    var prev = new Array(len2 + 1);
    var curr = new Array(len2 + 1);

    for (var j = 0; j <= len2; j++)
        prev[j] = j;

    for (var i = 1; i <= len1; i++) {
        curr[0] = i;
        for (var j = 1; j <= len2; j++) {
            var cost = s1[i - 1] === s2[j - 1] ? 0 : 1;
            curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
        }
        var tmp = prev;
        prev = curr;
        curr = tmp;
    }
    return prev[len2];
}

function fuzzyScore(text, query) {
    var maxDistance = query.length === 3 ? 1 : query.length <= 6 ? 2 : 3;
    var bestScore = 0;

    if (Math.abs(text.length - query.length) <= maxDistance) {
        var distance = levenshteinDistance(text, query);
        if (distance <= maxDistance) {
            var maxLen = Math.max(text.length, query.length);
            bestScore = 1 - (distance / maxLen);
        }
    }

    var words = tokenize(text);
    for (var i = 0; i < words.length && bestScore < 0.8; i++) {
        if (Math.abs(words[i].length - query.length) > maxDistance)
            continue;
        var wordDistance = levenshteinDistance(words[i], query);
        if (wordDistance <= maxDistance) {
            var wordMaxLen = Math.max(words[i].length, query.length);
            var score = 1 - (wordDistance / wordMaxLen);
            bestScore = Math.max(bestScore, score);
        }
    }

    return bestScore;
}

function calculateTextScore(name, query) {
    if (name === query)
        return Weights.exactMatch;
    if (name.startsWith(query))
        return Weights.prefixMatch;
    if (hasWordBoundaryMatch(name, query))
        return Weights.wordBoundary;
    if (name.includes(query))
        return Weights.substring;

    if (query.length >= 3) {
        var fs = fuzzyScore(name, query);
        if (fs > 0)
            return fs * Weights.fuzzy;
    }

    return 0;
}

function textScore(item, query) {
    if (!query || query.length === 0)
        return 0;

    var name = (item.name || "").toLowerCase();
    var q = query.toLowerCase();

    var best = calculateTextScore(name, q);

    // An action's subtitle is its live state ("Now: On"), not something to match.
    if (best === 0 && item.subtitle && item.type !== "action") {
        var subtitleScore = calculateTextScore(item.subtitle.toLowerCase(), q);
        best = subtitleScore * 0.5;
    }

    if (best === 0 && item.keywords) {
        for (var i = 0; i < item.keywords.length; i++) {
            var keywordScore = calculateTextScore(item.keywords[i].toLowerCase(), q);
            if (keywordScore > 0) {
                best = keywordScore * 0.3;
                break;
            }
        }
    }

    if (best === 0 && item.data && item.data.genericName) {
        var genericLower = item.data.genericName.toLowerCase();
        if (genericLower.startsWith(q))
            best = Weights.genericPrefix;
        else if (genericLower.includes(q))
            best = Weights.generic;
    }

    if (best === 0 && item.id && item.type === "app") {
        var id = item.id.toLowerCase().replace(/\.desktop$/, "");
        if (id.includes(q)) {
            best = Weights.id;
        }
    }

    return best;
}

function score(item, query, frecencyData) {
    var typeBonus = Weights.typeBonus[item.type] || 0;

    if (!query || query.length === 0) {
        var usageCount = frecencyData ? frecencyData.usageCount : 0;
        return typeBonus + (usageCount * 100);
    }

    var matched = textScore(item, query);
    if (matched === 0)
        return 0;

    var usageBonus = frecencyData ? Math.min(frecencyData.usageCount * 50, Weights.frecency) : 0;

    return matched + usageBonus + typeBonus;
}

function scoreItems(items, query, getFrecencyFn) {
    var scored = [];

    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var itemScore;

        if (item._preScored !== undefined && (query || item._preScored > 900)) {
            itemScore = item._preScored;
        } else {
            var frecencyData = getFrecencyFn ? getFrecencyFn(item) : null;
            itemScore = score(item, query, frecencyData);
        }

        if (itemScore > 0 || !query || query.length === 0) {
            scored.push({
                item: item,
                score: itemScore,
                order: scored.length
            });
        }
    }

    scored.sort(function (a, b) {
        if (a.score !== b.score)
            return b.score - a.score;
        return a.order - b.order;
    });

    return scored;
}

// Rows of one catalog kind are matched to hits by key; a row may carry its own
// (_key) when its id is shared with sibling rows.
function keyOf(item) {
    return item._key !== undefined ? item._key : item.id;
}

// lexical: [{id, strong}] best first. semantic: [{id, score}] best first (cosine).
// usage: {id: count}. Returns [{id, fused, strong, lexRank, semRank, semScore}].
function fuse(lexical, semantic, usage) {
    var entries = {};
    var order = [];
    function entry(id) {
        if (!entries[id]) {
            entries[id] = {
                id: id,
                fused: 0,
                strong: false,
                lexRank: 0,
                semRank: 0,
                semScore: undefined,
                order: order.length
            };
            order.push(id);
        }
        return entries[id];
    }

    for (var i = 0; i < lexical.length; i++) {
        var lex = entry(lexical[i].id);
        if (lex.lexRank > 0)
            continue;
        lex.lexRank = i + 1;
        lex.strong = lexical[i].strong === true;
        lex.fused += Fusion.lexicalWeight / (Fusion.k + lex.lexRank);
    }

    var semRank = 0;
    for (var j = 0; j < semantic.length; j++) {
        var sem = entry(semantic[j].id);
        if (sem.semRank > 0)
            continue;
        sem.semRank = ++semRank;
        sem.semScore = semantic[j].score;
        sem.fused += Fusion.semanticWeight / (Fusion.k + sem.semRank);
    }

    // Only entries another ranking already admitted are ranked by usage.
    var used = order.filter(function (id) {
        return (usage[id] || 0) > 0;
    }).sort(function (a, b) {
        return usage[b] - usage[a] || entries[a].order - entries[b].order;
    });
    for (var u = 0; u < used.length; u++)
        entries[used[u]].fused += Fusion.usageWeight / (Fusion.k + u + 1);

    return order.map(function (id) {
        return entries[id];
    }).sort(function (a, b) {
        if (a.strong !== b.strong)
            return a.strong ? -1 : 1;
        if (a.fused !== b.fused)
            return b.fused - a.fused;
        return a.order - b.order;
    });
}

// lexicalItems: launcher items of one kind that matched the query, best first.
// semanticItems: items resolved from the hits, may repeat lexical ones.
// hits: [{id, score}] as dsearch returned them. Returns {entries, hits}: the fused
// entries, each carrying a copy of its item whose _preScored keeps the fused order
// (the original may be a cached object shared with queries that have no semantic
// side), and the hits that resolved to an item.
function fuseCatalog(lexicalItems, semanticItems, query, hits, usageOf) {
    var byId = {};
    var lexical = [];
    var i;
    for (i = 0; i < lexicalItems.length; i++) {
        var item = lexicalItems[i];
        if (byId[keyOf(item)])
            continue;
        byId[keyOf(item)] = item;
        lexical.push({
            id: keyOf(item),
            strong: textScore(item, query) >= Fusion.strongLexical
        });
    }
    for (i = 0; i < semanticItems.length; i++) {
        if (!byId[keyOf(semanticItems[i])])
            byId[keyOf(semanticItems[i])] = semanticItems[i];
    }
    var semantic = hits.filter(function (hit) {
        return !!byId[hit.id] && hit.score >= Fusion.semanticFloor;
    });
    var usage = {};
    for (var id in byId)
        usage[id] = usageOf ? usageOf(byId[id]) : 0;

    var fused = fuse(lexical, semantic, usage);
    for (i = 0; i < fused.length; i++) {
        fused[i].lexScore = textScore(byId[fused[i].id], query);
        fused[i].item = Object.assign({}, byId[fused[i].id], {
            _preScored: Fusion.scoreBase - i
        });
    }
    return {
        entries: fused,
        hits: semantic
    };
}

// Should the action section sit above the applications? An action runs on Enter,
// so putting a wrong one first is worse than hiding a right one a row lower.
// fused: fuseCatalog output for actions. rivalScore: best lexical score among the
// non-action rows.
function actionsConfident(fused, rivalScore) {
    var entries = fused.entries;
    var hits = fused.hits;
    if (entries.length === 0)
        return false;
    var top = entries[0];
    if (top.lexScore >= Fusion.strongLexical)
        return top.lexScore >= rivalScore;
    if (hits.length === 0 || top.id !== hits[0].id || rivalScore >= Weights.prefixMatch)
        return false;
    var best = hits[0].score;
    var margin = hits.length > 1 ? best - hits[1].score : best;
    return top.lexScore > 0 || margin >= Fusion.semanticMargin;
}

function bestTextScore(items, query) {
    var best = 0;
    for (var i = 0; i < items.length; i++)
        best = Math.max(best, textScore(items[i], query));
    return best;
}

function groupBySection(scoredItems, sectionOrder, sortAlphabetically, maxPerSection) {
    var sections = {};
    var result = [];
    var limit = maxPerSection || 50;

    for (var i = 0; i < sectionOrder.length; i++) {
        var sectionId = sectionOrder[i].id;
        sections[sectionId] = {
            id: sectionId,
            title: sectionOrder[i].title,
            icon: sectionOrder[i].icon,
            priority: sectionOrder[i].priority,
            items: [],
            collapsed: false,
            flatStartIndex: 0
        };
    }

    for (var i = 0; i < scoredItems.length; i++) {
        var scoredItem = scoredItems[i];
        var item = scoredItem.item;
        var sectionId = item.section || "apps";

        if (sections[sectionId] && sections[sectionId].items.length < limit) {
            sections[sectionId].items.push(item);
        } else if (sections["apps"] && sections["apps"].items.length < limit) {
            sections["apps"].items.push(item);
        }
    }

    for (var i = 0; i < sectionOrder.length; i++) {
        var section = sections[sectionOrder[i].id];
        if (section && section.items.length > 0) {
            if (sortAlphabetically && section.id === "apps") {
                section.items.sort(function (a, b) {
                    return (a.name || "").localeCompare(b.name || "");
                });
            }
            result.push(section);
        }
    }

    return result;
}

function flattenSections(sections) {
    var flat = [];
    flat._sectionBounds = null;
    var bounds = {};

    for (var i = 0; i < sections.length; i++) {
        var section = sections[i];

        flat.push({
            isHeader: true,
            section: section,
            sectionId: section.id,
            sectionIndex: i
        });

        var itemStart = flat.length;
        section.flatStartIndex = itemStart;

        if (!section.collapsed) {
            for (var j = 0; j < section.items.length; j++) {
                flat.push({
                    isHeader: false,
                    item: section.items[j],
                    sectionId: section.id,
                    sectionIndex: i,
                    indexInSection: j
                });
            }
        }

        var itemEnd = flat.length - 1;
        var itemCount = flat.length - itemStart;
        if (itemCount > 0) {
            bounds[section.id] = {
                start: itemStart,
                end: itemEnd,
                count: itemCount
            };
        }
    }

    flat._sectionBounds = bounds;
    return flat;
}
