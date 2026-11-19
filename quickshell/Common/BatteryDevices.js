.pragma library
.import "settings/BarWidgetDefaults.js" as WidgetDefaults

var SYSTEM_ID = "system";

// Charging or a healthy level is "success"; below twice the low threshold it is
// "caution". A reading of 0 (unknown) falls into "caution" like it always did.
function levelRamp(percentage, charging, lowThreshold, criticalThreshold) {
    if (charging)
        return "success";
    if (percentage > 0 && percentage <= criticalThreshold)
        return "critical";
    if (percentage > 0 && percentage <= lowThreshold)
        return "warning";
    if (percentage <= lowThreshold * 2)
        return "caution";
    return "success";
}

function isLow(percentage, charging, lowThreshold) {
    return percentage > 0 && percentage <= lowThreshold && !charging;
}

function deviceKeys(devices) {
    const seen = {};
    return (devices || []).map(dev => {
        const base = dev.type + ":" + (dev.model ?? "");
        const ordinal = seen[base] ?? 0;
        seen[base] = ordinal + 1;
        return base + ":" + ordinal;
    });
}

function flag(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}

function text(value) {
    return typeof value === "string" ? value : "";
}

// Saved entries with a string id, first occurrence of an id wins. A list that went through a settings
// write is a Qt list wrapper, which Array.isArray rejects.
function savedEntries(saved) {
    const list = saved && typeof saved === "object" && typeof saved.length === "number" ? Array.prototype.slice.call(saved) : WidgetDefaults.DEFAULTS.battery.batteryDevices;
    const seen = {};
    const out = [];
    for (const entry of list) {
        if (!entry || typeof entry !== "object" || typeof entry.id !== "string" || seen[entry.id])
            continue;
        seen[entry.id] = true;
        out.push(entry);
    }
    return out;
}

function normalizeEntry(entry) {
    const on = flag(entry.on, true);
    const lowOnly = flag(entry.lowOnly, false);
    if (entry.id === SYSTEM_ID)
        return { id: SYSTEM_ID, on: on, lowOnly: lowOnly };
    return {
        id: entry.id,
        on: on,
        icon: flag(entry.icon, true),
        percent: flag(entry.percent, true),
        lowOnly: lowOnly,
        name: text(entry.name),
        iconName: text(entry.iconName)
    };
}

function liveById(devices) {
    const byId = {};
    for (const dev of devices || []) {
        if (dev && typeof dev.key === "string" && !byId[dev.key])
            byId[dev.key] = dev;
    }
    return byId;
}

function resolveBarEntries(saved, system, devices) {
    const live = liveById(devices);
    const out = [];
    for (const raw of savedEntries(saved)) {
        const entry = normalizeEntry(raw);
        if (!entry.on)
            continue;
        if (entry.id === SYSTEM_ID) {
            const unknown = system.unknown === true || !(system.percentage > 0);
            const low = system.low === true && !unknown;
            if (entry.lowOnly && !low)
                continue;
            out.push({ id: SYSTEM_ID, kind: "system", iconName: "", percentage: system.percentage, charging: system.charging === true, low: low, unknown: unknown, entry: entry });
            continue;
        }
        const dev = live[entry.id];
        if (!dev)
            continue;
        const unknown = !(dev.percentage > 0);
        const low = dev.low === true && !unknown;
        if (entry.lowOnly && !low)
            continue;
        out.push({ id: entry.id, kind: "device", iconName: dev.icon, percentage: dev.percentage, charging: dev.charging === true, low: low, unknown: unknown, entry: entry });
    }
    return out;
}

function editorRows(saved, devices) {
    const live = liveById(devices);
    const rows = [];
    const listed = {};
    for (const raw of savedEntries(saved)) {
        const entry = normalizeEntry(raw);
        listed[entry.id] = true;
        if (entry.id === SYSTEM_ID) {
            rows.push({ id: SYSTEM_ID, kind: "system", raw: raw, name: "", iconName: "", present: true, on: entry.on, icon: true, percent: true, lowOnly: entry.lowOnly });
            continue;
        }
        const dev = live[entry.id];
        rows.push({
            id: entry.id,
            kind: "device",
            raw: raw,
            name: dev ? dev.name : entry.name,
            iconName: dev ? dev.icon : entry.iconName,
            present: !!dev,
            on: entry.on,
            icon: entry.icon,
            percent: entry.percent,
            lowOnly: entry.lowOnly
        });
    }
    if (!listed[SYSTEM_ID])
        rows.unshift({ id: SYSTEM_ID, kind: "system", name: "", iconName: "", present: true, on: false, icon: true, percent: true, lowOnly: false });
    for (const key of Object.keys(live)) {
        if (listed[key])
            continue;
        const dev = live[key];
        rows.push({ id: key, kind: "device", name: dev.name, iconName: dev.icon, present: true, on: false, icon: true, percent: true, lowOnly: false });
    }
    return rows;
}

// Fields this module does not know stay on the saved entry (`raw`) and survive an edit.
function entryForRow(row) {
    if (row.id === SYSTEM_ID)
        return Object.assign({}, row.raw, { id: SYSTEM_ID, on: flag(row.on, true), lowOnly: flag(row.lowOnly, false) });
    return Object.assign({}, row.raw, {
        id: row.id,
        on: flag(row.on, true),
        icon: flag(row.icon, true),
        percent: flag(row.percent, true),
        lowOnly: flag(row.lowOnly, false),
        name: text(row.name),
        iconName: text(row.iconName)
    });
}
