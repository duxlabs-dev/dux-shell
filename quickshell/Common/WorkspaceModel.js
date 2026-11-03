.pragma library

function placeholder() {
    return {
        id: null,
        idx: null,
        name: "",
        output: "",
        active: false,
        placeholder: true
    };
}

function neighbor(workspaces, index, direction) {
    const next = direction > 0 ? Math.min(index + 1, workspaces.length - 1) : Math.max(index - 1, 0);
    return next === index ? null : workspaces[next];
}

function reuse(cache, id, record) {
    const previous = cache[id];
    if (previous && Object.keys(record).every(key => previous[key] === record[key]))
        return previous;
    cache[id] = record;
    return record;
}

function dropStale(cache, ids) {
    for (const key of Object.keys(cache)) {
        if (!ids.has(key))
            delete cache[key];
    }
}

function niriFallback() {
    return [
        {
            id: 1,
            idx: 0,
            name: ""
        },
        {
            id: 2,
            idx: 1,
            name: ""
        }
    ];
}

function niriRecord(ws) {
    return {
        id: ws.id,
        idx: ws.idx,
        name: ws.name ?? "",
        output: ws.output ?? "",
        active: ws.is_active === true,
        placeholder: false
    };
}

function niriCurrentIdx(raw, screenName, followFocus) {
    if (raw.allWorkspaces.length === 0)
        return 1;
    if (!screenName || followFocus)
        return raw.focusedIdx;
    const active = raw.allWorkspaces.find(ws => ws.output === screenName && ws.is_active);
    return active ? active.idx : 1;
}

function niriWorkspacesForScreen(raw, screenName, followFocus, occupiedOnly, cache) {
    const all = raw.allWorkspaces;
    if (all.length === 0)
        return niriFallback().map(niriRecord);
    dropStale(cache, new Set(all.map(ws => String(ws.id))));
    const onScreen = !screenName || followFocus ? raw.currentOutputWorkspaces : all.filter(ws => ws.output === screenName);
    const sorted = (onScreen.length > 0 ? onScreen : niriFallback()).slice().sort((a, b) => a.idx - b.idx);
    const workspaces = occupiedOnly ? sorted.filter(ws => ws.is_active || (raw.windows?.some(win => win.workspace_id === ws.id) ?? false)) : sorted;
    return workspaces.map(ws => reuse(cache, ws.id, niriRecord(ws)));
}

function niriActiveWorkspace(raw, screenName) {
    const ws = raw.allWorkspaces.find(w => (!screenName || w.output === screenName) && w.is_active);
    return ws ? niriRecord(ws) : null;
}

function niriWorkspaceActive(allWorkspaces, workspace) {
    return allWorkspaces.some(ws => ws.id === workspace.id && ws.is_active);
}

function niriWindowsOnWorkspace(windows, workspace) {
    return windows.filter(win => win && win.workspace_id === workspace.id);
}

function niriWorkspaceOccupied(windows, workspace) {
    return windows?.some(win => win.workspace_id === workspace.id) ?? false;
}

function niriWorkspaceUrgent(windows, workspace) {
    if (!workspace?.id)
        return false;
    return windows.some(win => win.workspace_id === workspace.id && win.is_urgent);
}

function hyprlandSpecialName(name) {
    return name === "special" || name.startsWith("special:");
}

function hyprlandSpecial(ws) {
    return !(ws.id > 0) && hyprlandSpecialName(ws.name ?? "");
}

// Hyprland 0.57 gives named workspaces no id (Quickshell reports -1 for all of them), so the address is their identity
function hyprlandKey(ws) {
    if (ws?.id > 0)
        return ws.id;
    return ws?.address || ws?.name || "";
}

// "name:" resolves against the address, which a rename leaves alone; pre-main Hyprland had no address (Quickshell then echoes the id)
function hyprlandSelector(ws) {
    if (ws?.id > 0)
        return ws.id;
    const address = String(ws?.address ?? "");
    const target = address && !/^-?\d+$/.test(address) ? address : String(ws?.name ?? "");
    return hyprlandSpecialName(target) ? target : "name:" + target;
}

