.pragma library

function value(spec, stored) {
    switch (spec.type) {
    case "toggle":
        return typeof stored === "boolean" ? stored : spec.def;
    case "choice":
        return spec.choices.some(c => c.value === stored) ? stored : spec.def;
    case "number":
    case "slider":
        if (!Number.isFinite(stored))
            return spec.def;
        return Math.max(spec.min, Math.min(spec.max, stored));
    }
    return spec.def;
}
