.pragma library

function windowIdentity(toplevel, appId, coreApps) {
    const core = ["org.quickshell", "dev.duxlabs.shell", "com.danklinux.dms"].includes(toplevel.appId)
        ? coreApps.find(app => app.name === toplevel.title) ?? null : null;
    return { appId: core?.builtInPluginId ?? appId, coreAppData: core, isCoreApp: core !== null };
}

function pinnedItem(appId, coreAppData, isRunning) {
    return {
        uniqueKey: "pinned_" + appId, type: "pinned", appId, toplevel: null,
        isPinned: true, isRunning: isRunning ?? false, isCoreApp: coreAppData !== null,
        coreAppData, isInOverflow: false
    };
}

function separator(key) {
    return { uniqueKey: key, type: "separator", appId: "__SEPARATOR__", toplevel: null, isPinned: false, isRunning: false };
}

function overflow(items, maxPinned, maxRunning) {
    const pinned = items.filter(item => item.isPinned && item.type !== "launcher");
    const running = items.filter(item => item.isRunning && !item.isPinned);
    const hidden = new Set((maxPinned > 0 ? pinned.slice(maxPinned) : []).concat(maxRunning > 0 ? running.slice(maxRunning) : []).map(item => item.uniqueKey));
    if (!hidden.size)
        return { items: items.map(item => Object.assign({}, item, { isInOverflow: false })), count: 0 };
    const result = [];
    let separated = false;
    for (const item of items) {
        if (item.type === "separator")
            continue;
        if (item.type === "launcher") {
            result.push(item);
            continue;
        }
        if (!item.isPinned && !item.isRunning)
            continue;
        if (!item.isPinned && !separated && result.length) {
            result.push(separator("separator_overflow"));
            separated = true;
        }
        result.push(Object.assign({}, item, { isInOverflow: hidden.has(item.uniqueKey) }));
    }
    const separatorIndex = result.findIndex(item => item.type === "separator");
    result.splice(separatorIndex < 0 ? result.length : separatorIndex, 0, {
        uniqueKey: "overflow_toggle", type: "overflow-toggle", appId: "__OVERFLOW_TOGGLE__",
        toplevel: null, isPinned: false, isRunning: false, overflowCount: hidden.size
    });
    return { items: result, count: hidden.size };
}

function movePin(pins, items, from, to) {
    const source = items[from];
    const target = items[to];
    if (!source?.isPinned || !target?.isPinned || source.type === "launcher")
        return pins;
    const pinned = items.filter(item => item.isPinned && item.type !== "launcher");
    const sourceIndex = pinned.indexOf(source);
    const targetIndex = target.type === "launcher" ? items.slice(0, to).filter(item => item.isPinned && item.type !== "launcher").length : pinned.indexOf(target);
    if (sourceIndex < 0 || sourceIndex >= pins.length || targetIndex < 0 || sourceIndex === targetIndex)
        return pins;
    const result = pins.slice();
    result.splice(Math.min(targetIndex, result.length - 1), 0, result.splice(sourceIndex, 1)[0]);
    return result;
}