function hyprlandOrder(a, b) {
    const keyA = a.id < 0 ? Number.MAX_SAFE_INTEGER : a.id;
    const keyB = b.id < 0 ? Number.MAX_SAFE_INTEGER : b.id;
    if (keyA !== keyB)
        return keyA - keyB;
    return (a.name ?? "").localeCompare(b.name ?? "");
}

function hyprlandRecord(ws) {
    return {
        id: ws.id,
        idx: ws.id > 0 ? ws.id : null,
        address: ws.address ?? "",
        name: ws.name ?? "",
        output: ws.monitor?.name ?? "",
        active: ws.active === true,
        placeholder: false,
        urgent: ws.urgent === true
    };
}

function hyprlandCurrentId(raw, screenName, followFocus) {
    const ws = !screenName || followFocus ? raw.focusedWorkspace : raw.monitors.find(m => m.name === screenName)?.activeWorkspace;
    return hyprlandKey(ws) || 1;
}

function hyprlandMonitorWorkspaces(raw, workspaces, screenName) {
    const monitorWorkspaces = workspaces.filter(ws => ws.monitor?.name === screenName);
    if (monitorWorkspaces.length > 0)
        return monitorWorkspaces.sort(hyprlandOrder);
    const active = raw.monitors.find(m => m.name === screenName)?.activeWorkspace;
    return active ? [active] : [];
}

function hyprlandListedWorkspaces(raw, screenName, followFocus, occupiedOnly) {
    const regular = raw.workspaces.filter(ws => !hyprlandSpecial(ws));
    if (regular.length === 0)
        return [hyprlandRecord({
                id: 1,
                name: "1"
            })];
    const workspaces = !screenName || followFocus ? regular.slice().sort(hyprlandOrder) : hyprlandMonitorWorkspaces(raw, regular, screenName);
    if (!occupiedOnly)
        return workspaces.map(hyprlandRecord);
    const currentKey = hyprlandCurrentId(raw, screenName, followFocus);
    return workspaces.filter(ws => hyprlandKey(ws) === currentKey || hyprlandWorkspaceOccupied(raw.toplevels, ws)).map(hyprlandRecord);
}

function hyprlandRuleIds(workspaceString) {
    const tokens = String(workspaceString ?? "").trim().split(/\s+/);
    if (tokens.includes("s[true]"))
        return [];
    const ids = [];
    for (const token of tokens) {
        if (/^\d+$/.test(token)) {
            ids.push(Number(token));
            continue;
        }
        const range = /^r\[(\d+)-(\d+)\]$/.exec(token);
        if (!range)
            continue;
        for (let id = Number(range[1]); id <= Number(range[2]); id++)
            ids.push(id);
    }
    return ids;
}

// `desc:` rules match a description prefix, like Hyprland's getMonitorFromDesc; a rule for an unplugged monitor binds nothing
function hyprlandRuleMonitor(raw, rule) {
    const target = String(rule.monitor ?? "");
    if (!target)
        return "";
    if (!target.startsWith("desc:"))
        return raw.monitors.some(m => m.name === target) ? target : "";
    const desc = target.slice(5).trim();
    return raw.monitors.find(m => (m.description ?? m.lastIpcObject?.description ?? "").startsWith(desc))?.name ?? "";
}

function hyprlandBoundMonitor(raw, id) {
    for (const rule of raw.workspaceRules ?? []) {
        if (!hyprlandRuleIds(rule.workspaceString).includes(id))
            continue;
        const monitor = hyprlandRuleMonitor(raw, rule);
        if (monitor)
            return monitor;
    }
    return "";
}

