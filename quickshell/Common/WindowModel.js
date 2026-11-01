.pragma library

function touchesEdge(position, positions, x, y, width, height, thickness, screenWidth, screenHeight) {
    switch (position) {
    case positions.top:
        return y < thickness;
    case positions.bottom:
        return y + height > screenHeight - thickness;
    case positions.left:
        return x < thickness;
    case positions.right:
        return x + width > screenWidth - thickness;
    default:
        return false;
    }
}

function sortedWindowFor(sortedToplevels, toplevel) {
    const exact = sortedToplevels.find(window => window === toplevel || window.wayland === toplevel || window.sourceToplevel === toplevel);
    if (exact)
        return exact;
    const titleMatches = sortedToplevels.filter(window => window.appId === toplevel.appId && window.title === toplevel.title);
    return titleMatches.length === 1 ? titleMatches[0] : null;
}

function niriActiveWorkspaceId(allWorkspaces, screenName) {
    const active = allWorkspaces.find(ws => ws.output === screenName && ws.is_active);
    return active ? active.id : null;
}

function niriScreenWorkspaceIds(allWorkspaces, screenName) {
    return new Set(allWorkspaces.filter(ws => ws.output === screenName).map(ws => ws.id));
}

function niriWindowGeometry(win) {
    const tilePos = win.layout?.tile_pos_in_workspace_view;
    const size = win.layout?.window_size || win.layout?.tile_size;
    if (!tilePos || !size)
        return null;
    return {
        x: tilePos[0],
        y: tilePos[1],
        width: size[0],
        height: size[1]
    };
}

function niriFocusedWindow(windows, lastFocusedWindowId, includeLastFocused) {
    const focused = windows.find(w => w.is_focused);
    if (focused)
        return focused;
    if (!includeLastFocused || lastFocusedWindowId === null)
        return null;
    return windows.find(w => w.id === lastFocusedWindowId) || null;
}

function niriActiveWindow(windows, allWorkspaces, sortedToplevels, toplevels, screenName, lastFocusedWindowId, includeLastFocused) {
    const focused = niriFocusedWindow(windows, lastFocusedWindowId, includeLastFocused);
    if (!focused || !niriScreenWorkspaceIds(allWorkspaces, screenName).has(focused.workspace_id))
        return null;
    const sortedMatch = sortedToplevels.find(st => st.niriWindowId === focused.id);
    return sortedMatch?.sourceToplevel || toplevels.find(t => t.appId === focused.app_id && (!focused.title || t.title === focused.title)) || null;
}

function niriActiveWorkspaceOccupied(windows, allWorkspaces, screenName) {
    const workspaceId = niriActiveWorkspaceId(allWorkspaces, screenName);
    return workspaceId !== null && windows.some(w => w.workspace_id === workspaceId);
}

function niriWindowOnActiveWorkspace(windows, allWorkspaces, screenName, currentOutput, focusedWindow) {
    if (currentOutput !== screenName)
        return true;
    if (!focusedWindow)
        return niriActiveWorkspaceOccupied(windows, allWorkspaces, screenName);
    return niriScreenWorkspaceIds(allWorkspaces, screenName).has(focusedWindow.workspace_id);
}

function niriWindowPid(windows, sortedWindow) {
    if (sortedWindow?.niriWindowId === undefined)
        return 0;
    return windows.find(w => w.id === sortedWindow.niriWindowId)?.pid || 0;
}

function niriBarHideForWindows(windows, allWorkspaces, screenName, position, thickness, screenWidth, screenHeight, positions) {
    const workspaceId = niriActiveWorkspaceId(allWorkspaces, screenName);
    if (workspaceId === null)
        return false;
    let hasTiled = false;
    let hasFloatingTouchingBar = false;
    for (const win of windows) {
        if (win.workspace_id !== workspaceId)
            continue;
        if (!win.is_floating) {
            hasTiled = true;
            continue;
        }
        const geometry = niriWindowGeometry(win);
        if (!geometry)
            continue;
        if (touchesEdge(position, positions, geometry.x, geometry.y, geometry.width, geometry.height, thickness, screenWidth, screenHeight))
            hasFloatingTouchingBar = true;
    }
    return hasTiled || hasFloatingTouchingBar;
}

