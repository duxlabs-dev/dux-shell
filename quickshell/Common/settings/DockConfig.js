.pragma library

var EDGES = ["top", "bottom", "left", "right"];
var MAGNIFICATION_PROFILES = ["parabolic", "cosine", "gaussian"];
var DEFAULT_MAGNIFICATION_PROFILE = "parabolic";

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function create(id, name) {
    return {
        id: id,
        name: name,
        enabled: false,
        screenPreferences: ["all"],
        showOnLastDisplay: true,
        position: 1,
        mode: "compact",
        taskbarAlign: "center",
        widgetExpansion: "popout",
        iconSize: 42,
        spacing: 8,
        itemSpacing: 8,
        margin: 8,
        bottomGap: 0,
        transparency: 1,
        followInterfaceStyle: true,
        autoHide: false,
        smartAutoHide: false,
        useOverlayLayer: false,
        editOnRightClick: false,
        showOnFullscreen: false,
        openOnOverview: false,
        groupByApp: false,
        separatePinnedAndRunningApps: false,
        restoreSpecialWorkspaceOnClick: false,
        isolateDisplays: false,
        indicatorStyle: "circle",
        borderEnabled: false,
        borderColor: "surfaceText",
        borderOpacity: 1,
        borderThickness: 1,
        launcherEnabled: true,
        launcherLogoMode: "os",
        launcherLogoCustomPath: "",
        launcherLogoColorOverride: "",
        launcherLogoSizeOffset: 0,
        launcherLogoBrightness: 0.5,
        launcherLogoContrast: 1,
        maxVisibleApps: 0,
        maxVisibleRunningApps: 0,
        showOverflowBadge: true,
        showTrash: false,
        trashFileManager: "default",
        trashCustomCommand: "",
        magnification: false,
        magnificationScale: 130,
        magnificationProfile: DEFAULT_MAGNIFICATION_PROFILE,
        magnificationExpand: false,
        order: [],
        widgets: [
            {
                id: id + "_launcher",
                widgetId: "dockLauncher",
                enabled: true
            },
            {
                id: id + "_apps",
                widgetId: "appsDock",
                enabled: true
            },
            {
                id: id + "_trash",
                widgetId: "dockTrash",
                enabled: true
            }
        ]
    };
}

function bounded(value, fallback, minimum, maximum) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.max(minimum, Math.min(maximum, number)) : fallback;
}

