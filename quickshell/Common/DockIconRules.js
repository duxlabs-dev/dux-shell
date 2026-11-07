.pragma library

// Terminals prefix titles with spinners and status glyphs that change while
// the rest stays put, so remembered titles ignore leading symbols.
function titleKey(title) {
    return (title || "").replace(/^(?:[\s!-\/:-@\[-`{-~ -¿ -⯿　️]|[\ud83c-\ud83e][\udc00-\udfff])+/, "").trim();
}

function findRule(rules, appId, title) {
    const key = titleKey(title);
    if (!appId || !key)
        return null;
    return (rules || []).find(rule => rule.appId === appId && rule.title === key) ?? null;
}

function withoutRule(rules, appId, key) {
    return (rules || []).filter(rule => rule.appId !== appId || rule.title !== key);
}

function withRule(rules, appId, key, icon) {
    return withoutRule(rules, appId, key).concat([
        {
            "appId": appId,
            "title": key,
            "icon": icon
        }
    ]);
}
