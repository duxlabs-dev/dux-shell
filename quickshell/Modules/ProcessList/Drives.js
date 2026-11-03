.pragma library
.import "../../Common/Format.js" as Format

const MIN_STRIP_WEIGHT = 0.04;
const HOURS_AS_DAYS = 48;
const DAYS_AS_YEARS = 730;

function row(id, value, warn) {
    return {
        id: id,
        value: value,
        warn: !!warn
    };
}

function has(v) {
    return v !== undefined && v !== null;
}

// powerOnTime carries a numeric string plus `unit` ("hours" | "days" | "years"); QML picks the "%1 days"-style string.
function powerOnRow(hours) {
    if (hours < HOURS_AS_DAYS)
        return Object.assign(row("powerOnTime", String(Math.round(hours))), {
            unit: "hours"
        });
    const days = hours / 24;
    if (days < DAYS_AS_YEARS)
        return Object.assign(row("powerOnTime", String(Math.round(days))), {
            unit: "days"
        });
    return Object.assign(row("powerOnTime", (days / 365.25).toFixed(1)), {
        unit: "years"
    });
}

// Self-test value is "ok", "running" or "error"; null (no row) when the status is empty or unrecognized.
function selftestRow(status) {
    const s = String(status || "").toLowerCase();
    if (!s || s === "unknown")
        return null;
    const value = s === "success" || s === "ok" || s === "passed" ? "ok" : s.indexOf("progress") >= 0 || s === "running" ? "running" : "error";
    return row("selftest", value, false);
}

function summaryRows(drive) {
    const rows = [];
    const add = (id, v, warn, fmt) => {
        if (has(v))
            rows.push(row(id, fmt ? fmt(v) : String(v), warn));
    };
    const n = drive && drive.nvme;
    const a = drive && drive.ata;
    if (n) {
        const warnings = (n.criticalWarning || []).filter(w => w !== "");
        rows.push(row("criticalWarning", warnings.length ? warnings.join(", ") : "none", warnings.length > 0));
        add("spare", n.availableSpare, has(n.spareThreshold) && n.availableSpare < n.spareThreshold, v => v + "%");
        add("wear", n.percentUsed, false, v => v + "%");
        add("mediaErrors", n.mediaErrors, false);
        add("dataRead", n.dataRead, false, v => Format.formatBytes(v, true));
        add("dataWritten", n.dataWritten, false, v => Format.formatBytes(v, true));
        add("unsafeShutdowns", n.unsafeShutdowns, false);
        if (has(n.powerOnHours))
            rows.push(powerOnRow(n.powerOnHours));
        const st = selftestRow(n.selftestStatus);
        if (st)
            rows.push(st);
    } else if (a) {
        add("reallocated", a.reallocatedSectors, a.reallocatedSectors > 0);
        add("pending", a.pendingSectors, a.pendingSectors > 0);
        add("uncorrectable", a.offlineUncorrectable, a.offlineUncorrectable > 0);
        add("crc", a.crcErrors, false);
        if (has(a.powerOnHours))
            rows.push(powerOnRow(a.powerOnHours));
        if (drive.kind === "hdd") {
            add("startStop", a.startStopCount, false);
            add("loadCycles", a.loadCycleCount, false);
            add("spinUp", a.spinUpTimeMs, false, v => v + " ms");
        }
        const st = selftestRow(a.selftestStatus);
        if (st)
            rows.push(st);
    }
    return rows;
}

// "healthy" | "warning" | "failing", or "" when the drive has no SMART data. An ATA `failing` flag wins.
function healthLevel(drive) {
    if (!drive)
        return "";
    if (drive.ata && drive.ata.failing)
        return "failing";
    return ({
            ok: "healthy",
            warning: "warning",
            failing: "failing"
        })[drive.health] || "";
}

// "ok" | "warning" | "critical" label id for a healthLevel, or "" when there is none.
function healthWord(level) {
    return ({
            healthy: "ok",
            warning: "warning",
            failing: "critical"
        })[level] || "";
}

// Mount point closest to the root: "/" wins, otherwise the shortest path.
function rootMostMount(drive) {
    let best = "";
    for (const p of (drive && drive.partitions) || []) {
        const m = p.mountPoint;
        if (m && (best === "" || m === "/" || (best !== "/" && m.length < best.length)))
            best = m;
    }
    return best;
}

// Rows with warn set, for the health pill tooltip.
function warnRows(drive) {
    return summaryRows(drive).filter(r => r.warn);
}

function mountPercent(mounts, mountPoint) {
    if (!mountPoint)
        return null;
    for (const m of mounts || []) {
        if (m.mount === mountPoint) {
            const p = parseFloat(m.percent);
            return isNaN(p) ? null : Math.max(0, Math.min(1, p / 100));
        }
    }
    return null;
}

