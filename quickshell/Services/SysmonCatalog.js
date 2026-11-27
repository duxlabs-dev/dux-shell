.pragma library
.import "../Common/Format.js" as Format
.import "SysmonDevices.js" as Devices

const V = (id, kind, warn, danger) => ({
    id,
    kind,
    warn,
    danger
});

const TYPES = {
    cpu: [V("usage", "pct", 60, 80), V("temp", "temp", 69, 85), V("clock", "clock", null, null)],
    memory: [V("used", "pct", 75, 90), V("swap", "pct", 50, 80)],
    gpu: [V("usage", "pct", 70, 90), V("temp", "temp", 65, 80), V("vram", "pct", 80, 92), V("power", "power", null, null)],
    disk: [V("space", "pct", 75, 90), V("read", "rate", null, null), V("write", "rate", null, null)],
    net: [V("down", "rate", null, null), V("up", "rate", null, null)]
};

// The values behind the bar widget's option rows, in the order the rows list them.
const barChoices = {
    style: ["icon", "meter", "ring", "graph"],
    label: ["icon", "name", "both", "none"],
    separator: ["gap", "line", "dot", "separate"],
    popout: ["compact", "processes", "device", "overview"]
};

const maxMetrics = 16;
const maxSuffix = 128;
const hasControl = s => /[\u0000-\u001f\u007f]/.test(s);

function typeOf(deviceKey) {
    if (typeof deviceKey !== "string")
        return "";
    const m = /^(cpu|memory|gpu|disk|net)(?::([\s\S]*))?$/.exec(deviceKey);
    if (!m)
        return "";
    const suffix = m[2];
    if (suffix === undefined)
        return m[1] === "cpu" || m[1] === "memory" || m[1] === "disk" || m[1] === "net" ? m[1] : "";
    if (m[1] === "cpu" || m[1] === "memory")
        return "";
    if (suffix.length === 0 || suffix.length > maxSuffix || hasControl(suffix))
        return "";
    return m[1];
}

function valueDef(type, id) {
    const list = TYPES[type] || [];
    for (let i = 0; i < list.length; i++) {
        if (list[i].id === id)
            return list[i];
    }
    return null;
}

function level(type, id, value) {
    const def = valueDef(type, id);
    if (!def || typeof value !== "number" || def.danger === null)
        return 0;
    if (value > def.danger)
        return 2;
    return value > def.warn ? 1 : 0;
}

function formatValue(kind, value, opts) {
    if (typeof value !== "number" || !isFinite(value))
        return "—";
    const o = opts || {};
    switch (kind) {
    case "pct":
        return Math.round(value) + "%";
    case "temp":
        return Math.round(value) + "°";
    case "clock":
        return (value / 1000).toFixed(1) + (o.short ? "" : " GHz");
    case "power":
        return Math.round(value) + " W";
    case "rate":
        return o.short ? Format.formatRateCompact(value, true, true) : Format.formatRate(value);
    }
    return "";
}

// The device key of the card a migrated GPU widget meant: the list index when its PCI id still matches, else the first card with that id.
// A PCI id no card has keeps its own key, which the widget shows as missing. Empty while the list is.
function legacyGpuKey(entry, gpus) {
    const list = Array.isArray(gpus) ? gpus : [];
    const index = entry && Number.isInteger(entry.selectedGpuIndex) && entry.selectedGpuIndex >= 0 ? entry.selectedGpuIndex : 0;
    const want = entry && typeof entry.pciId === "string" ? entry.pciId.toLowerCase() : "";
    const same = g => String(g.pciId || "").toLowerCase() === want;
    const card = want ? (list[index] && same(list[index]) ? list[index] : list.find(same)) : (list[index] || list[0]);
    const key = card ? "gpu:" + Devices.gpuSlot(card) : list.length > 0 && want ? "gpu:" + entry.pciId : "";
    return typeOf(key) === "gpu" ? key : "";
}

// Arrays that went through a QML var property or signal come back as sequences, which Array.isArray rejects.
function listOf(v) {
    return v && typeof v === "object" && typeof v.length === "number" ? Array.from(v) : null;
}

function normalizeMetrics(input) {
    const list = listOf(input);
    if (!list)
        return [];
    const out = [];
    for (let i = 0; i < list.length && out.length < maxMetrics; i++) {
        const m = list[i];
        if (!m || typeof m !== "object" || listOf(m))
            continue;
        const type = typeOf(m.device);
        if (!type)
            continue;
        const vals = [];
        const given = listOf(m.vals) || [];
        for (let j = 0; j < given.length; j++) {
            const v = given[j];
            if (typeof v === "string" && valueDef(type, v) && vals.indexOf(v) < 0)
                vals.push(v);
        }
        if (vals.length === 0)
            vals.push(TYPES[type][0].id);
        const metric = {
            device: m.device,
            vals,
            graph: m.graph === true,
            on: m.on !== false
        };
        if (type === "disk" && typeof m.mount === "string" && m.mount.charAt(0) === "/" && !hasControl(m.mount))
            metric.mount = m.mount;
        if ((type === "memory" || type === "gpu") && m.percent === false)
            metric.percent = false;
        if (type === "disk" && Number.isInteger(m.diskMode) && m.diskMode >= 1 && m.diskMode <= 3)
            metric.diskMode = m.diskMode;
        if (type === "net") {
            if (m.compact === true)
                metric.compact = true;
            if (m.hideIdle === true)
                metric.hideIdle = true;
        }
        out.push(metric);
    }
    return out;
}

