.pragma library
.import "AppFolders.js" as AppFolders

function isFolder(pin) {
    return !!pin && typeof pin.id === "string" && Array.isArray(pin.apps);
}

function id(pin) {
    return isFolder(pin) ? "folder:" + pin.id : pin;
}

function contains(pins, appId) {
    return !!appId && (pins.includes(appId) || AppFolders.folderForApp(pins, appId) !== null);
}

function add(pins, appId) {
    return !appId || contains(pins, appId) ? pins : pins.concat(appId);
}

function remove(pins, appId) {
    const next = AppFolders.removeApp(pins, appId);
    return next.includes(appId) ? next.filter(pin => pin !== appId) : next;
}

function drop(pins, sourceId, targetId, name) {
    const source = pins.find(pin => id(pin) === sourceId);
    const target = pins.find(pin => id(pin) === targetId);
    if (typeof source !== "string" || !target || source === target)
        return pins;
    if (isFolder(target)) {
        const next = AppFolders.addApp(pins, target.id, source);
        return next === pins ? pins : next.filter(pin => pin !== source);
    }
    const folder = AppFolders.createFolder([], name, [target, source]).folders[0];
    return pins.filter(pin => pin !== source).map(pin => pin === target ? folder : pin);
}

function create(pins, appId, name) {
    if (!appId || AppFolders.folderForApp(pins, appId))
        return pins;
    const folder = AppFolders.createFolder([], name, [appId]).folders[0];
    return pins.includes(appId) ? pins.map(pin => pin === appId ? folder : pin) : pins.concat([folder]);
}

function extract(pins, folderId, appId) {
    const folder = AppFolders.folderById(pins, folderId);
    if (!folder?.apps.includes(appId))
        return pins;
    const next = AppFolders.removeApp(pins, appId);
    const index = next.findIndex(pin => id(pin) === id(folder));
    const result = next.slice();
    result.splice(index >= 0 ? index + 1 : pins.indexOf(folder), 0, appId);
    return result;
}

function dissolve(pins, folderId) {
    const folder = AppFolders.folderById(pins, folderId);
    if (!folder)
        return pins;
    const next = pins.slice();
    next.splice(next.indexOf(folder), 1, ...folder.apps);
    return next;
}
