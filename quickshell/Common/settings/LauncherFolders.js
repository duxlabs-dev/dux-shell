.pragma library

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
