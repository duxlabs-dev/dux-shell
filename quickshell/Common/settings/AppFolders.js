.pragma library

function _list(value) {
    return Array.isArray(value) ? value : [];
}

function _apps(folder) {
    return _list(folder && folder.apps);
}

function _indexOfFolder(folders, id) {
    for (var i = 0; i < folders.length; i++) {
        if (folders[i] && folders[i].id === id)
            return i;
    }
    return -1;
}

function _replaceAt(folders, index, patch) {
    var next = folders.slice();
    next[index] = Object.assign({}, folders[index], patch);
    return next;
}

function _stripApps(folders, appIds, keepId) {
    var changed = false;
    var next = [];
    for (var i = 0; i < folders.length; i++) {
        var folder = folders[i];
        if (!folder || folder.id === keepId) {
            next.push(folder);
            continue;
        }
        var apps = _apps(folder);
        var kept = apps.filter(function (id) {
            return appIds.indexOf(id) === -1;
        });
        if (kept.length === apps.length) {
            next.push(folder);
            continue;
        }
        changed = true;
        if (kept.length > 0)
            next.push(Object.assign({}, folder, {
                apps: kept
            }));
    }
    return changed ? next : folders;
}

function newFolderId() {
    return "f" + Date.now().toString(36) + (Math.random().toString(36) + "0000").slice(2, 6);
}

function folderById(folders, id) {
    if (!id)
        return null;
    folders = _list(folders);
    var index = _indexOfFolder(folders, id);
    return index === -1 ? null : folders[index];
}

function folderForApp(folders, appId) {
    if (!appId)
        return null;
    folders = _list(folders);
    for (var i = 0; i < folders.length; i++) {
        if (_apps(folders[i]).indexOf(appId) !== -1)
            return folders[i];
    }
    return null;
}

function _slot(value) {
    var n = Math.trunc(Number(value));
    return isFinite(n) && n > 0 ? n : 0;
}

function createFolder(folders, name, appIds, slot) {
    folders = _list(folders);
    var ids = [];
    _list(appIds).forEach(function (id) {
        if (id && ids.indexOf(id) === -1)
            ids.push(id);
    });
    if (ids.length === 0)
        return {
            folders: folders,
            id: ""
        };
    var id = newFolderId();
    var next = _stripApps(folders, ids, null).concat([
        {
            id: id,
            name: name || "",
            icon: "",
            apps: ids,
            slot: _slot(slot)
        }
    ]);
    return {
        folders: next,
        id: id
    };
}

function renameFolder(folders, id, name) {
    folders = _list(folders);
    var trimmed = (name || "").trim();
    var index = _indexOfFolder(folders, id);
    if (index === -1 || !trimmed || folders[index].name === trimmed)
        return folders;
    return _replaceAt(folders, index, {
        name: trimmed
    });
}

function setFolderIcon(folders, id, icon) {
    folders = _list(folders);
    var index = _indexOfFolder(folders, id);
    if (index === -1 || (folders[index].icon || "") === (icon || ""))
        return folders;
    return _replaceAt(folders, index, {
        icon: icon || ""
    });
}

function setFolderSlot(folders, id, slot) {
    folders = _list(folders);
    var index = _indexOfFolder(folders, id);
    if (index === -1)
        return folders;
    var next = _slot(slot);
    if (_slot(folders[index].slot) === next)
        return folders;
    return _replaceAt(folders, index, {
        slot: next
    });
}

function addApp(folders, folderId, appId) {
    folders = _list(folders);
    var index = _indexOfFolder(folders, folderId);
    if (!appId || index === -1 || _apps(folders[index]).indexOf(appId) !== -1)
        return folders;
    var next = _stripApps(folders, [appId], folderId);
    index = _indexOfFolder(next, folderId);
    return _replaceAt(next, index, {
        apps: _apps(next[index]).concat([appId])
    });
}

function removeApp(folders, appId) {
    folders = _list(folders);
    if (!appId)
        return folders;
    return _stripApps(folders, [appId], null);
}

function moveApp(folders, folderId, fromIndex, toIndex) {
    folders = _list(folders);
    var index = _indexOfFolder(folders, folderId);
    if (index === -1)
        return folders;
    var apps = _apps(folders[index]);
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= apps.length || toIndex >= apps.length)
        return folders;
    var reordered = apps.slice();
    reordered.splice(toIndex, 0, reordered.splice(fromIndex, 1)[0]);
    return _replaceAt(folders, index, {
        apps: reordered
    });
}

function dissolveFolder(folders, id) {
    folders = _list(folders);
    var index = _indexOfFolder(folders, id);
    if (index === -1)
        return folders;
    var next = folders.slice();
    next.splice(index, 1);
    return next;
}

// Folders move as a unit; only apps can join one.
function dropAction(source, target) {
    if (!source || !target || source.id === target.id)
        return "";
    if (source.type === "folder")
        return "move";
    if (source.type !== "app")
        return "";
    if (target.type === "folder")
        return "add";
    return target.type === "app" ? "create" : "";
}

function moveAppById(folders, folderId, sourceId, targetId) {
    const apps = _apps(folderById(folders, folderId));
    return moveApp(folders, folderId, apps.indexOf(sourceId), apps.indexOf(targetId));
}

function memberGridIndex(x, y, width, cellHeight, columns, rtl) {
    if (x < 0 || x >= width || y < 0 || cellHeight <= 0 || columns <= 0)
        return -1;
    const column = Math.floor((x / width) * columns);
    return Math.floor(y / cellHeight) * columns + (rtl ? columns - 1 - column : column);
}

function addToFolderEntries(folders, options) {
    folders = _list(folders);
    const add = folder => ({
        type: "item",
        icon: "folder",
        text: options.label(folder),
        action: () => options.add(folder)
    });
    if (folders.length < 2)
        return folders.map(add);
    return [{
        type: "item",
        icon: "folder",
        text: options.header,
        trailingIcon: options.expanded ? "expand_less" : "expand_more",
        keepOpen: true,
        action: options.toggle
    }].concat(folders.map(folder => Object.assign(add(folder), {
        indent: options.indent,
        hidden: !options.expanded
    })));
}