// Hyprland creates a numbered workspace on demand, so ids up to minCount are real switch targets even before they exist
function hyprlandPersistentWorkspaces(raw, records, screenName, followFocus, minCount) {
    if (!(minCount > 0))
        return records;
    const perMonitor = !!screenName && !followFocus;
    const taken = new Set(records.map(ws => ws.id));
    // a just-created workspace has no monitor until quickshell's j/workspaces refresh lands; claiming it for another monitor drops its slot for a frame
    if (perMonitor)
        raw.workspaces.forEach(ws => ws.id > 0 && ws.monitor && ws.monitor.name !== screenName && taken.add(ws.id));
    const filled = records.slice();
    for (let id = 1; id <= minCount; id++) {
        if (taken.has(id))
            continue;
        if (perMonitor) {
            const bound = hyprlandBoundMonitor(raw, id);
            if (bound && bound !== screenName)
                continue;
        }
        filled.push(hyprlandRecord({
            id,
            name: String(id),
            monitor: {
                name: perMonitor ? screenName : ""
            }
        }));
    }
    return filled.sort(hyprlandOrder);
}

function hyprlandSpecialDisplayName(name) {
    return name.startsWith("special:") ? name.slice(8) : name;
}

// Hyprland >= 0.56 reports every special workspace with a null id, so specials only match by name
function hyprlandWorkspaceMatches(ws, record) {
    if (record.special !== true)
        return !!ws && hyprlandKey(ws) === hyprlandKey(record);
    const name = ws?.name ?? "";
    return hyprlandSpecialName(name) && hyprlandSpecialDisplayName(name) === record.name;
}

// Hyprland overlays a special workspace on the monitor's regular one, so active comes from the tracked overlay, not ws.active
function hyprlandSpecialWorkspaces(raw, screenName, followFocus, occupiedOnly) {
    const perMonitor = !!screenName && !followFocus;
    const visible = raw.visibleSpecials ?? {};
    const toplevels = raw.toplevels;
    const isVisible = normalized => perMonitor ? visible[screenName] === normalized : Object.values(visible).includes(normalized);
    const specials = raw.workspaces.filter(ws => hyprlandSpecial(ws) && (!perMonitor || ws.monitor?.name === screenName)).map(ws => {
        const name = ws.name ?? "";
        return {
            id: ws.id,
            idx: null,
            name: hyprlandSpecialDisplayName(name),
            output: ws.monitor?.name ?? "",
            active: isVisible(name === "special" ? "special:special" : name),
            placeholder: false,
            urgent: ws.urgent === true,
            special: true
        };
    }).filter(ws => !occupiedOnly || ws.active || toplevels.some(tl => hyprlandWorkspaceMatches(tl.workspace, ws))).sort((a, b) => a.name.localeCompare(b.name));
    // the default scratchpad is always offered so it can be opened before Hyprland has created it
    if (!specials.some(ws => ws.name === "special"))
        specials.push({
            id: null,
            idx: null,
            name: "special",
            output: screenName ?? "",
            active: isVisible("special:special"),
            placeholder: false,
            urgent: false,
            special: true
        });
    return specials;
}

function hyprlandWorkspacesForScreen(raw, screenName, followFocus, occupiedOnly, minCount, showSpecial) {
    const regular = hyprlandPersistentWorkspaces(raw, hyprlandListedWorkspaces(raw, screenName, followFocus, occupiedOnly), screenName, followFocus, minCount);
    if (!showSpecial)
        return regular;
    return regular.concat(hyprlandSpecialWorkspaces(raw, screenName, followFocus, occupiedOnly));
}

function hyprlandScrollWorkspaces(raw, screenName, followFocus) {
    const onScreen = !screenName || followFocus ? raw.workspaces : raw.workspaces.filter(ws => ws.lastIpcObject?.monitor === screenName);
    const numbered = onScreen.filter(ws => ws.id > -1).sort((a, b) => a.id - b.id);
    return (numbered.length > 0 ? numbered : [
            {
                id: 1,
                name: "1"
            }
        ]).map(hyprlandRecord);
}

