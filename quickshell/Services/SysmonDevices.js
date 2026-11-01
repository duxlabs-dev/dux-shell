.pragma library
.import "../Common/Format.js" as Format

const WHOLE_DISK = /^(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|mmcblk\d+)$/;

function isWholeDisk(name) {
    return WHOLE_DISK.test(name || "");
}

const KIND_PATTERNS = [["loopback", /^lo$/], ["ethernet", /^(en|eth)/], ["wifi", /^wl/], ["vpn", /^(tailscale|wg|tun|tap|proton|nordlynx|ipv6leakintrf)/], ["virtual", /^(veth|docker|virbr|br-|vnet|lxc|podman|cni|flannel)/]];

const LINK_KINDS = {
    ethernet: "ethernet",
    wireless: "wifi",
    tunnel: "vpn",
    loopback: "loopback"
};

// The name decides first; dgop's sysfs link type only fills in names the patterns don't know.
function interfaceKind(name, linkType) {
    for (const [kind, pattern] of KIND_PATTERNS) {
        if (pattern.test(name || ""))
            return kind;
    }
    return LINK_KINDS[linkType] ?? "other";
}

function isHiddenByDefault(kind) {
    return kind === "loopback" || kind === "virtual";
}

function sumWholeDisks(entries, readKey, writeKey) {
    const total = {
        read: 0,
        write: 0
    };
    for (const entry of entries || []) {
        if (!isWholeDisk(entry.name ?? entry.device))
            continue;
        total.read += entry[readKey] || 0;
        total.write += entry[writeKey] || 0;
    }
    return total;
}

function formatLinkSpeed(mbit) {
    if (!(mbit > 0))
        return "";
    return mbit >= 1000 ? +(mbit / 1000).toFixed(1) + " Gbit/s" : mbit + " Mbit/s";
}

function wifiBand(mhz) {
    if (!(mhz > 0))
        return "";
    return mhz < 3000 ? "2.4 GHz" : mhz < 5925 ? "5 GHz" : "6 GHz";
}

function stripPrefixLength(cidr) {
    return String(cidr || "").split("/")[0];
}

// Chart axis for rates: the history peak plus 10%, never below the floor.
function rateAxisMax(values, secondaryValues, floor) {
    let peak = 0;
    for (const v of (values || []).concat(secondaryValues || []))
        if (v > peak)
            peak = v;
    return Math.max(floor, peak * 1.1);
}

// "32.0 GiB DDR4" from the installed modules (sizes in KB), or "" when none are known.
function memoryModulesSummary(modules) {
    const list = modules || [];
    const total = list.reduce((sum, m) => sum + (m.size || 0), 0) * 1024;
    if (total <= 0)
        return "";
    const types = [];
    for (const m of list)
        if (m.type && !types.includes(m.type))
            types.push(m.type);
    return [Format.formatBytes(total, true).replace(/\.0 /, " ")].concat(types).join(" ");
}

function formatTemp(celsius) {
    if (celsius === null || celsius === undefined)
        return "—";
    return Math.round(celsius) + " °C";
}

// Mirrors dgop: an id matches a GPU by vendor:device id or PCI bus id, case-insensitively.
function gpuMonitored(ids, pciId, busId) {
    const want = [pciId, busId].filter(Boolean).map(v => String(v).toLowerCase());
    return (ids || []).some(id => want.includes(String(id).toLowerCase()));
}

// Bus id tells identical cards apart; dgop leaves it empty where the platform has none.
function gpuSlot(gpu) {
    return gpu.busId || gpu.pciId || "";
}

function deviceKey(type, id) {
    return type + ":" + id;
}

function naturalCompare(a, b) {
    const pa = String(a).match(/\d+|\D+/g) || [];
    const pb = String(b).match(/\d+|\D+/g) || [];
    for (let i = 0; i < Math.min(pa.length, pb.length); i++) {
        const x = pa[i], y = pb[i];
        if (x === y)
            continue;
        if (/^\d/.test(x) && /^\d/.test(y))
            return Number(x) - Number(y) || (x < y ? -1 : 1);
        // Shorter letter runs first, matching disk naming (sdz is followed by sdaa).
        return x.length - y.length || (x < y ? -1 : 1);
    }
    return pa.length - pb.length;
}

// "ChannelA-DIMM0", "P0 CHANNEL A", "DIMM_A2", "A1_DIMM0" -> board channel key, or null.
const CHANNEL_PATTERNS = [/CHANNEL[ _-]*([A-Z]|\d+)(?![A-Z])/i, /^(?:SO)?DIMM[ _-]?([A-Z])\d*$/i, /^([A-Z])\d*[ _-](?:SO)?DIMM\d*$/i];

// Number of distinct board channels across the modules' locators, or null unless
// every locator is recognized. DDR5 subchannels never show up in locators.
function memoryChannelCount(modules) {
    if (!modules || modules.length === 0)
        return null;
    const channels = new Set();
    for (const m of modules) {
        const loc = (m.locator || "").trim();
        let key = null;
        for (const re of CHANNEL_PATTERNS) {
            const hit = re.exec(loc);
            if (hit) {
                key = loc.slice(0, hit.index).toUpperCase() + hit[1].toUpperCase();
                break;
            }
        }
        if (key === null)
            return null;
        channels.add(key);
    }
    return channels.size;
}