function normalize(configs, presets) {
    if (!Array.isArray(configs))
        return [];
    const ids = new Set();
    return configs.filter(config => {
        if (!config || typeof config.id !== "string" || !config.id || ids.has(config.id))
            return false;
        ids.add(config.id);
        return true;
    }).map(config => {
        const defaults = Object.assign(create(config.id, config.id), presets);
        const result = Object.assign({}, defaults, clone(config));
        result.name = typeof config.name === "string" && config.name.trim() ? config.name : config.id;
        result.position = Number.isInteger(config.position) && config.position >= 0 && config.position < 4 ? config.position : 1;
        result.mode = config.mode === "taskbar" ? "taskbar" : "compact";
        result.taskbarAlign = ["start", "center", "end"].includes(config.taskbarAlign) ? config.taskbarAlign : "center";
        result.widgetExpansion = config.widgetExpansion === "inline" ? "inline" : "popout";
        result.iconSize = bounded(result.iconSize, defaults.iconSize, 16, 96);
        result.itemSpacing = bounded(result.itemSpacing, defaults.itemSpacing, 0, 32);
        for (const key of ["spacing", "margin"])
            result[key] = bounded(result[key], defaults[key], 0, 128);
        result.bottomGap = bounded(result.bottomGap, defaults.bottomGap, -128, 128);
        for (const key of ["transparency", "borderOpacity", "launcherLogoBrightness"])
            result[key] = bounded(result[key], 1, 0, 1);
        for (const key of ["maxVisibleApps", "maxVisibleRunningApps"])
            result[key] = Math.floor(bounded(result[key], 0, 0, 100));
        result.magnificationScale = bounded(result.magnificationScale, defaults.magnificationScale, 105, 160);
        result.magnificationProfile = MAGNIFICATION_PROFILES.includes(result.magnificationProfile) ? result.magnificationProfile : defaults.magnificationProfile;
        for (const key of Object.keys(defaults)) {
            if (typeof defaults[key] === "boolean")
                result[key] = result[key] === true;
        }
        result.screenPreferences = Array.isArray(config.screenPreferences) ? config.screenPreferences.filter(pref => (typeof pref === "string" && pref) || (pref && typeof pref === "object" && (typeof pref.name === "string" || typeof pref.model === "string"))).map(pref => typeof pref === "string" ? pref : clone(pref)) : ["all"];
        const widgetIds = new Set();
        result.widgets = (Array.isArray(config.widgets) ? config.widgets : result.widgets).filter(widget => widget && (typeof widget === "string" || typeof widget.widgetId === "string" || typeof widget.id === "string")).map((widget, index) => {
            const item = typeof widget === "string" ? {
                widgetId: widget
            } : clone(widget);
            item.widgetId = item.widgetId || item.id;
            let id = typeof item.id === "string" && item.id ? item.id : config.id + "_widget_" + index;
            while (widgetIds.has(id))
                id += "_";
            item.id = id;
            widgetIds.add(id);
            item.enabled = item.enabled !== false;
            return item;
        });
        result.widgets = withAppSlots(result.widgets, config.id);
        result.order = Array.isArray(config.order) ? [...new Set(config.order.filter(id => typeof id === "string"))] : [];
        delete result.launcherPosition;
        delete result.thickness;
        return result;
    });
}

function matches(config, screen) {
    return config.screenPreferences.some(pref => {
        if (typeof pref === "string")
            return pref === screen.name || !!(screen.model && pref === screen.model);
        return pref.name === screen.name || !!(screen.model && pref.model === screen.model);
    });
}

function pick(eligible, screen, screens, screenMatches) {
    const explicit = eligible.find(config => (screenMatches || matches)(config, screen));
    if (explicit)
        return explicit;
    const fallback = eligible.find(config => config.screenPreferences.includes("all"));
    if (fallback)
        return fallback;
    if (screens?.length !== 1)
        return null;
    return eligible.find(config => config.showOnLastDisplay && config.screenPreferences.length > 0) || null;
}

// One dock may claim each edge of a screen, so resolution runs per edge rather than per screen.
// An enabled dock owns its edge; a dock shown only in the overview takes an edge nothing else holds.
function resolveEdge(configs, screen, screens, edge, screenMatches) {
    if (!screen)
        return null;
    const onEdge = configs.filter(config => EDGES[config.position] === edge);
    return pick(onEdge.filter(config => config.enabled), screen, screens, screenMatches) ?? pick(onEdge.filter(config => config.openOnOverview), screen, screens, screenMatches);
}

function resolveAll(configs, screen, screens, screenMatches) {
    return EDGES.map(edge => resolveEdge(configs, screen, screens, edge, screenMatches)).filter(Boolean);
}

function resolve(configs, screen, screens, screenMatches) {
    return resolveAll(configs, screen, screens, screenMatches)[0] ?? null;
}

// Options the redesign gave a new default. A settings.json written before it stored only
// changed values, so the old default is what the user is actually running today.
var LEGACY_DEFAULTS = {
    iconSize: 40,
    spacing: 4,
    margin: 0,
    bottomGap: 0,
    launcherEnabled: false,
    launcherLogoMode: "apps"
};

