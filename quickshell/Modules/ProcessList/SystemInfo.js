.pragma library
.import "../../Services/SysmonDevices.js" as Devices

const CPU_CHIPS = ["k10temp", "coretemp", "zenpower", "cpu_thermal"];
const GPU_CHIPS = ["amdgpu", "radeon", "nouveau", "nvidia", "i915", "xe"];
const MEMORY_CHIPS = ["jc42", "spd5118"];
const KIND_ORDER = ["temperature", "fan", "power"];
const FALLBACK_TEMP_LIMIT = 100;

// wlr-output mode {width, height, refresh (mHz)} -> "2560 × 1440, 165 Hz".
function modeText(mode) {
    if (!mode || !(mode.width > 0))
        return "";
    const size = mode.width + " × " + mode.height;
    return mode.refresh > 0 ? size + ", " + Math.round(mode.refresh / 1000) + " Hz" : size;
}

// Sensor owner name: names = {cpu, gpu, memory} (translated), drives from DriveService, gpus = DgopService.availableGpus.
function sensorOwner(sensor, drives, gpus, names, memoryIndex) {
    const chip = sensor.chip || "";
    if (CPU_CHIPS.includes(chip))
        return names.cpu;
    if (GPU_CHIPS.includes(chip)) {
        const list = gpus || [];
        const gpu = list.length > 1 ? list.find(g => String(g.busId).toLowerCase() === String(sensor.device).toLowerCase()) : null;
        return (gpu && gpu.fullName) || names.gpu;
    }
    if (chip === "nvme") {
        const drive = (drives || []).find(d => String(d.name).startsWith(sensor.device + "n"));
        return (drive && drive.model) || sensor.device || chip;
    }
    if (MEMORY_CHIPS.includes(chip))
        return names.memory + " " + memoryIndex;
    return "";
}

// Display rows for dgop sensors: {name, kind, value, ratio}; ratio is null when there is no limit to scale against.
function sensorRows(sensors, drives, gpus, names) {
    const memoryDevices = [];
    // -40 °C or below is an unconnected header probe (e.g. a board's T_Sensor or Water_In), not a reading.
    const rows = (sensors || []).filter(s => !(s.kind === "temperature" && s.value <= -40)).map(s => {
        if (MEMORY_CHIPS.includes(s.chip) && !memoryDevices.includes(s.device))
            memoryDevices.push(s.device);
        const owner = sensorOwner(s, drives, gpus, names, memoryDevices.indexOf(s.device) + 1);
        const generic = /^(temp|fan|power)\d+$/.test(s.label || "") || (s.chip === "nvme" && s.label === "Composite");
        const detail = generic && owner ? "" : String(s.label || s.chip || "").replace(/_/g, " ");
        const name = owner && detail ? owner + " (" + detail + ")" : owner || detail;
        let limit = s.critical > 0 ? s.critical : s.max > 0 ? s.max : null;
        let value;
        if (s.kind === "temperature") {
            limit = limit || FALLBACK_TEMP_LIMIT;
            value = Devices.formatTemp(s.value);
        } else if (s.kind === "fan") {
            value = Math.round(s.value) + " RPM";
        } else {
            value = (s.value < 10 ? s.value.toFixed(1) : Math.round(s.value)) + " W";
        }
        return {
            name: name,
            kind: s.kind,
            value: value,
            ratio: limit ? Math.max(0, Math.min(1, s.value / limit)) : null
        };
    });
    const rank = k => KIND_ORDER.includes(k) ? KIND_ORDER.indexOf(k) : KIND_ORDER.length;
    return rows.map((r, i) => [r, i]).sort((a, b) => rank(a[0].kind) - rank(b[0].kind) || a[1] - b[1]).map(x => x[0]);
}

// First version-looking token: "Hyprland 0.56.2 built from …" -> "0.56.2".
function version(text) {
    const m = /\d+\.\d+(?:\.\d+)?/.exec(String(text || ""));
    return m ? m[0] : "";
}

// "2088 pacman, 17 flatpak" from pkg.<manager> facts; managers with nothing installed are left out.
function packagesText(facts) {
    return Object.keys(facts || {}).filter(k => k.startsWith("pkg.") && Number(facts[k]) > 0).sort((a, b) => Number(facts[b]) - Number(facts[a])).map(k => facts[k] + " " + k.slice(4)).join(", ");
}

function mesaVersion(facts) {
    return version((facts || {}).mesa);
}

const DMI_PLACEHOLDERS = ["system product name", "to be filled by o.e.m.", "default string", "not applicable", "system version", "none", "o.e.m."];

// "ASUS ROG …" from DMI vendor and product, without firmware placeholders.
function dmiModel(facts) {
    const f = facts || {};
    const product = DMI_PLACEHOLDERS.includes(String(f["dmi.product_name"] || "").toLowerCase()) ? "" : (f["dmi.product_name"] || "");
    return product ? [f["dmi.sys_vendor"], product].filter(x => x).join(" ") : "";
}

// SMBIOS chassis type code -> desktop, laptop, server, tablet, convertible, mini or "".
function chassisKind(code) {
    const n = Number(code);
    if ([3, 4, 5, 6, 7, 15, 16, 24].includes(n))
        return "desktop";
    if ([8, 9, 10, 14].includes(n))
        return "laptop";
    if ([17, 23, 28, 29].includes(n))
        return "server";
    if (n === 30)
        return "tablet";
    if ([31, 32].includes(n))
        return "convertible";
    if ([35, 36].includes(n))
        return "mini";
    return "";
}

// The full report: GitHub-flavored Markdown that also reads well in Discord. Rows marked private and empty rows are
// left out. sections = [{title, rows: [{label, value, private}]}].
function report(title, sections) {
    const blocks = sections.map(s => {
        const rows = (s.rows || []).filter(r => r && r.value && !r.private);
        return rows.length ? "**" + s.title + "**\n" + rows.map(r => "- " + r.label + ": " + r.value).join("\n") : "";
    }).filter(b => b);
    return ["### " + title].concat(blocks).join("\n\n");
}

// The short overview: one bullet per non-empty line.
function summary(lines) {
    return (lines || []).filter(l => l).map(l => "- " + l).join("\n");
}
