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

function score(item, query, frecencyData) {
    var typeBonus = Weights.typeBonus[item.type] || 0;

    if (!query || query.length === 0) {
        var usageCount = frecencyData ? frecencyData.usageCount : 0;
        return typeBonus + (usageCount * 100);
    }

    var name = (item.name || "").toLowerCase();
    var q = query.toLowerCase();

    var textScore = calculateTextScore(name, q);

    if (textScore === 0 && item.subtitle) {
        var subtitleScore = calculateTextScore(item.subtitle.toLowerCase(), q);
        textScore = subtitleScore * 0.5;
    }

    if (textScore === 0 && item.keywords) {
        for (var i = 0; i < item.keywords.length; i++) {
            var keywordScore = calculateTextScore(item.keywords[i].toLowerCase(), q);
            if (keywordScore > 0) {
                textScore = keywordScore * 0.3;
                break;
            }
        }
    }

    if (textScore === 0 && item.data && item.data.genericName) {
        var genericLower = item.data.genericName.toLowerCase();
        if (genericLower.startsWith(q))
            textScore = Weights.genericPrefix;
        else if (genericLower.includes(q))
            textScore = Weights.generic;
    }

    if (textScore === 0 && item.id && item.type === "app") {
        var id = item.id.toLowerCase().replace(/\.desktop$/, "");
        if (id.includes(q)) {
            textScore = Weights.id;
        }
    }

    if (textScore === 0)
        return 0;

    var usageBonus = frecencyData ? Math.min(frecencyData.usageCount * 50, Weights.frecency) : 0;

    return textScore + usageBonus + typeBonus;
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