function migrate(settings) {
    if (Array.isArray(settings.dockConfigs))
        return normalize(settings.dockConfigs);
    const config = Object.assign(create("dock", "Dock"), LEGACY_DEFAULTS);
    config.enabled = settings.showDock === true;
    const preferences = settings.screenPreferences?.dock;
    config.screenPreferences = Array.isArray(preferences) && preferences.length ? clone(preferences) : ["all"];
    for (const option of Object.keys(config)) {
        const key = "dock" + option[0].toUpperCase() + option.slice(1);
        if (settings[key] !== undefined)
            config[option] = clone(settings[key]);
    }
    config.itemSpacing = Math.min(8, Math.max(4, config.iconSize * 0.08));
    for (const key of ["transparency", "borderOpacity", "launcherLogoBrightness", "launcherLogoContrast"]) {
        if (config[key] > 1)
            config[key] /= 100;
    }
    config.showOnLastDisplay = settings.showOnLastDisplay?.dock ?? true;
    return normalize([config]);
}

function move(items, from, to) {
    if (from < 0 || from >= items.length || to < 0 || to >= items.length || from === to)
        return items;
    const result = items.slice();
    result.splice(to, 0, result.splice(from, 1)[0]);
    return result;
}

function allocation(sizes, flexible, available, spacing) {
    const fixed = sizes.reduce((sum, size, i) => sum + (flexible[i] ? 0 : Math.max(0, size)), 0);
    const gaps = Math.max(0, sizes.length - 1) * spacing;
    const count = flexible.filter(Boolean).length;
    const share = count ? Math.max(0, available - fixed - gaps) / count : 0;
    return sizes.map((size, i) => flexible[i] ? share : Math.max(0, size));
}

var APP_SLOT_TYPES = {
    dockLauncher: "launcher",
    dockTrash: "trash"
};

function withAppSlots(widgets, id) {
    const result = widgets.filter((widget, index) => !(widget.widgetId in APP_SLOT_TYPES) || widgets.findIndex(other => other.widgetId === widget.widgetId) === index);
    const apps = () => result.findIndex(widget => widget.widgetId === "appsDock");
    if (!result.some(widget => widget.widgetId === "dockLauncher"))
        result.splice(Math.max(0, apps()), 0, {
            id: id + "_launcher",
            widgetId: "dockLauncher",
            enabled: true
        });
    if (!result.some(widget => widget.widgetId === "dockTrash"))
        result.splice(apps() < 0 ? result.length : apps() + 1, 0, {
            id: id + "_trash",
            widgetId: "dockTrash",
            enabled: true
        });
    return result;
}

function isPinnedApp(app) {
    return app.isPinned === true && app.type !== "launcher" && typeof app.appId === "string" && app.appId !== "";
}

function pinUnit(app) {
    return "pin:" + app.appId;
}

function pinUnits(apps) {
    return apps.filter(isPinnedApp).map(pinUnit);
}

// The saved order places widgets and pinned apps; the apps widget stands for the running windows,
// which keep the compositor's order. Pin slots are refilled in pin order so a plain pin drag still wins.
function unitList(widgets, pins, order) {
    const widgetIds = widgets.map(widget => widget.id);
    const known = new Set(widgetIds.concat(pins));
    const result = [];
    for (const id of order || []) {
        if (known.has(id) && !result.includes(id))
            result.push(id);
    }
    for (const id of widgetIds) {
        if (!result.includes(id))
            result.push(id);
    }
    const remaining = pins.slice();
    for (let i = 0; i < result.length; i++) {
        if (result[i].startsWith("pin:"))
            result[i] = remaining.shift();
    }
    if (remaining.length === 0)
        return result;
    const lastPin = result.map(id => id.startsWith("pin:")).lastIndexOf(true);
    const apps = result.indexOf(widgets.find(widget => widget.widgetId === "appsDock")?.id);
    result.splice(lastPin >= 0 ? lastPin + 1 : apps >= 0 ? apps : result.length, 0, ...remaining);
    return result;
}