function hyprlandScrollCurrentId(raw, screenName) {
    return raw.monitors.find(m => m.name === screenName)?.activeWorkspace?.id ?? 1;
}

function hyprlandVisibleSpecial(raw, monitorName) {
    const tracked = raw.visibleSpecials?.[monitorName];
    if (!tracked)
        return null;
    // the overlay event can land before the workspace list refresh, so the tracked name is the OSD's key
    const ws = raw.workspaces.find(ws => hyprlandSpecial(ws) && (ws.name === "special" ? "special:special" : ws.name) === tracked);
    return {
        id: ws?.id || tracked,
        idx: null,
        name: hyprlandSpecialDisplayName(tracked),
        output: monitorName,
        active: true,
        placeholder: false,
        special: true
    };
}

function hyprlandActiveWorkspace(raw, screenName) {
    const monitor = raw.monitors.find(m => !screenName || m.name === screenName);
    const ws = monitor?.activeWorkspace;
    if (!ws)
        return null;
    const special = hyprlandVisibleSpecial(raw, monitor.name ?? screenName);
    if (special)
        return special;
    const name = ws.name ?? "";
    if (hyprlandSpecialName(name))
        return null;
    return {
        id: ws.id,
        idx: ws.id > 0 ? ws.id : null,
        name: name !== "" && name !== String(ws.id) ? name : "",
        output: monitor?.name ?? screenName,
        active: true,
        placeholder: false
    };
}

function hyprlandWindowsOnWorkspace(windows, workspace, toplevels) {
    const workspaces = new Map();
    for (const toplevel of toplevels) {
        if (!workspaces.has(toplevel.wayland))
            workspaces.set(toplevel.wayland, toplevel.workspace);
    }
    return windows.filter(win => win && hyprlandWorkspaceMatches(workspaces.get(win), workspace));
}

function hyprlandWorkspaceOccupied(toplevels, workspace) {
    return toplevels.some(tl => hyprlandWorkspaceMatches(tl.workspace, workspace));
}

function mangoRecord(index, tag, output) {
    const state = tag?.state ?? 0;
    return {
        id: index,
        idx: index + 1,
        name: "",
        output,
        active: state === 1,
        placeholder: false,
        urgent: tag?.urgent ?? state === 2,
        occupied: (tag?.clients ?? 0) > 0
    };
}

function mangoWorkspacesForScreen(raw, screenName, showAllTags, minCount) {
    if (!raw.available)
        return [];
    const tags = raw.output?.tags;
    if (!tags || tags.length === 0)
        return [];
    if (showAllTags)
        return tags.map(tag => mangoRecord(tag.tag, tag, screenName));
    if (!(minCount > 0))
        return raw.visibleTags.map(index => mangoRecord(index, tags.find(tag => tag.tag === index), screenName));
    // tags always exist per output, so the first minCount are real switch targets
    const indices = raw.visibleTags.slice();
    for (let index = 0; index < Math.min(minCount, tags.length); index++) {
        if (!indices.includes(index))
            indices.push(index);
    }
    return indices.sort((a, b) => a - b).map(index => mangoRecord(index, tags.find(tag => tag.tag === index), screenName));
}

function mangoCurrentTag(raw) {
    if (!raw.available)
        return -1;
    const activeTags = raw.activeTags;
    return activeTags.length > 0 ? activeTags[0] : -1;
}

function mangoScrollWorkspaces(raw, screenName, showAllTags) {
    const current = mangoScrollCurrentTag(raw);
    const tags = !raw.available ? [0] : showAllTags ? Array.from({
        length: raw.tagCount
    }, (_, i) => i) : raw.visibleTags;
    return tags.map(index => ({
                id: index,
                idx: index + 1,
                name: "",
                output: screenName,
                active: index === current,
                placeholder: false
            }));
}

function mangoScrollCurrentTag(raw) {
    if (!raw.available || !raw.output?.tags)
        return 0;
    const activeTags = raw.activeTags;
    return activeTags.length > 0 ? activeTags[0] : 0;
}