function defaultDesktopConfig() {
    return {
        layout: "tiles",
        style: "icon",
        barStyle: "brackets",
        listStyle: "rows",
        metrics: [
            {device: "cpu", vals: ["usage", "temp"], graph: true, on: true},
            {device: "memory", vals: ["used"], graph: true, on: true},
            {device: "net", vals: ["down", "up"], graph: true, on: true},
            {device: "disk", vals: ["read", "write"], graph: true, on: true}
        ],
        graphInterval: 60,
        legend: "list",
        barNames: false,
        barOrientation: "auto",
        showHeader: true,
        title: "",
        showTopProcesses: false,
        topProcessCount: 3,
        topProcessSortBy: "cpu",
        background: "card",
        textShadow: true
    };
}

function defaultDashConfig() {
    return Object.assign(defaultDesktopConfig(), {
        metrics: [{device: "cpu", vals: ["usage"], graph: false, on: true}],
        legend: "inline",
        showHeader: false,
        showTopProcesses: false
    });
}

const enums = {
    layout: ["tiles", "list", "bars", "graphs"],
    style: ["icon", "meter", "ring", "graph"],
    barStyle: ["brackets", "tiles"],
    listStyle: ["rows", "tiles"],
    graphInterval: [60, 300, 600, 900, 1800],
    legend: ["off", "inline", "list"],
    barOrientation: ["auto", "horizontal", "vertical"],
    topProcessCount: [3, 5, 10],
    topProcessSortBy: ["cpu", "memory"],
    background: ["card", "none"]
};
const unsafeKeys = ["__proto__", "constructor", "prototype"];
const bools = ["barNames", "showHeader", "showTopProcesses", "textShadow"];

// Drops trademark marks, core counts, clock speeds and integrated graphics from a CPU model name.
function shortCpuName(model) {
    return String(model || "").replace(/\((R|TM)\)/gi, "").replace(/\s+(w\/|with)\s.*$/i, "").replace(/\s+@\s.*$/, "").replace(/\b(\d+-Core|Processor|CPU)\b/gi, "").replace(/\s+/g, " ").trim();
}

// The Tiles background became the Tiles style.
function upgradeLegacy(src) {
    const out = {};
    Object.keys(src).forEach(k => {
        if (unsafeKeys.indexOf(k) < 0)
            out[k] = src[k];
    });
    if (out.background === "tiles") {
        out.background = out.layout === "graphs" ? "card" : "none";
        out.textShadow = false;
        if (out.layout === "bars")
            out.barStyle = "tiles";
        else if (out.layout === "list")
            out.listStyle = "tiles";
    }
    return out;
}

function normalizeConfig(raw, defaults) {
    const base = defaults || defaultDesktopConfig();
    const src = raw && typeof raw === "object" && !Array.isArray(raw) ? upgradeLegacy(raw) : {};
    const out = Object.assign({}, src);
    Object.keys(enums).forEach(k => out[k] = enums[k].indexOf(src[k]) >= 0 ? src[k] : base[k]);
    bools.forEach(k => out[k] = typeof src[k] === "boolean" ? src[k] : base[k]);
    out.title = typeof src.title === "string" && src.title.length <= maxSuffix && !hasControl(src.title) ? src.title : base.title;
    out.metrics = listOf(src.metrics) ? normalizeMetrics(src.metrics) : normalizeMetrics(base.metrics);
    return out;
}

function paintsTiles(config) {
    return config.layout === "tiles" || (config.layout === "bars" && config.barStyle === "tiles") || (config.layout === "list" && config.listStyle === "tiles");
}

// Opacity sets the card and the tiles; without either, nothing it changes is painted.
function usesOpacity(config) {
    return config.background === "card" || paintsTiles(config);
}

function modulesFor(metrics, extras) {
    const set = {};
    (metrics || []).forEach(m => {
        if (!m || m.on === false)
            return;
        const type = typeOf(m.device);
        const vals = m.vals || [];
        const has = id => vals.indexOf(id) >= 0;
        const isAll = m.device === type;
        if (type === "cpu" || type === "memory" || type === "gpu")
            set[type] = true;
        else if (type === "disk") {
            if (has("read") || has("write"))
                set[isAll ? "disk" : "disk-rate"] = true;
            if (has("space") || m.mount)
                set["diskmounts"] = true;
        } else if (type === "net")
            set[isAll ? "network" : "net-rate"] = true;
    });
    if (extras && extras.processes)
        set["processes"] = true;
    if (extras && extras.system)
        set["system"] = true;
    return Object.keys(set).sort();
}

// The dgop modules a device pane reads; the aggregate keys ("disk", "net") also need the all-devices modules.
function paneModules(key) {
    const type = typeOf(key);
    const all = key === type;
    switch (type) {
    case "cpu":
        return ["cpu", "system"];
    case "memory":
        return ["memory", "memory-modules"];
    case "gpu":
        return ["gpu"];
    case "disk":
        return all ? ["disk", "disk-rate", "diskmounts"] : ["disk-rate", "diskmounts"];
    case "net":
        return all ? ["network", "net-rate"] : ["net-rate"];
    }
    return [];
}

function needsDrives(metrics) {
    return (metrics || []).some(m => m && m.on !== false && typeOf(m.device) === "disk" && (m.device !== "disk" || ((m.vals || []).indexOf("space") >= 0 && !m.mount)));
}