// Weights sum to 1 and none is below MIN_STRIP_WEIGHT.
function partitionStrip(drive, mounts) {
    const parts = (drive && drive.partitions) || [];
    const sizes = parts.map(p => (isFinite(p.size) && p.size > 0 ? p.size : 0));
    const total = sizes.reduce((s, v) => s + v, 0);
    const equal = !total || parts.length > 1 / MIN_STRIP_WEIGHT;
    const clamped = sizes.map(() => false);
    let again = !equal;
    while (again) {
        const n = clamped.filter(Boolean).length;
        const room = 1 - n * MIN_STRIP_WEIGHT;
        const rest = sizes.reduce((s, v, i) => s + (clamped[i] ? 0 : v), 0);
        again = false;
        sizes.forEach((v, i) => {
            if (!clamped[i] && v / rest * room < MIN_STRIP_WEIGHT) {
                clamped[i] = true;
                again = true;
            }
        });
    }
    const n = clamped.filter(Boolean).length;
    const room = 1 - n * MIN_STRIP_WEIGHT;
    const rest = sizes.reduce((s, v, i) => s + (clamped[i] ? 0 : v), 0);
    return parts.map((p, i) => ({
                device: p.device,
                weight: equal ? 1 / parts.length : clamped[i] ? MIN_STRIP_WEIGHT : room * sizes[i] / rest,
                label: p.mountPoint || p.label || String(p.device || "").split("/").pop(),
                mounted: !!p.mountPoint,
                size: sizes[i],
                swap: !!p.swap || p.fsType === "swap",
                fsType: p.fsType || "",
                encrypted: !!p.encrypted,
                usedRatio: mountPercent(mounts, p.mountPoint)
            }));
}

// Decimal units, the way drives are sold: 2000398934016 -> "2 TB".
function formatCapacity(bytes) {
    const units = ["B", "kB", "MB", "GB", "TB", "PB"];
    let v = bytes > 0 ? bytes : 0;
    let i = 0;
    while (v >= 1000 && i < units.length - 1) {
        v /= 1000;
        i++;
    }
    return (v >= 100 || i === 0 ? String(Math.round(v)) : String(+v.toFixed(1))) + " " + units[i];
}

const KIND_NAMES = {
    nvme: "NVMe SSD",
    ssd: "SSD",
    hdd: "HDD"
};

function kindName(drive) {
    return KIND_NAMES[drive && drive.kind] || "";
}

// "nvme" is drawn by DeviceIcon (Material Symbols has no M.2 glyph); the rest are Material Symbols names.
function driveIcon(drive) {
    if (!drive)
        return "storage";
    if (drive.connectionBus === "usb")
        return "usb";
    if (drive.connectionBus === "sdio" || String(drive.name || "").startsWith("mmcblk"))
        return "sd_card";
    if (drive.removable)
        return "usb";
    switch (drive.kind) {
    case "nvme":
        return "nvme";
    case "ssd":
        return "hard_drive_2";
    case "hdd":
        return "hard_disk";
    }
    return String(drive.name || "").startsWith("sr") ? "album" : "storage";
}

// "NVMe SSD, 2 TB, PCIe 4.0 x4"
function driveSubtitle(drive) {
    if (!drive)
        return "";
    return [kindName(drive), drive.size > 0 ? formatCapacity(drive.size) : "", drive.link || ""].filter(s => s).join(", ");
}

function driveFor(name, drives) {
    for (const d of drives || []) {
        if (d.name === name || d.device === name)
            return d;
    }
    return null;
}

function driveByMount(mountPoint, drives) {
    for (const d of drives || []) {
        if ((d.partitions || []).some(p => p.mountPoint === mountPoint))
            return d;
    }
    return null;
}

function kv(key, value) {
    return {
        key: key,
        value: String(value)
    };
}

function scalarRows(obj) {
    return Object.keys(obj).filter(k => typeof obj[k] !== "object").map(k => kv(k, obj[k]));
}

// smartctl -x --json -> {sections: [{id, rows: [{key, value}]}], error}. Section ids: health, attributes, selftest, errors.
function parseReport(jsonText) {
    let j;
    try {
        j = JSON.parse(jsonText);
    } catch (e) {
        return {
            sections: [],
            error: "Invalid smartctl output"
        };
    }
    if (!j || typeof j !== "object" || Array.isArray(j))
        return {
            sections: [],
            error: "Invalid smartctl output"
        };

    const sections = [];
    const push = (id, rows) => {
        if (rows.length)
            sections.push({
                id: id,
                rows: rows
            });
    };

    const nv = j.nvme_smart_health_information_log;
    if (nv && typeof nv === "object")
        push("health", scalarRows(nv).filter(r => r.key !== "num_err_log_entries"));

    const table = j.ata_smart_attributes && j.ata_smart_attributes.table;
    if (Array.isArray(table))
        push("attributes", table.filter(t => t && has(t.name)).map(t => kv(t.name, t.value + " / " + t.worst + " / " + t.thresh + (t.raw && t.raw.string ? "  " + t.raw.string : ""))));

    const nvTests = j.nvme_self_test_log && j.nvme_self_test_log.table;
    // smartctl -x prints the extended (GP) logs in place of the standard ones when the drive has them.
    const testLog = j.ata_smart_self_test_log;
    const ataTests = testLog && (testLog.standard || testLog.extended)?.table;
    const str = o => o && (o.string || o.value);
    if (Array.isArray(nvTests))
        push("selftest", nvTests.map(t => kv(str(t.self_test_code), str(t.self_test_result) + (has(t.power_on_hours) ? " @ " + t.power_on_hours + " h" : ""))));
    else if (Array.isArray(ataTests))
        push("selftest", ataTests.map(t => kv(str(t.type), str(t.status) + (has(t.lifetime_hours) ? " @ " + t.lifetime_hours + " h" : ""))));

    const errors = [];
    const errorLog = j.ata_smart_error_log;
    const ataErr = errorLog && (errorLog.summary || errorLog.extended);
    if (ataErr && has(ataErr.count))
        errors.push(kv("count", ataErr.count));
    if (nv && has(nv.num_err_log_entries))
        errors.push(kv("num_err_log_entries", nv.num_err_log_entries));
    push("errors", errors);

    const msgs = ((j.smartctl && j.smartctl.messages) || []).filter(m => m && m.severity === "error").map(m => m.string);
    return {
        sections: sections,
        error: msgs.join("\n")
    };
}
