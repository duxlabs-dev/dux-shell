.pragma library

function isFullscreenOnScreen(screenName, workspaces, windows, toplevels) {
    if (!screenName || !workspaces || !windows || !toplevels)
        return false;

    const workspace = workspaces.find(ws => ws.output === screenName && ws.is_active);
    if (!workspace || workspace.active_window_id === null || workspace.active_window_id === undefined)
        return false;

    const window = windows.find(w => w.id === workspace.active_window_id && w.workspace_id === workspace.id);
    if (!window || !window.app_id)
        return false;

    const matches = toplevels.filter(t => t && t.appId === window.app_id
        && (t.title || "") === (window.title || "")
        && t.screens?.some(screen => screen.name === screenName));

    if (window.is_focused) {
        const focused = matches.filter(t => t.activated);
        if (focused.length === 1)
            return !!focused[0].fullscreen;
    }

    // Niri IPC and wlr-foreign-toplevel have no shared window identifier.
    // Do not guess when equal titles on the same output make the match ambiguous.
    const workspaceIds = new Set(workspaces.filter(ws => ws.output === screenName).map(ws => ws.id));
    const sameWindows = windows.filter(w => workspaceIds.has(w.workspace_id)
        && w.app_id === window.app_id && (w.title || "") === (window.title || ""));
    if (sameWindows.length !== 1 || matches.length !== 1)
        return false;

    return !!matches[0].fullscreen;
}