function mangoActiveWorkspace(raw, screenName) {
    const activeTags = raw.activeTags;
    if (activeTags.length === 0)
        return null;
    return {
        id: activeTags[0],
        idx: activeTags[0] + 1,
        name: "",
        output: screenName,
        active: true,
        placeholder: false
    };
}

function mangoWindowsOnWorkspace(windows, workspace) {
    // mangoTags are 1-based; workspace.id is 0-based.
    return windows.filter(win => win && win.mangoMonitor === workspace.output && (win.mangoTags || []).includes(workspace.id + 1));
}

function i3Key(ws) {
    return ws.num !== -1 ? ws.num : ws.name;
}

function i3Number(workspace) {
    return typeof workspace.id === "number" ? workspace.id : -1;
}

function i3StripNumber(num, name) {
    if (num === undefined || num === -1 || typeof name !== "string")
        return name ?? "";
    const prefix = num + ":";
    return name.startsWith(prefix) ? name.slice(prefix.length) : name;
}

function i3Order(a, b) {
    const keyA = a.num === -1 ? Number.MAX_SAFE_INTEGER : a.num;
    const keyB = b.num === -1 ? Number.MAX_SAFE_INTEGER : b.num;
    if (keyA !== keyB)
        return keyA - keyB;
    return (a.name ?? "").localeCompare(b.name ?? "");
}

function i3Record(ws) {
    return {
        id: i3Key(ws),
        idx: ws.num !== -1 ? ws.num : null,
        name: i3StripNumber(ws.num, ws.name),
        output: ws.monitor?.name ?? "",
        active: ws.active === true,
        placeholder: false,
        urgent: ws.urgent === true,
        focused: ws.focused === true
    };
}

function i3CurrentKey(raw, screenName, followFocus) {
    const focused = !screenName || followFocus ? raw.workspaces.find(ws => ws.focused === true) : raw.workspaces.find(ws => ws.monitor?.name === screenName && ws.focused === true);
    return focused ? i3Key(focused) : 1;
}

function i3ListedWorkspaces(raw, screenName, followFocus) {
    const workspaces = raw.workspaces;
    if (workspaces.length === 0)
        return [
            {
                num: 1
            }
        ];
    if (!screenName || followFocus)
        return workspaces.slice();
    const onScreen = workspaces.filter(ws => ws.monitor?.name === screenName);
    return onScreen.length > 0 ? onScreen : [
        {
            num: 1
        }
    ];
}

// `workspace number N` creates the workspace on demand, so numbers up to minCount are real switch targets
function i3PersistentWorkspaces(raw, listed, screenName, followFocus, minCount) {
    if (!(minCount > 0))
        return listed;
    const perMonitor = !!screenName && !followFocus;
    const taken = new Set(listed.map(ws => ws.num));
    if (perMonitor)
        raw.workspaces.forEach(ws => ws.num !== -1 && ws.monitor?.name !== screenName && taken.add(ws.num));
    const filled = listed.slice();
    for (let num = 1; num <= minCount; num++) {
        if (taken.has(num))
            continue;
        filled.push({
            num,
            name: String(num),
            monitor: {
                name: perMonitor ? screenName : ""
            }
        });
    }
    return filled;
}

function i3WorkspacesForScreen(raw, screenName, followFocus, minCount) {
    return i3PersistentWorkspaces(raw, i3ListedWorkspaces(raw, screenName, followFocus), screenName, followFocus, minCount).sort(i3Order).map(i3Record);
}

function i3ScrollWorkspaces(raw, screenName, followFocus) {
    const workspaces = raw.workspaces;
    if (workspaces.length === 0)
        return [i3Record({
                num: 1
            })];
    const onScreen = !screenName || followFocus ? workspaces.slice() : workspaces.filter(ws => ws.monitor?.name === screenName);
    return onScreen.length > 0 ? onScreen.sort((a, b) => a.num - b.num).map(i3Record) : [i3Record({
            num: 1
        })];
}

