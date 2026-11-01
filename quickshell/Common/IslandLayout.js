.pragma library

var DEFAULT_HOME_LAYOUT = [
    {id: "workspaces", enabled: false},
    {id: "media", enabled: true},
    {id: "clock", enabled: true},
    {id: "weather", enabled: false},
    {id: "status", enabled: false},
    {id: "volume", enabled: false},
    {id: "brightness", enabled: false},
    {id: "notifications", enabled: true},
    {id: "privacy", enabled: true}
];

var GROUP_WIDGETS = {
    workspaces: "workspaceSwitcher", media: "music", clock: "clock", weather: "weather",
    status: "battery", volume: "controlCenterButton", brightness: "controlCenterButton",
    notifications: "notificationButton", privacy: "privacyIndicator"
};

function widgets(config) {
    return (config?.centerWidgets || []).filter(entry => (typeof entry === "string" ? entry : entry.id) !== "island").map(entry => {
        const widget = Object.assign({background: false}, typeof entry === "string" ? {id: entry, enabled: true} : entry);
        return widget.id === "music" ? Object.assign({mediaStyle: "activity", mediaTitleMode: "changes", mediaAlwaysVisible: true}, widget) : widget;
    });
}

function migrate(config, includeDefault = false) {
    if (!config?.island || config.dot || (!Array.isArray(config.islandHomeLayout) && !includeDefault))
        return;
    const original = (config.leftWidgets || []).concat(config.centerWidgets || [], config.rightWidgets || []);
    const result = [];
    const layout = Array.isArray(config.islandHomeLayout) ? config.islandHomeLayout : DEFAULT_HOME_LAYOUT;
    for (const group of layout) {
        const id = group.id === "status" && config.islandHomeStatusContent === "connectivity" ? "controlCenterButton" : GROUP_WIDGETS[group.id];
        if (!id || group.enabled === false || result.some(entry => entry.id === id))
            continue;
        const old = original.find(entry => (typeof entry === "string" ? entry : entry.id) === id);
        const entry = Object.assign({}, typeof old === "object" ? old : {}, {id: id, enabled: true});
        if (id === "music") {
            Object.assign(entry, {
                mediaStyle: "activity", mediaTitleMode: "changes", mediaAlwaysVisible: true,
                mediaArtworkCircular: config.islandMediaArtworkCircular ?? true,
                mediaVisualizerIdle: config.islandMediaVisualizerIdle ?? false,
                mediaShowCoverArt: config.islandMediaAlwaysVisible ?? true
            });
        }
        if (id === "clock" && config.islandHomeClockDisplay)
            entry.clockCompactMode = config.islandHomeClockDisplay === "time";
        result.push(entry);
    }
    const mapped = Object.values(GROUP_WIDGETS);
    for (const entry of config.centerWidgets || []) {
        const id = typeof entry === "string" ? entry : entry.id;
        if (id !== "island" && !mapped.includes(id) && !result.some(item => item.id === id))
            result.push(typeof entry === "string" ? {id: id, enabled: true} : Object.assign({}, entry));
    }
    config.centerWidgets = result;
    delete config.islandHomeLayout;
}

function groupForWidget(id) {
    for (const group of ["workspaces", "media", "clock", "weather", "status", "notifications", "privacy"]) {
        if (GROUP_WIDGETS[group] === id)
            return group;
    }
    return id;
}
