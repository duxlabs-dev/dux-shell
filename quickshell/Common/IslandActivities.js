.pragma library

var IPC_ACTIVITY_TTL = 8 * 60 * 60 * 1000;
var MAX_ACTIVITY_TTL = 24 * 60 * 60 * 1000;

var CLICK_ACTIVITIES = ["live", "home", "media", "clipboard", "controlcenter", "notificationcenter", "weather", "launcher", "wallpaper"];

// Island colours are Theme roles, never free colours: fill and on are Theme property names.
var ROLE_COLORS = {
    "hostSurface": {fill: "hostSurface", on: "surfaceText"},
    "cardSurface": {fill: "cardSurface", on: "surfaceText"},
    "chipSurface": {fill: "chipSurface", on: "surfaceText"},
    "chipSurfaceNested": {fill: "chipSurfaceNested", on: "surfaceText"},
    "primaryContainer": {fill: "primaryContainer", on: "onPrimaryContainer"},
    "secondaryContainer": {fill: "secondaryContainer", on: "onSecondaryContainer"},
    "tertiaryContainer": {fill: "tertiaryContainer", on: "onTertiaryContainer"},
    "error": {fill: "errorContainer", on: "onErrorContainer"},
    // Theme has no warning container; tint a chip the way Theme derives missing containers.
    "warning": {fill: "chipSurface", tint: "warning", tintRatio: 0.35, on: "surfaceText"}
};
// "" keeps the island's own surface; the settings dropdown offers these in order.
var SURFACE_ROLES = ["", "hostSurface", "cardSurface", "chipSurface", "chipSurfaceNested", "primaryContainer", "secondaryContainer", "tertiaryContainer"];
var ACTIVITY_ROLES = SURFACE_ROLES.slice(1).concat(["error", "warning"]);

function surfaceRole(value) {
    return SURFACE_ROLES.indexOf(value) >= 0 ? value : "";
}

function activityRole(value) {
    return ACTIVITY_ROLES.indexOf(value) >= 0 ? value : "";
}

function roleColors(role) {
    return ROLE_COLORS[role] || null;
}

function severityRole(severity) {
    return severity === "error" || severity === "warning" ? severity : "";
}

function validId(value) {
    return typeof value === "string" && /^[a-zA-Z0-9_.:-]{1,64}$/.test(value);
}

function text(value, limit) {
    return typeof value === "string" ? value.slice(0, limit) : "";
}

function priorityFor(priorityClass, priority) {
    if (typeof priority === "number" && isFinite(priority))
        return Math.max(-100, Math.min(100, priority));
    switch (priorityClass) {
    case "critical":
        return 100;
    case "urgent":
        return 90;
    case "high":
        return 60;
    case "low":
        return -20;
    default:
        return 0;
    }
}

function normalize(source, id, payload, now) {
    if (!validId(source) || !validId(id) || !payload || typeof payload !== "object" || Array.isArray(payload))
        return null;
    const title = text(payload.title, 256);
    if (!title)
        return null;
    const duration = payload.duration === undefined ? 5000 : payload.duration;
    if (typeof duration !== "number" || !isFinite(duration) || duration < 0 || duration > 3600000)
        return null;
    const persistent = payload.persistent === true || duration === 0;
    const ttl = payload.ttl === undefined ? 0 : payload.ttl;
    if (typeof ttl !== "number" || !isFinite(ttl) || ttl < 0 || ttl > MAX_ACTIVITY_TTL)
        return null;
    const position = ["left", "center", "right"].indexOf(payload.position) >= 0 ? payload.position : payload.category === "status" ? "right" : "left";
    return {
        source: source,
        id: id,
        title: title,
        compact: payload.compact === "icon" ? "icon" : "label",
        persistent: persistent,
        dismissible: payload.dismissible === true,
        position: position,
        stableCompact: payload.stableCompact === "label" ? "label" : "icon",
        duration: duration,
        durationSpecified: payload.duration !== undefined,
        announce: payload.announce !== false && duration > 0,
        clickActivity: CLICK_ACTIVITIES.indexOf(payload.clickActivity) >= 0 ? payload.clickActivity : "live",
        clickAction: validId(payload.clickAction) ? payload.clickAction : "",
        clickTarget: validId(payload.clickTarget) ? payload.clickTarget : "",
        clickMethod: validId(payload.clickMethod) ? payload.clickMethod : "",
        subtitle: text(payload.subtitle, 512),
        body: text(payload.body, 4096),
        value: text(payload.value, 128),
        status: text(payload.status, 256),
        icon: text(payload.icon, 128) || "notifications",
        iconAnimation: ["wiggle", "pulse", "spin"].indexOf(payload.iconAnimation) >= 0 ? payload.iconAnimation : "",
        image: text(payload.image, 2048),
        background: activityRole(payload.background),
        expandedBackground: activityRole(payload.expandedBackground),
        foreground: activityRole(payload.foreground),
        severity: ["error", "warning"].indexOf(payload.severity) >= 0 ? payload.severity : "",
        progress: typeof payload.progress === "number" && isFinite(payload.progress) ? Math.max(0, Math.min(1, payload.progress)) : -1,
        priorityClass: ["low", "normal", "high", "urgent", "critical"].indexOf(payload.priorityClass) >= 0 ? payload.priorityClass : "normal",
        priority: priorityFor(payload.priorityClass, payload.priority),
        preemption: payload.preemption === "higher" ? "higher" : "never",
        screen: text(payload.screen, 128),
        barId: text(payload.barId, 128),
        actions: Array.isArray(payload.actions) ? payload.actions.filter(action => action && validId(action.id) && typeof action.label === "string" && action.label.length > 0).slice(0, 3).map(action => ({id: action.id, label: text(action.label, 64), role: ["primary", "destructive"].indexOf(action.role) >= 0 ? action.role : "secondary", enabled: action.enabled !== false, pending: action.pending === true})) : [],
        ttl: ttl,
        expiresAt: persistent ? (ttl > 0 ? now + ttl : 0) : now + duration,
        updatedAt: now
    };
}