function i3ActiveWorkspace(raw, screenName) {
    const onScreen = raw.workspaces.filter(w => !screenName || w.monitor?.name === screenName);
    const ws = onScreen.find(w => w.focused) || onScreen.find(w => w.active) || onScreen[0];
    if (!ws)
        return null;
    const num = ws.number;
    const name = i3StripNumber(num, ws.name);
    return {
        id: num !== undefined && num !== -1 ? num : name,
        idx: num !== undefined && num > 0 ? num : null,
        name,
        output: ws.monitor?.name ?? screenName,
        active: true,
        placeholder: false
    };
}

function i3WorkspaceFocused(raw, workspace) {
    const focused = raw.workspaces.find(ws => ws.focused === true);
    return focused ? focused.num === i3Number(workspace) : false;
}

function i3WindowsOnWorkspace(windows, workspace) {
    const number = i3Number(workspace);
    return windows.filter(win => win && win.workspace?.num === number);
}

function aqueousRecord(ws, screenName) {
    return {
        id: ws.id,
        idx: ws.number ?? null,
        name: ws.name ?? "",
        output: screenName,
        active: ws.active === true,
        placeholder: false,
        urgent: ws.urgent === true,
        session: ws.aqueousSession
    };
}

function aqueousWorkspacesForScreen(raw, screenName, occupiedOnly, cache) {
    const workspaces = raw.workspaces;
    dropStale(cache, new Set(workspaces.map(ws => String(ws.id))));
    const visible = occupiedOnly ? workspaces.filter(ws => ws.active || raw.toplevels.some(win => win.aqueousWorkspaceId === ws.id)) : workspaces;
    return visible.map(ws => reuse(cache, ws.id, aqueousRecord(ws, screenName)));
}

function aqueousCurrentId(raw) {
    return raw.workspaces.find(ws => ws.active)?.id || "";
}

function aqueousActiveWorkspace(raw, screenName) {
    const ws = raw.workspaces.find(w => w.active);
    return ws ? aqueousRecord(ws, screenName) : null;
}

function aqueousWindowsOnWorkspace(windows, workspace) {
    return windows.filter(win => win && win.aqueousWorkspaceId === workspace.id);
}

function aqueousWorkspaceOccupied(toplevels, workspace) {
    return toplevels.some(win => win.aqueousWorkspaceId === workspace.id);
}

function umbrielRecord(ws) {
    return {
        id: ws.id,
        idx: ws.index,
        name: ws.named === true ? ws.name : "",
        output: ws.output ?? "",
        active: ws.active === true,
        placeholder: false,
        occupied: ws.occupied === true
    };
}

function umbrielCurrentId(workspaces, screenName) {
    return workspaces.find(ws => ws.output === screenName && ws.active)?.id ?? "";
}

function umbrielWorkspacesForScreen(workspaces, screenName, occupiedOnly, cache) {
    dropStale(cache, new Set(workspaces.map(ws => ws.id)));
    const listed = workspaces.filter(ws => ws.output === screenName && (!occupiedOnly || ws.active || ws.occupied));
    return listed.sort((a, b) => a.index - b.index).map(ws => reuse(cache, ws.id, umbrielRecord(ws)));
}

function umbrielActiveWorkspace(workspaces, screenName) {
    const ws = workspaces.find(w => w.output === screenName && w.active);
    return ws ? umbrielRecord(ws) : null;
}

function umbrielWindowsOnWorkspace(windows, workspace) {
    return windows.filter(win => win.workspace === workspace.id).sort((a, b) => a.x - b.x || a.y - b.y || a.id.localeCompare(b.id)).map(win => ({
                id: win.id,
                app_id: win.app_id,
                activated: win.active === true
            }));
}

function umbrielWorkspaceUrgent(windows, workspace) {
    return windows.some(win => win.workspace === workspace.id && win.urgent === true);
}
