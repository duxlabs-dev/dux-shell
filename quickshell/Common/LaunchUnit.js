.pragma library

// systemd.unit(5) "String Escaping for Inclusion in Unit Names"
function escape(str) {
    let out = "";
    for (const ch of str) {
        if (/[A-Za-z0-9:_.]/.test(ch)) {
            out += ch;
            continue;
        }
        if (ch === "/") {
            out += "-";
            continue;
        }
        const code = ch.codePointAt(0);
        out += code < 128 ? "\\x" + code.toString(16).padStart(2, "0") : encodeURIComponent(ch).replace(/%/g, "\\x").toLowerCase();
    }
    return out.startsWith(".") ? "\\x2e" + out.slice(1) : out;
}

function hasUnitName(args) {
    return args.some(arg => arg === "--unit" || arg === "-u" || arg.startsWith("--unit="));
}

// app-<launcher>-<ApplicationID>-<RANDOM>.scope per systemd.io/DESKTOP_ENVIRONMENTS, the shape xdg-desktop-portal maps back to a desktop id
function prefixArgs(prefix, desktopId, suffix) {
    const args = prefix.split(" ");
    if (args[0] !== "systemd-run" || !args.includes("--scope") || !desktopId || hasUnitName(args))
        return args;
    const unit = `app-dms-${escape(desktopId)}-${suffix}`;
    if (unit.length + ".scope".length > 255)
        return args;
    return [args[0], `--unit=${unit}`].concat(args.slice(1));
}

function randomSuffix() {
    return Date.now().toString(36) + Math.floor(Math.random() * 1679616).toString(36);
}
