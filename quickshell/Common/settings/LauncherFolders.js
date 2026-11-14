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

function transformFolder(folder, memberItems, openLabel) {
    return {
        id: "folder:" + folder.id,
        type: "folder",
        name: folder.name || "",
        subtitle: "",
        icon: folder.icon || "",
        iconType: folder.icon ? "material" : "folder",
        section: "apps",
        data: {
            folderId: folder.id,
            members: memberItems
        },
        keywords: [],
        actions: [],
        primaryAction: {
            name: openLabel,
            icon: "folder_open",
            action: "open"
        },
        _hName: "",
        _hSub: "",
        _hRich: false,
        _preScored: undefined
    };
}

function folderMembers(folder, itemsById) {
    var members = [];
    var ids = folder.apps || [];
    for (var i = 0; i < ids.length; i++) {
        var item = itemsById[ids[i]];
        if (item)
            members.push(item);
    }
    return members;
}

function foldApps(items, folders, openLabel) {
    if (!folders || folders.length === 0)
        return items;
    var folderByApp = {};
    for (var f = 0; f < folders.length; f++) {
        var apps = folders[f].apps || [];
        for (var a = 0; a < apps.length; a++)
            folderByApp[apps[a]] = folders[f].id;
    }
    var result = [];
    var folderedById = {};
    var folded = false;
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (item.type !== "app" || !folderByApp[item.id]) {
            result.push(item);
            continue;
        }
        folderedById[item.id] = item;
        folded = true;
    }
    if (!folded)
        return items;
    for (var k = 0; k < folders.length; k++) {
        var members = folderMembers(folders[k], folderedById);
        if (members.length > 0)
            result.push(transformFolder(folders[k], members, openLabel));
    }
    return result;
}

function placeFolders(items, folders, sourceItems) {
    if (!folders || folders.length === 0)
        return items;
    var slotById = {};
    for (var f = 0; f < folders.length; f++)
        slotById["folder:" + folders[f].id] = f;
    var rest = [];
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (item.type !== "folder" || slotById[item.id] === undefined)
            rest.push(item);
    }
    // Folder scores can fall below the app-result cap.
    var candidates = sourceItems || items;
    var placed = [];
    for (var i = 0; i < candidates.length; i++) {
        var item = candidates[i];
        if (item.type !== "folder" || slotById[item.id] === undefined)
            continue;
        var folder = folders[slotById[item.id]];
        placed.push({
            item: item,
            slot: Math.max(0, Math.trunc(folder.slot) || 0),
            order: slotById[item.id]
        });
    }
    if (placed.length === 0)
        return items;
    // Reverse ties because later splices land first.
    placed.sort(function (a, b) {
        return a.slot - b.slot || b.order - a.order;
    });
    for (var p = 0; p < placed.length; p++)
        rest.splice(Math.min(placed[p].slot, rest.length), 0, placed[p].item);
    return rest;
}
