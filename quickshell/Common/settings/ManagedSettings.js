.pragma library
.import "SettingsSpec.js" as SpecModule

function parse(text, warn) {
    const settings = {};
    if (!text)
        return settings;
    let policy;
    try {
        policy = JSON.parse(text);
    } catch (e) {
        warn("Ignoring unreadable managed settings:", e.message);
        return settings;
    }
    for (const key in policy) {
        const spec = SpecModule.SPEC[key];
        if (!spec || spec.persist === false) {
            warn("Ignoring managed setting that does not exist:", key);
            continue;
        }
        const value = policy[key];
        if (typeof value !== typeof spec.def || Array.isArray(value) !== Array.isArray(spec.def)) {
            warn("Ignoring managed setting of the wrong type:", key, JSON.stringify(value));
            continue;
        }
        settings[key] = value;
    }
    return settings;
}
