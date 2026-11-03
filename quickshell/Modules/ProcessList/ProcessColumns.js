.pragma library
.import "../../Common/Format.js" as Format
.import "../../Services/ProcessSort.js" as ProcessSort

// width is in Theme.fontSizeSmall units. meter marks resource columns, drawn in the stronger text color.
const COLUMNS = [
    {id: "cpu", width: 7, meter: "percent"},
    {id: "memory", width: 8, meter: "memory"},
    {id: "gpu", width: 6, meter: "percent", modules: ["process-gpu"]},
    {id: "vram", width: 7, meter: "vram", modules: ["process-gpu", "gpu"]},
    {id: "gpuVideo", width: 6, meter: "percent", modules: ["process-gpu"]},
    {id: "diskRead", group: "disk", width: 7, meter: "disk", modules: ["process-io", "disk"]},
    {id: "diskWrite", group: "disk", width: 7, meter: "disk", modules: ["process-io", "disk"]},
    {id: "connections", group: "network", width: 7, modules: ["process-net"]},
    {id: "netRx", group: "network", width: 7, meter: "net", modules: ["process-net", "network"]},
    {id: "netTx", group: "network", width: 7, meter: "net", modules: ["process-net", "network"]},
    {id: "status", width: 7},
    {id: "threads", width: 5},
    {id: "nice", width: 4},
    {id: "cpuTime", width: 6},
    {id: "pid", width: 5},
    {id: "user", width: 8}
];

const DEFAULT_COLUMNS = ["cpu", "memory", "gpu", "vram", "diskRead", "diskWrite", "connections", "netRx", "netTx"];
const POPOUT_COLUMNS = ["cpu", "memory", "pid"];

function _col(id) {
    return COLUMNS.find(c => c.id === id) || null;
}

function modulesFor(columnIds) {
    const out = [];
    for (const id of columnIds) {
        for (const m of _col(id)?.modules ?? []) {
            if (!out.includes(m))
                out.push(m);
        }
    }
    return out;
}

// null means absent: the caller shows an em dash. status stays the raw letter.
function formatCell(id, row) {
    const v = ProcessSort.rawValue(id, row);
    if (v === null)
        return null;
    switch (id) {
    case "cpu": return v.toFixed(1) + "%";
    case "gpu":
    case "gpuVideo": return v.toFixed(0) + "%";
    case "memory":
    case "vram": return Format.formatBytes(v * 1024, true);
    case "diskRead":
    case "diskWrite": return Format.formatRate(v, 1);
    // UDP (QUIC) has no byte counters, so the TCP rate is only a lower bound.
    case "netRx":
    case "netTx": return (row.netPartial ? "≥ " : "") + Format.formatRate(v, 1);
    case "cpuTime": return Format.formatDuration(v, true);
    case "connections":
    case "threads":
    case "nice":
    case "pid": return String(v);
    case "status":
    case "user": return v;
    }
    return null;
}

// Why a cell is absent: a GPU the user doesn't monitor, a rate dgop can't measure on a readable process
// (UDP only, a container's network), or a process we can't read.
function absentReason(id, row) {
    if ((id === "gpu" || id === "vram" || id === "gpuVideo") && row?.gpuUnmonitored === true)
        return "unmonitored";
    if ((id === "netRx" || id === "netTx") && row?.connections != null)
        return "unknown";
    return "unreadable";
}
