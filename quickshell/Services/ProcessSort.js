.pragma library

function _num(v) {
    return (v === null || v === undefined || Number.isNaN(v)) ? null : v;
}

// Value behind a sort/column key; null when the field is absent.
function rawValue(key, row) {
    switch (key) {
    case "cpu": return _num(row.cpu);
    case "memory": return _num(row.memoryKB);
    case "gpu": return _num(row.gpu);
    case "vram": return _num(row.vramKB);
    case "diskRead": return _num(row.diskRead);
    case "diskWrite": return _num(row.diskWrite);
    case "disk": {
        const r = _num(row.diskRead), w = _num(row.diskWrite);
        return (r === null && w === null) ? null : (r ?? 0) + (w ?? 0);
    }
    case "gpuVideo": return _num(row.gpuVideo);
    case "connections": return _num(row.connections);
    case "netRx": return _num(row.netRx);
    case "netTx": return _num(row.netTx);
    case "status": return row.status ? row.status : null;
    case "threads": return _num(row.threads);
    case "nice": return _num(row.nice);
    case "cpuTime": return _num(row.pticks);
    case "pid": return _num(row.pid);
    case "name": return (row.appName || row.command || "").toLowerCase();
    case "user": return row.username ? row.username : null;
    }
    return null;
}

// Absent values sort last in both directions; ties fall back to PID ascending.
function compare(key, ascending) {
    return (a, b) => {
        const x = rawValue(key, a), y = rawValue(key, b);
        if ((x === null) !== (y === null))
            return x === null ? 1 : -1;
        let c = 0;
        if (x !== null)
            c = typeof x === "string" ? x.localeCompare(y) : x - y;
        if (c !== 0)
            return ascending ? c : -c;
        return (a.pid ?? 0) - (b.pid ?? 0);
    };
}