function matches(entry, screen, barId, excludedSources) {
    return (!entry.screen || entry.screen === screen) && (!entry.barId || entry.barId === barId) && excludedSources.indexOf(entry.source) < 0;
}

function identity(entry) {
    return entry ? JSON.stringify([entry.source, entry.id]) : "";
}

function stableEntries(entries, screen, barId, excludedSources, overrides, limit) {
    overrides = overrides || {};
    return entries.filter(entry => entry.persistent && matches(entry, screen, barId, excludedSources)).map(entry => {
        const override = overrides[entry.source] || {};
        const clickOverride = CLICK_ACTIVITIES.indexOf(override.clickActivity) >= 0;
        return Object.assign({}, entry, {
            position: ["left", "center", "right"].indexOf(override.position) >= 0 ? override.position : entry.position,
            stableCompact: ["icon", "label"].indexOf(override.compact) >= 0 ? override.compact : entry.stableCompact,
            clickActivity: clickOverride ? override.clickActivity : entry.clickActivity,
            clickAction: clickOverride ? "" : entry.clickAction,
            clickTarget: clickOverride ? "" : entry.clickTarget
        });
    }).sort((a, b) => b.priority - a.priority || (a.createdAt ?? a.updatedAt) - (b.createdAt ?? b.updatedAt) || (a.createdOrder ?? 0) - (b.createdOrder ?? 0)).slice(0, Math.max(0, Math.min(6, limit)));
}

function enqueue(queue, entry) {
    const key = identity(entry);
    const index = queue.findIndex(item => identity(item) === key);
    if (index >= 0) {
        const update = entry.restartPreview ? entry : Object.assign({}, entry, {duration: queue[index].duration});
        return queue.map((item, i) => i === index ? update : item);
    }
    if (!entry.announce || queue.length >= 64)
        return queue;
    return queue.concat([entry]);
}

function nextEvent(queue) {
    return queue.reduce((best, entry) => !best || entry.priority > best.priority ? entry : best, null);
}

function upsert(entries, entry, now) {
    const previous = entries.find(item => item.source === entry.source && item.id === entry.id && (!item.expiresAt || item.expiresAt > now));
    entry.createdAt = previous?.createdAt ?? previous?.updatedAt ?? now;
    entry.createdOrder = previous?.createdOrder ?? entries.reduce((order, item) => Math.max(order, item.createdOrder ?? 0), 0) + 1;
    const retained = entries.filter(item => (!item.expiresAt || item.expiresAt > now) && item !== previous);
    if (retained.length >= 64)
        return null;
    return retained.concat([entry]);
}

function select(entries, screen, barId, excludedSources) {
    return entries.filter(entry => (!entry.screen || entry.screen === screen) && (!entry.barId || entry.barId === barId) && excludedSources.indexOf(entry.source) < 0).reduce((best, entry) => !best || entry.priority > best.priority || (entry.priority === best.priority && entry.updatedAt >= best.updatedAt) ? entry : best, null);
}

function nextExpiry(entries) {
    return entries.reduce((next, entry) => entry.expiresAt && (!next || entry.expiresAt < next) ? entry.expiresAt : next, 0);
}

function notificationTitle(template, info) {
    return text(template, 512).replace(/\{(summary|body|appName)\}/g, function(match, key) {
        return text(info[key], 512);
    }).slice(0, 512);
}

function canInvoke(entry, action) {
    if (!entry)
        return false;
    const button = entry.actions.find(item => item.id === action);
    if (button)
        return button.enabled !== false && !button.pending;
    return entry.clickAction === action;
}

function validPayloadSize(payload) {
    const limit = 64 * 1024;
    let bytes = 0;
    for (let i = 0; i < payload.length; i++) {
        const code = payload.charCodeAt(i);
        if (code >= 0xd800 && code <= 0xdbff && i + 1 < payload.length && payload.charCodeAt(i + 1) >= 0xdc00 && payload.charCodeAt(i + 1) <= 0xdfff) {
            bytes += 4;
            i++;
        } else {
            bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : 3;
        }
        if (bytes > limit)
            return false;
    }
    return true;
}
