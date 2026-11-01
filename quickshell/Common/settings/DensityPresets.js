.pragma library

var LEVELS = ["spacious", "comfortable", "compact", "dense"];

// Indexed in LEVELS order.
var PRESETS = {
    bar: {
        innerPadding: [6, 2, -2, -4],
        widgetPadding: [10, 8, 7, 5]
    },
    island: {
        islandCompactThickness: [42, 38, 34, 32],
        islandSatelliteGap: [16, 12, 8, 6]
    },
    dock: {
        iconSize: [46, 42, 38, 36],
        itemSpacing: [10, 8, 6, 4],
        spacing: [10, 8, 6, 4]
    },
    frame: {
        frameThickness: [20, 16, 12, 8],
        frameBarSize: [44, 40, 36, 34]
    }
};

function value(surface, key, density) {
    var row = PRESETS[surface] && PRESETS[surface][key];
    var index = LEVELS.indexOf(density);
    return row && index >= 0 ? row[index] : undefined;
}

function values(surface, density) {
    var out = {};
    for (var key in PRESETS[surface] || {}) {
        var preset = value(surface, key, density);
        if (preset !== undefined)
            out[key] = preset;
    }
    return out;
}

// Only fields missing or still on the outgoing preset move; anything else is user-set.
function transition(config, surface, from, to) {
    if (from === to || LEVELS.indexOf(from) < 0 || LEVELS.indexOf(to) < 0 || !config)
        return null;
    var out = null;
    for (var key in PRESETS[surface] || {}) {
        var current = config[key];
        if (current !== undefined && current !== value(surface, key, from))
            continue;
        out = out || Object.assign({}, config);
        out[key] = value(surface, key, to);
    }
    return out;
}

// Island keys outlive the island flag (frame mode drops it), so they keep moving.
function _surfacesFor(kind, config) {
    if (kind !== "bar" || !config)
        return [kind];
    var island = config.island === true || config.dot === true || Object.keys(PRESETS.island).some(function (key) {
        return key in config;
    });
    return island ? ["bar", "island"] : ["bar"];
}

function transitionAll(configs, kind, from, to) {
    var changed = false;
    var out = (configs || []).map(function (config) {
        var next = config;
        _surfacesFor(kind, config).forEach(function (surface) {
            next = transition(next, surface, from, to) || next;
        });
        changed = changed || next !== config;
        return next;
    });
    return changed ? out : null;
}
