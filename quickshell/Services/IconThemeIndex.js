.pragma library

function create() {
    return {
        paths: Object.create(null),
        scores: Object.create(null),
        directories: Object.create(null)
    };
}

function add(index, path, searchDirs, looseDirs) {
    const separator = path.lastIndexOf("/") + 1;
    const fileName = path.substring(separator);
    const name = fileName.replace(/\.(svg|png|xpm)$/, "");
    if (!/^[\w.+-]+$/.test(name))
        return;
    const directory = path.substring(0, separator);
    let directoryScore = index.directories[directory];
    if (directoryScore === undefined) {
        directoryScore = score(directory, searchDirs, looseDirs);
        index.directories[directory] = directoryScore;
    }
    const candidateScore = directoryScore + (fileName.endsWith(".svg") ? 100000 : 0);
    const currentScore = index.scores[name];
    if (currentScore !== undefined && candidateScore <= currentScore)
        return;
    index.paths[name] = path;
    index.scores[name] = candidateScore;
}

function chainIndex(path, searchDirs, looseDirs) {
    for (let i = 0; i < searchDirs.length; i++) {
        if (path.startsWith(searchDirs[i] + "/"))
            return i;
    }
    for (let i = 0; i < looseDirs.length; i++) {
        if (path.startsWith(looseDirs[i] + "/"))
            return searchDirs.length + i;
    }
    return searchDirs.length + looseDirs.length;
}

const LARGEST_PREFERRED_RASTER = 256;

function rasterScore(size) {
    if (size <= LARGEST_PREFERRED_RASTER)
        return LARGEST_PREFERRED_RASTER + size;
    return Math.max(0, LARGEST_PREFERRED_RASTER - size / 8);
}

function score(path, searchDirs, looseDirs) {
    let s = 0;
    if (path.includes("/apps/"))
        s += 3000000000;
    else if (path.includes("/categories/"))
        s += 1000000000;
    else if (path.includes("/places/") || path.includes("/devices/") || path.includes("/mimetypes/") || path.includes("/status/") || path.includes("/actions/"))
        s += 100000000;

    s += Math.min(99, Math.max(0, searchDirs.length + looseDirs.length - chainIndex(path, searchDirs, looseDirs))) * 1000000;

    if (path.endsWith(".svg"))
        s += 100000;

    if (path.includes("/scalable/")) {
        s += 1000;
    } else {
        const m = path.match(/\/(\d+)(?:x\d+)?(?:@\d+x)?\//);
        if (m)
            s += rasterScore(parseInt(m[1]));
    }
    return s;
}
