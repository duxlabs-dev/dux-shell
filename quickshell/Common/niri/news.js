.pragma library

// "New" pills: the page keys each niri release introduced (recherche.md), so a pill can say
// which options arrived with the running version until the user has seen them.

var introduced = {
    "25.11": ["columns.altTab", "columns.altTabDelay", "columns.altTabPreviewScale"],
    "26.04": ["look.blurOn", "look.blurStrength", "look.xray", "look.barXray"]
};

function versions() {
    return Object.keys(introduced);
}

function parseVersion(version) {
    const match = /^(\d+)\.(\d+)$/.exec(String(version ?? "").trim());
    return match ? [Number(match[1]), Number(match[2])] : null;
}

function newer(a, b) {
    const va = parseVersion(a);
    const vb = parseVersion(b);
    if (!va || !vb)
        return false;
    return va[0] > vb[0] || (va[0] === vb[0] && va[1] > vb[1]);
}

// Keys that arrived after `seen` and exist in `running`. An unknown running version shows
// nothing; nothing seen yet counts as older than every release.
function newKeys(seen, running) {
    if (!parseVersion(running))
        return [];
    const keys = [];
    for (const version of versions()) {
        if (!newer(version, seen) && parseVersion(seen))
            continue;
        if (newer(version, running))
            continue;
        for (const key of introduced[version])
            if (keys.indexOf(key) < 0)
                keys.push(key);
    }
    return keys;
}

function isNew(key, seen, running) {
    return newKeys(seen, running).indexOf(key) >= 0;
}