function surfaceItems(widgets, apps, order) {
    const items = [];
    const byId = new Map(widgets.map(widget => [widget.id, widget]));
    const appsWidget = widgets.find(widget => widget.widgetId === "appsDock" && widget.enabled !== false);
    const slotTypes = Object.values(APP_SLOT_TYPES);
    const push = (widget, unitId, app, index) => items.push({
            id: widget.id + ":" + app.uniqueKey,
            unitId,
            widgetId: "application",
            appData: app,
            appIndex: index
        });
    for (const id of unitList(widgets, pinUnits(apps), order)) {
        if (id.startsWith("pin:")) {
            if (!appsWidget)
                continue;
            apps.forEach((app, index) => {
                if (isPinnedApp(app) && pinUnit(app) === id && !app.isInOverflow)
                    push(appsWidget, id, app, index);
            });
            continue;
        }
        const widget = byId.get(id);
        if (!widget || widget.enabled === false)
            continue;
        const slotType = APP_SLOT_TYPES[widget.widgetId];
        if (!slotType && widget.widgetId !== "appsDock") {
            items.push(widget);
            continue;
        }
        apps.forEach((app, index) => {
            if (slotType) {
                if (app.type === slotType)
                    push(widget, widget.id, app, index);
                return;
            }
            if (app.isInOverflow || isPinnedApp(app) || slotTypes.includes(app.type))
                return;
            if (app.type === "separator" && !isPinnedApp(items[items.length - 1]?.appData ?? {}))
                return;
            push(widget, widget.id, app, index);
        });
    }
    return items;
}

// Maps the pin units of a new order back onto the raw pin list, which the strip keeps in the same sequence.
function reorderPins(pins, apps, order) {
    const pinned = apps.filter(isPinnedApp);
    if (pinned.length !== pins.length)
        return null;
    const next = order.filter(id => id.startsWith("pin:")).map(id => pins[pinned.findIndex(app => pinUnit(app) === id)]).filter(pin => pin !== undefined);
    if (next.length !== pins.length || next.every((pin, index) => pin === pins[index]))
        return null;
    return next;
}

function unitOf(item) {
    return item.unitId ?? item.id;
}

function units(items) {
    const ids = [];
    for (const item of items) {
        const id = unitOf(item);
        if (ids[ids.length - 1] !== id)
            ids.push(id);
    }
    return ids;
}

function unitOrder(items, from, to) {
    const ids = units(items);
    const order = move(ids, ids.indexOf(from), ids.indexOf(to));
    const result = [];
    for (const id of order) {
        items.forEach((item, index) => {
            if (unitOf(item) === id)
                result.push(index);
        });
    }
    return result;
}

// The leading edge decides, so a wide unit swaps with a narrow neighbour at the dock's end.
function unitTarget(spans, id, offset) {
    const from = spans.findIndex(span => span.id === id);
    if (from < 0)
        return id;
    const middle = span => (span.start + span.end) / 2;
    let target = from;
    for (let i = from + 1; i < spans.length && spans[from].end + offset > middle(spans[i]); i++)
        target = i;
    for (let i = from - 1; i >= 0 && spans[from].start + offset < middle(spans[i]); i--)
        target = i;
    return spans[target].id;
}

// Lane kept clear beside icons for running indicators.
function indicatorLane(config) {
    return Math.max(8, Math.round(config.iconSize * 0.18));
}

// Thickness is derived, never set: content decides it and padding surrounds it.
function effectiveThickness(config) {
    return config.iconSize + config.spacing * 2;
}

// Proximity magnification influence radius per profile curve.
function magnificationRadius(baseSize, profile) {
    const size = baseSize > 0 ? baseSize : 42;
    if (profile === "parabolic")
        return size * 1.8;
    if (profile === "gaussian")
        return size * 2.2;
    return size * 2.5;
}

// Magnification scale decay factor (1.0 at dist=0, tapering to 0.0 at dist>=radius).
function magnificationFactor(dist, radius, profile) {
    if (dist >= radius)
        return 0;
    const u = dist / radius;
    if (profile === "cosine")
        return 0.5 * (1 + Math.cos(Math.PI * u));
    if (profile === "gaussian")
        return (Math.exp(-3 * u * u) - Math.exp(-3)) / (1 - Math.exp(-3));
    return 1 - (u * u);
}
