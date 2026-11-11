.pragma library

function validId(value) {
    return typeof value === "string" && /^[a-zA-Z0-9_.:-]{1,64}$/.test(value);
}

function register(entries, source, id, priority, matcher, interceptor, label, description) {
    if (!validId(source) || !validId(id) || typeof matcher !== "function" || typeof interceptor !== "function")
        return null;
    const retained = entries.filter(entry => entry.source !== source || entry.id !== id);
    if (retained.length >= 128)
        return null;
    const numericPriority = Number(priority);
    return retained.concat([{
        source,
        id,
        priority: Number.isFinite(numericPriority) ? Math.max(-100, Math.min(100, numericPriority)) : 0,
        matcher,
        interceptor,
        label: typeof label === "string" && label ? label.slice(0, 128) : id,
        description: typeof description === "string" ? description.slice(0, 256) : ""
    }]);
}

function evaluate(entries, info, priorityFor, enabledFor) {
    const ordered = entries.filter(entry => enabledFor(entry)).slice().sort((left, right) => priorityFor(right) - priorityFor(left) || left.id.localeCompare(right.id));
    for (const entry of ordered) {
        try {
            if (!entry.matcher(info))
                continue;
            const result = entry.interceptor(info);
            if (result && typeof result === "object" && !Array.isArray(result))
                return {source: entry.source, id: entry.id, result};
        } catch (error) {}
    }
    return null;
}