function niriDockOverlap(windows, allWorkspaces, screenName, position, thickness, screenWidth, screenHeight, positions) {
    const workspaceId = niriActiveWorkspaceId(allWorkspaces, screenName);
    if (workspaceId === null)
        return false;
    for (const win of windows) {
        if (win.workspace_id !== workspaceId)
            continue;
        const geometry = niriWindowGeometry(win);
        if (!geometry) {
            if (!win.is_floating)
                return true;
            continue;
        }
        if (touchesEdge(position, positions, geometry.x, geometry.y, geometry.width, geometry.height, thickness, screenWidth, screenHeight))
            return true;
    }
    return false;
}

function hyprlandToplevelFor(hyprToplevels, toplevel) {
    for (const hyprToplevel of hyprToplevels) {
        if (hyprToplevel.wayland === toplevel)
            return hyprToplevel;
    }
    return null;
}

function hyprlandWindowPid(hyprToplevels, toplevel) {
    return hyprToplevels.find(t => t.wayland === toplevel)?.lastIpcObject?.pid || 0;
}

// Same identity as WorkspaceModel.hyprlandKey: Quickshell reports -1 for every named workspace on Hyprland 0.57
function hyprlandWorkspaceKey(ws) {
    return ws.id > 0 ? ws.id : ws.address || ws.name;
}

function hyprlandWindowOnActiveWorkspace(hyprToplevels, focusedWorkspace, toplevel) {
    if (!focusedWorkspace)
        return false;
    const hyprToplevel = hyprToplevels.find(t => t?.wayland === toplevel);
    if (!hyprToplevel || !hyprToplevel.workspace)
        return false;
    return hyprlandWorkspaceKey(hyprToplevel.workspace) === hyprlandWorkspaceKey(focusedWorkspace);
}

function hyprlandSpecialWorkspaceName(hyprToplevels, toplevel) {
    const hyprToplevel = hyprlandToplevelFor(hyprToplevels, toplevel);
    if (!hyprToplevel)
        return "";
    const wsName = String(hyprToplevel.lastIpcObject?.workspace?.name || hyprToplevel.workspace?.name || "");
    if (!wsName.startsWith("special:"))
        return "";
    return wsName.slice("special:".length);
}

function mangoWindowPid(windows, sortedWindow) {
    if (sortedWindow?.mangoWindowId === undefined)
        return 0;
    return windows.find(w => w.id === sortedWindow.mangoWindowId)?.pid || 0;
}

function mangoVisibleWindows(windows, output, screenName) {
    const active = new Set(output?.activeTags || []);
    return windows.filter(win => {
        if (!win || win.monitor !== screenName || win.is_minimized)
            return false;
        if (typeof win.is_visible === "boolean")
            return win.is_visible;
        return active.size === 0 || (win.tags || []).some(t => active.has(t));
    });
}

function mangoEdgeOverlap(windows, output, screenName, position, thickness, screenWidth, screenHeight, positions) {
    const monX = output?.x ?? 0;
    const monY = output?.y ?? 0;
    return mangoVisibleWindows(windows, output, screenName).some(win => touchesEdge(position, positions, (win.x ?? 0) - monX, (win.y ?? 0) - monY, win.width ?? 0, win.height ?? 0, thickness, screenWidth, screenHeight));
}

function mangoMaximizedOnScreen(windows, output, screenName) {
    return mangoVisibleWindows(windows, output, screenName).some(win => win.is_maximized || win.is_fullscreen);
}

function aqueousActiveWindow(focusedWindow, screenName) {
    if (!focusedWindow)
        return null;
    return screenName === null || focusedWindow.screens.some(s => s.name === screenName) ? focusedWindow : null;
}
