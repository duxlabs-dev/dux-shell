.pragma library

function formatRate(bytesPerSec, gbDecimals) {
    if (bytesPerSec < 1024)
        return bytesPerSec.toFixed(0) + " B/s";
    if (bytesPerSec < 1024 * 1024)
        return (bytesPerSec / 1024).toFixed(1) + " KB/s";
    if (bytesPerSec < 1024 * 1024 * 1024)
        return (bytesPerSec / (1024 * 1024)).toFixed(1) + " MB/s";
    return (bytesPerSec / (1024 * 1024 * 1024)).toFixed(gbDecimals ?? 2) + " GB/s";
}

function formatRateCompact(bytesPerSec, abbreviated) {
    const units = ["K", "M", "G", "T"];
    let value = bytesPerSec / 1024;
    let unit = 0;
    while (unit < units.length - 1 && Math.round(value) >= 1000) {
        value /= 1024;
        unit++;
    }
    const shown = bytesPerSec > 0 ? Math.max(1, Math.round(value)) : 0;
    return abbreviated ? shown + units[unit] : shown + " " + units[unit] + "B/s";
}

function formatBytes(bytes, iec) {
    if (iec) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let value = bytes;
        let i = 0;
        while (value >= 1024 && i < units.length - 1) {
            value /= 1024;
            i++;
        }
        return value.toFixed(i < 2 ? 0 : 1) + " " + units[i];
    }
    if (bytes < 1024)
        return bytes.toFixed(0) + "B";
    if (bytes < 1024 * 1024)
        return (bytes / 1024).toFixed(0) + "K";
    if (bytes < 1024 * 1024 * 1024)
        return (bytes / (1024 * 1024)).toFixed(1) + "M";
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + "G";
}

function formatIsoTime(isoString) {
    if (!isoString)
        return "";
    try {
        const date = new Date(isoString);
        if (isNaN(date.getTime()))
            return "";
        return date.toLocaleTimeString(Qt.locale(), "HH:mm");
    } catch (e) {
        return "";
    }
}

function formatRemaining(ms, zeroText, minText, hText, hmText) {
    if (ms <= 0)
        return zeroText;
    const totalMinutes = Math.ceil(ms / 60000);
    if (totalMinutes < 60)
        return minText.arg(totalMinutes);
    const hours = Math.floor(totalMinutes / 60);
    const mins = totalMinutes - hours * 60;
    if (mins === 0)
        return hText.arg(hours);
    return hmText.arg(hours).arg(mins);
}

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

function formatDuration(seconds, withHours) {
    if (!isFinite(seconds) || seconds < 0)
        return "0:00";
    const s = Math.floor(seconds % 60);
    if (withHours && seconds >= 3600)
        return Math.floor(seconds / 3600) + ":" + pad2(Math.floor(seconds / 60) % 60) + ":" + pad2(s);
    const m = Math.floor(seconds / 60);
    return m + ":" + pad2(s);
}

function formatUntil(ts, use24h) {
    if (!ts)
        return "";
    const d = new Date(ts);
    const hours = d.getHours();
    const minutes = d.getMinutes();
    if (use24h)
        return pad2(hours) + ":" + pad2(minutes);
    const suffix = hours >= 12 ? "PM" : "AM";
    const h12 = ((hours + 11) % 12) + 1;
    return h12 + ":" + pad2(minutes) + " " + suffix;
}

function addToHistory(arr, val, max) {
    const newArr = arr.slice();
    newArr.push(val);
    if (newArr.length > max)
        newArr.shift();
    return newArr;
}

function escapeHtml(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
