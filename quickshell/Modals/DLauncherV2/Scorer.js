.pragma library
.import "../../Common/SearchMatch.js" as SearchMatch

const Weights = {
    genericPrefix: 800,
    generic: 400,
    id: 350,
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

let preparedNames = Object.create(null);
let preparedNameCount = 0;
const maxPreparedNames = 8192;
const maxPreparedCharacters = 256 * 1024;
let preparedCharacters = 0;

function preparedName(item) {
    const name = String(item.name || "");
    let prepared = preparedNames[name];
    if (prepared)
        return prepared;
    prepared = SearchMatch.prepareText(name);
    if (name.length > maxPreparedCharacters)
        return prepared;
    if (preparedNameCount >= maxPreparedNames || preparedCharacters + name.length > maxPreparedCharacters) {
        preparedNames = Object.create(null);
        preparedNameCount = 0;
        preparedCharacters = 0;
    }
    preparedNames[name] = prepared;
    preparedNameCount++;
    preparedCharacters += name.length;
    return prepared;
}

function score(item, query, frecencyData) {
    var typeBonus = Weights.typeBonus[item.type] || 0;

    if (!query.lower) {
        var usageCount = frecencyData ? frecencyData.usageCount : 0;
        return typeBonus + (usageCount * 100);
    }

    var q = query.lower;
    var textScore = SearchMatch.textScore(preparedName(item), query);

    if (textScore === 0 && item.subtitle)
        textScore = SearchMatch.lexicalScore(SearchMatch.prepareText(item.subtitle), query) * 0.5;

    if (textScore === 0 && item.keywords) {
        for (var i = 0; i < item.keywords.length; i++) {
            var keywordScore = SearchMatch.lexicalScore(SearchMatch.prepareText(item.keywords[i]), query);
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
    var preparedQuery = SearchMatch.prepareQuery(query);

    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        var itemScore;

        if (item._preScored !== undefined && (query || item._preScored > 900)) {
            itemScore = item._preScored;
        } else {
            var frecencyData = getFrecencyFn ? getFrecencyFn(item) : null;
            itemScore = score(item, preparedQuery, frecencyData);
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
