.pragma library
.import "settings/BarWidgetDefaults.js" as WidgetDefaults

var SYSTEM_ID = "system";

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

// Low never comes with charging (isLow), so the order only matters for hand-made input.
function badgeFor(device) {
    return device.low ? "priority_high" : device.charging ? "bolt" : "";
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

function editorRow(id, raw, dev) {
    const entry = normalizeEntry(raw || { id: id, on: false });
    return {
        id: id,
        kind: id === SYSTEM_ID ? "system" : "device",
        raw: raw,
        name: dev ? dev.name : entry.name || "",
        iconName: dev ? dev.icon : entry.iconName || "",
        present: id === SYSTEM_ID || !!dev,
        on: entry.on,
        icon: entry.icon ?? true,
        percent: entry.percent ?? true,
        lowOnly: entry.lowOnly
    };
}

function editorRows(saved, devices) {
    const live = liveById(devices);
    const rows = [];
    const listed = {};
    for (const raw of savedEntries(saved)) {
        listed[raw.id] = true;
        rows.push(editorRow(raw.id, raw, live[raw.id]));
    }
    if (!listed[SYSTEM_ID])
        rows.unshift(editorRow(SYSTEM_ID, null, null));
    for (const key of Object.keys(live)) {
        if (!listed[key])
            rows.push(editorRow(key, null, live[key]));
    }
    return rows;
}

// Fields this module does not know stay on the saved entry (`raw`) and survive an edit.
function entryForRow(row) {
    return Object.assign({}, row.raw, normalizeEntry(row));
}
