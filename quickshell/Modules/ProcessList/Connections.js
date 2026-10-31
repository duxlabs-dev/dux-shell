.pragma library

// "1.2.3.4:443" or "[2a00::1]:443" -> {host, port}.
function splitRemote(remote) {
    const s = String(remote || "");
    const m = /^\[(.*)\]:(\d+)$/.exec(s) || /^([^:]*):(\d+)$/.exec(s);
    return m ? { host: m[1], port: Number(m[2]) } : { host: s, port: 0 };
}

function ipv4(host) {
    const parts = host.split(".").map(Number);
    return parts.length === 4 && parts.every(n => Number.isInteger(n) && n >= 0 && n <= 255) ? parts : null;
}

// Tailscale hands out 100.64.0.0/10 and fd7a:115c:a1e0::/48.
function isTailscale(host) {
    const v4 = ipv4(host);
    if (v4)
        return v4[0] === 100 && v4[1] >= 64 && v4[1] <= 127;
    return host.toLowerCase().startsWith("fd7a:115c:a1e0:");
}

// "internet", "tailscale" or "local". dgop's local flag covers private, CGNAT and link-local remotes.
function kind(remote) {
    if (!remote?.local)
        return "internet";
    return isTailscale(splitRemote(remote.remote).host) ? "tailscale" : "local";
}

const SERVICES = {
    21: "FTP", 22: "SSH", 25: "SMTP", 53: "DNS", 80: "HTTP", 110: "POP3", 123: "NTP", 143: "IMAP", 443: "HTTPS",
    465: "SMTPS", 587: "SMTP", 853: "DNS over TLS", 993: "IMAPS", 995: "POP3S", 1883: "MQTT", 3389: "RDP",
    3478: "STUN", 5222: "XMPP", 5228: "Google push", 5353: "mDNS", 8080: "HTTP", 8443: "HTTPS", 8883: "MQTT"
};

// UDP to 443 is QUIC (HTTP/3); other ports fall back to the number.
function service(port, protocol) {
    if (port === 443 && protocol === "udp")
        return "QUIC";
    return SERVICES[port] || (port > 0 ? String(port) : "");
}

// Remotes grouped by kind and host:port, busiest first: {internet: [...], tailscale: [...], local: [...]}.
// names maps a Tailscale address to its device name.
function group(remotes, names) {
    const out = { internet: [], tailscale: [], local: [] };
    const seen = {};
    for (const r of remotes || []) {
        const k = kind(r);
        const key = k + "|" + r.remote + "|" + r.protocol;
        if (seen[key]) {
            seen[key].count++;
            continue;
        }
        const { host, port } = splitRemote(r.remote);
        seen[key] = { kind: k, host: host, name: (names && names[host]) || host, port: port, service: service(port, r.protocol), count: 1 };
        out[k].push(seen[key]);
    }
    for (const k in out)
        out[k].sort((a, b) => b.count - a.count);
    return out;
}

// What a systemd unit from the cgroup says: a real service, an app's launch scope, a login session or something else.
function unitKind(unit) {
    const u = String(unit || "");
    if (u === "")
        return "";
    if (u.startsWith("app-"))
        return "app";
    if (/^session-.+\.scope$/.test(u))
        return "session";
    if (u.endsWith(".service"))
        return "service";
    return "other";
}

// systemd escapes characters in unit names as \xNN ("proton\x2dmail" is "proton-mail").
function unescapeUnit(unit) {
    return String(unit || "").replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)));
}
