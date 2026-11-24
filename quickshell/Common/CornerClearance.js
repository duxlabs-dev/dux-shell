.pragma library

// Largest screen-corner radius whose arc stays clear of a rounded corner `radius` inset `gap` from both edges:
// the concentric radius (gap + radius) plus the slack the two arcs leave along the diagonal.
function limit(gap, radius) {
    return (2 + Math.SQRT2) * Math.max(0, gap) + Math.max(0, radius);
}

// Floating bars reaching a corner bound the radius; a bar with no gap sits flush and is meant to be rounded with the screen.
function screenLimit(layouts, windowLimit, barRadius, spansEdge) {
    let result = windowLimit;
    for (const layout of layouts) {
        for (const instance of layout.instances) {
            if (instance.kind !== "bar" || !(instance.spacing > 0))
                continue;
            const config = layout.bars.find(input => input.config.id === instance.barId)?.config;
            if (!config || !spansEdge(config))
                continue;
            result = Math.min(result, limit(instance.spacing, config.squareCorners ? 0 : barRadius));
        }
    }
    return result;
}
