.pragma library

// Repeated ids are numbered so selection and expansion stay on the same card across refreshes
function cards(pluginId, rawItems, transform) {
    var seen = {};
    return rawItems.map(raw => {
        var base = "live:" + pluginId + ":" + (raw.id || raw.name);
        var id = base;
        for (var n = 2; seen[id]; n++)
            id = base + "#" + n;
        seen[id] = true;
        return Object.assign(transform(raw), {
            id: id,
            section: "live_" + pluginId
        });
    });
}

// Base sections are copied because flattening writes flatStartIndex into them
function merge(base, live) {
    var merged = live.length > 0 ? base.map(s => Object.assign({}, s)) : base;
    for (var i = 0; i < live.length; i++) {
        var at = merged.findIndex(s => s.priority > live[i].priority);
        merged.splice(at < 0 ? merged.length : at, 0, live[i]);
    }
    return merged;
}
