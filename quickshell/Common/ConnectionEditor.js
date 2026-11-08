.pragma library

// NetworkManager settings as decoded by the DMS backend: {section: {key: value}}.
// null and undefined both mean "absent" everywhere in this file.

function _absent(v) {
    return v === undefined || v === null;
}

function copy(v) {
    return _absent(v) ? v : JSON.parse(JSON.stringify(v));
}

function deepEqual(a, b) {
    if (_absent(a) || _absent(b))
        return _absent(a) && _absent(b);
    if (typeof a !== "object" || typeof b !== "object")
        return a === b;
    if (Array.isArray(a) !== Array.isArray(b))
        return false;
    if (Array.isArray(a)) {
        if (a.length !== b.length)
            return false;
        for (let i = 0; i < a.length; i++) {
            if (!deepEqual(a[i], b[i]))
                return false;
        }
        return true;
    }
    const keys = {};
    for (const k in a) {
        if (!_absent(a[k]))
            keys[k] = true;
    }
    for (const k in b) {
        if (!_absent(b[k]))
            keys[k] = true;
    }
    for (const k in keys) {
        if (!deepEqual(a[k], b[k]))
            return false;
    }
    return true;
}

function _unionKeys(a, b) {
    return Array.from(new Set(Object.keys(a || {}).concat(Object.keys(b || {}))));
}

function settingsDiff(original, draft) {
    const patch = {};
    let changed = false;
    for (const name of _unionKeys(original, draft)) {
        const os = original ? original[name] : undefined;
        const ds = draft ? draft[name] : undefined;
        if (_absent(ds)) {
            if (!_absent(os)) {
                patch[name] = null;
                changed = true;
            }
            continue;
        }
        if (_absent(os)) {
            patch[name] = copy(ds);
            changed = true;
            continue;
        }
        const sub = {};
        let subChanged = false;
        for (const key of _unionKeys(os, ds)) {
            if (deepEqual(os[key], ds[key]))
                continue;
            sub[key] = _absent(ds[key]) ? null : copy(ds[key]);
            subChanged = true;
        }
        if (subChanged) {
            patch[name] = sub;
            changed = true;
        }
    }
    return changed ? patch : null;
}

function _isIpv4(text) {
    const parts = text.split(".");
    return parts.length === 4 && parts.every(p => /^(0|[1-9]\d{0,2})$/.test(p) && Number(p) <= 255);
}

function _isIpv6(text) {
    if (text.indexOf(":::") >= 0)
        return false;
    const halves = text.split("::");
    if (halves.length > 2)
        return false;
    let groups = 0;
    for (let h = 0; h < halves.length; h++) {
        if (halves[h] === "")
            continue;
        const parts = halves[h].split(":");
        for (let i = 0; i < parts.length; i++) {
            const last = h === halves.length - 1 && i === parts.length - 1;
            if (last && parts[i].indexOf(".") >= 0) {
                if (!_isIpv4(parts[i]))
                    return false;
                groups += 2;
            } else if (/^[0-9a-fA-F]{1,4}$/.test(parts[i])) {
                groups += 1;
            } else {
                return false;
            }
        }
    }
    return halves.length === 2 ? groups < 8 : groups === 8;
}

function isValidIp(text, family) {
    const t = String(text ?? "").trim();
    return family === 6 ? _isIpv6(t) : _isIpv4(t);
}

function _parsePrefix(text, family) {
    if (!/^(0|[1-9]\d{0,2})$/.test(text))
        return -1;
    const p = Number(text);
    return p <= (family === 6 ? 128 : 32) ? p : -1;
}

// {address, prefix} or null; a bare address gets the full-length prefix, as nmcli does.
function _parseCidr(text, family, requirePrefix) {
    const t = String(text ?? "").trim();
    const slash = t.indexOf("/");
    if (slash < 0) {
        if (requirePrefix || !isValidIp(t, family))
            return null;
        return {
            "address": t,
            "prefix": family === 6 ? 128 : 32
        };
    }
    const address = t.slice(0, slash);
    const prefix = _parsePrefix(t.slice(slash + 1), family);
    if (prefix < 0 || !isValidIp(address, family))
        return null;
    return {
        "address": address,
        "prefix": prefix
    };
}

function isValidCidr(text, family) {
    return _parseCidr(text, family, true) !== null;
}

function _tokens(text) {
    return String(text ?? "").split(/[\s,]+/).filter(t => t.length > 0);
}

function addressText(addressData) {
    return (addressData || []).map(a => a.address + "/" + a.prefix).join(", ");
}

function addressDataFromText(text, family, existing) {
    const out = [];
    for (const token of _tokens(text)) {
        const parsed = _parseCidr(token, family, false);
        if (!parsed)
            return null;
        const match = (existing || []).find(e => e && e.address === parsed.address);
        out.push(Object.assign({}, copy(match) || {}, parsed));
    }
    return out;
}

function listText(arr) {
    return (arr || []).join(", ");
}

// NM dns-data: a plain address (v6 may carry %scope), or dns+udp:// / dns+tls:// with an
// optional :port and IPv6 in brackets; either form may end in #server-name.
function _isValidServer(text, family) {
    let t = text;
    const hash = t.indexOf("#");
    if (hash >= 0)
        t = t.slice(0, hash);
    const scheme = /^dns\+(udp|tls):\/\//.exec(t);
    if (scheme) {
        t = t.slice(scheme[0].length);
        const port = /:(\d{1,5})$/.exec(t);
        if (port) {
            if (Number(port[1]) < 1 || Number(port[1]) > 65535)
                return false;
            t = t.slice(0, -port[0].length);
        }
        if (family === 6) {
            const bracket = /^\[([^\]]+)\]$/.exec(t);
            if (!bracket)
                return false;
            t = bracket[1];
        }
    }
    return family === 6 ? isValidIp(t.replace(/%[\w.-]+$/, ""), 6) : isValidIp(t, 4);
}

function serverListFromText(text, family) {
    const out = _tokens(text);
    return out.every(s => _isValidServer(s, family)) ? out : null;
}

function domainListFromText(text) {
    return _tokens(text);
}

const _ROUTE_KEYS = ["dest", "prefix", "next-hop", "metric"];

function routeRows(routeData) {
    return (routeData || []).map(r => {
        const extra = {};
        for (const k in r) {
            if (_ROUTE_KEYS.indexOf(k) < 0)
                extra[k] = copy(r[k]);
        }
        return {
            "dest": _absent(r.prefix) ? String(r.dest ?? "") : r.dest + "/" + r.prefix,
            "nextHop": r["next-hop"] ?? "",
            "metric": _absent(r.metric) ? "" : String(r.metric),
            "extra": extra
        };
    });
}

function routeDataFromRows(rows, family) {
    const out = [];
    for (const row of rows || []) {
        const dest = _parseCidr(row.dest, family, false);
        if (!dest)
            return null;
        const route = Object.assign({}, copy(row.extra) || {}, {
            "dest": dest.address,
            "prefix": dest.prefix
        });
        const hop = String(row.nextHop ?? "").trim();
        if (hop !== "") {
            if (!isValidIp(hop, family))
                return null;
            route["next-hop"] = hop;
        }
        const metric = String(row.metric ?? "").trim();
        if (metric !== "") {
            if (!/^\d{1,10}$/.test(metric) || Number(metric) > 4294967295)
                return null;
            route.metric = Number(metric);
        }
        out.push(route);
    }
    return out;
}

function ipMethods(family) {
    return family === 6 ? ["auto", "dhcp", "manual", "link-local", "shared", "ignore", "disabled"] : ["auto", "manual", "link-local", "shared", "disabled"];
}

const _IP_STATIC_KEYS = ["address-data", "gateway", "dns-data", "dns-search"];
const _IP_DISALLOWED = {
    "4": {
        "link-local": _IP_STATIC_KEYS,
        "shared": ["dns-data", "dns-search"],
        "disabled": _IP_STATIC_KEYS
    },
    "6": {
        "link-local": _IP_STATIC_KEYS,
        "ignore": _IP_STATIC_KEYS,
        "disabled": _IP_STATIC_KEYS
    }
};

// Keys NetworkManager refuses to save with this method ("this property is not allowed for 'method=…'").
function disallowedIpKeys(family, method) {
    const table = _IP_DISALLOWED[family === 6 ? "6" : "4"];
    return (table[method] || []).slice();
}

// Drops what the new method rejects, restores stored values the old method had dropped,
// and removes a gateway left without an address (NetworkManager rejects that under any method).
function applyIpMethod(section, family, method, original) {
    const out = Object.assign({}, section || {});
    const before = disallowedIpKeys(family, out.method ?? "auto");
    const after = disallowedIpKeys(family, method);
    out.method = method;
    for (const key of _IP_STATIC_KEYS) {
        if (after.indexOf(key) >= 0)
            delete out[key];
        else if (before.indexOf(key) >= 0 && _absent(out[key]) && original && !_absent(original[key]))
            out[key] = copy(original[key]);
    }
    if ((out["address-data"] || []).length === 0)
        delete out.gateway;
    return out;
}

function isValidMac(text) {
    return /^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$/.test(String(text ?? "").trim());
}

const _MAC_KEYWORDS = ["preserve", "permanent", "random", "stable"];

// Returns "default", a keyword, "manual", or an unrecognized stored value verbatim.
function clonedMacMode(section) {
    const assigned = section ? section["assigned-mac-address"] : undefined;
    if (!_absent(assigned) && assigned !== "") {
        if (_MAC_KEYWORDS.indexOf(assigned) >= 0)
            return assigned;
        return isValidMac(assigned) ? "manual" : String(assigned);
    }
    const legacy = section ? section["cloned-mac-address"] : undefined;
    return !_absent(legacy) && legacy !== "" ? "manual" : "default";
}

function clonedMacAddress(section) {
    if (!section)
        return "";
    const assigned = section["assigned-mac-address"];
    if (isValidMac(assigned))
        return assigned;
    return _absent(assigned) || assigned === "" ? (section["cloned-mac-address"] ?? "") : "";
}

function applyClonedMac(section, mode, address) {
    const out = Object.assign({}, section || {});
    delete out["cloned-mac-address"];
    if (mode === "default")
        delete out["assigned-mac-address"];
    else
        out["assigned-mac-address"] = mode === "manual" ? String(address ?? "").trim() : mode;
    return out;
}

function linkNegotiation(eth) {
    if (eth && eth["auto-negotiate"] === true)
        return "auto";
    return eth && eth.speed > 0 ? "manual" : "ignore";
}

function applyLinkNegotiation(eth, mode, speed, duplex) {
    const out = Object.assign({}, eth || {});
    out["auto-negotiate"] = mode === "auto";
    if (mode === "manual") {
        out.speed = speed;
        out.duplex = duplex || "full";
    } else {
        delete out.speed;
        delete out.duplex;
    }
    return out;
}

const _WOL = {
    "disabled": 0,
    "magic": 0x40,
    "ignore": 0x8000
};

function wolMode(value) {
    if (_absent(value) || value === 1)
        return "default";
    for (const mode in _WOL) {
        if (_WOL[mode] === value)
            return mode;
    }
    return "0x" + Number(value).toString(16);
}

// undefined removes the key (NM default).
function wolValue(mode) {
    if (mode === "default")
        return undefined;
    if (mode in _WOL)
        return _WOL[mode];
    return parseInt(mode, 16);
}

const _SECURITY = "802-11-wireless-security";
const _SECURITY_MODES = ["wpa-psk", "sae", "owe", "wpa-eap"];

// key-mgmt "none" is static WEP, reported as "wep" so it can't be mistaken for an open network.
function securityMode(settings) {
    const sec = settings ? settings[_SECURITY] : undefined;
    if (_absent(sec))
        return "none";
    const km = String(sec["key-mgmt"] ?? "");
    if (km === "")
        return "none";
    if (_SECURITY_MODES.indexOf(km) >= 0)
        return km;
    return km === "none" ? "wep" : km;
}

const _WEP_KEYS = ["wep-key0", "wep-key1", "wep-key2", "wep-key3", "wep-key-flags", "wep-key-type", "wep-tx-keyidx"];

// Returns a new draft; removed sections are absent rather than null. For wpa-eap the
// draft's 802-1x is kept, or restored from original when an earlier switch dropped it;
// callers must pass original when mode is wpa-eap, or a draft without 802-1x gets none.
function applySecurityMode(draft, mode, password, original) {
    const out = Object.assign({}, draft || {});
    const previous = securityMode(out);
    if (mode !== "wpa-eap")
        delete out["802-1x"];
    else if (_absent(out["802-1x"]) && original && !_absent(original["802-1x"]))
        out["802-1x"] = copy(original["802-1x"]);
    if (mode === "none") {
        delete out[_SECURITY];
        return out;
    }
    const sec = Object.assign({}, out[_SECURITY] || {});
    sec["key-mgmt"] = mode;
    if (previous === "sae" && mode !== "sae")
        delete sec.pmf;
    if (previous !== mode)
        delete sec["auth-alg"];
    if (previous === "wep")
        _WEP_KEYS.forEach(k => delete sec[k]);
    if (mode === "wpa-psk" || mode === "sae") {
        if (!_absent(password) && password !== "")
            sec.psk = password;
        sec["psk-flags"] = 0;
        if (mode === "sae")
            sec.pmf = 3;
    } else {
        delete sec.psk;
        delete sec["psk-flags"];
    }
    out[_SECURITY] = sec;
    return out;
}

function isValidPsk(text) {
    const t = String(text ?? "");
    return /^[\x20-\x7e]{8,63}$/.test(t) || /^[0-9a-fA-F]{64}$/.test(t);
}

function isValidWgKey(text) {
    return /^[A-Za-z0-9+\/]{43}=$/.test(String(text ?? ""));
}

function isValidEndpoint(text) {
    const m = /^(?:\[([^\]]+)\]|([^\s:\[\]\/]+)):(\d{1,5})$/.exec(String(text ?? "").trim());
    if (!m || Number(m[3]) < 1 || Number(m[3]) > 65535)
        return false;
    return m[1] === undefined || isValidIp(m[1], 6);
}

// Kernel limit IFNAMSIZ - 1, counted in UTF-8 bytes.
function isValidIfname(text) {
    const t = String(text ?? "");
    if (t === "." || t === ".." || /[\s\/:]/.test(t))
        return false;
    let bytes = 0;
    for (const ch of t) {
        const cp = ch.codePointAt(0);
        bytes += cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    }
    return bytes >= 1 && bytes <= 15;
}

const _PEER_KEYS = ["public-key", "allowed-ips", "endpoint", "preshared-key", "persistent-keepalive"];

function wgPeerRows(peers) {
    return (peers || []).map(p => {
        const extra = {};
        for (const k in p) {
            if (_PEER_KEYS.indexOf(k) < 0)
                extra[k] = copy(p[k]);
        }
        return {
            "publicKey": p["public-key"] ?? "",
            "allowedIps": listText(p["allowed-ips"]),
            "endpoint": p.endpoint ?? "",
            "presharedKey": p["preshared-key"] ?? "",
            "keepalive": _absent(p["persistent-keepalive"]) ? "" : String(p["persistent-keepalive"]),
            "extra": extra
        };
    });
}

// null if any row is invalid. originalPeers are the loaded peers: clearing a
// PSK one of them had sends "preshared-key": null, since omission keeps it.
function wgPeersFromRows(rows, originalPeers) {
    const out = [];
    for (const row of rows || []) {
        const peer = {
            "public-key": String(row.publicKey ?? "").trim()
        };
        if (!isValidWgKey(peer["public-key"]))
            return null;
        const endpoint = String(row.endpoint ?? "").trim();
        if (endpoint !== "") {
            if (!isValidEndpoint(endpoint))
                return null;
            peer.endpoint = endpoint;
        }
        const ips = _tokens(row.allowedIps);
        if (!ips.every(ip => _parseCidr(ip, ip.indexOf(":") >= 0 ? 6 : 4, false)))
            return null;
        if (ips.length > 0)
            peer["allowed-ips"] = ips;
        Object.assign(peer, copy(row.extra) || {});
        const psk = String(row.presharedKey ?? "").trim();
        if (psk === "") {
            // Flags 1/2 mean NM stores no secret; keep them so the PSK stays agent-owned.
            if (_absent(peer["preshared-key-flags"]) || Number(peer["preshared-key-flags"]) === 0) {
                delete peer["preshared-key-flags"];
                const loaded = (originalPeers || []).find(p => p["public-key"] === peer["public-key"]);
                if (loaded && !_absent(loaded["preshared-key"]) && loaded["preshared-key"] !== "")
                    peer["preshared-key"] = null;
            }
        } else {
            if (!isValidWgKey(psk))
                return null;
            peer["preshared-key"] = psk;
            if (_absent(peer["preshared-key-flags"]))
                peer["preshared-key-flags"] = 0;
        }
        const keepalive = String(row.keepalive ?? "").trim();
        if (keepalive !== "") {
            if (!/^\d{1,5}$/.test(keepalive) || Number(keepalive) > 65535)
                return null;
            if (Number(keepalive) > 0)
                peer["persistent-keepalive"] = Number(keepalive);
        }
        out.push(peer);
    }
    return out;
}

function kvRows(dict, ownedKeys) {
    const out = [];
    for (const key in dict || {}) {
        if ((ownedKeys || []).indexOf(key) < 0 && dict[key] !== null)
            out.push({
                "key": key,
                "value": String(dict[key] ?? "")
            });
    }
    return out;
}

// Owned entries of base plus the rows; null on an empty, duplicate or owned key.
// Keys of original (stored secrets) no longer present get a null entry, since
// the backend keeps omitted secrets.
function kvFromRows(rows, base, ownedKeys, original) {
    const owned = ownedKeys || [];
    const out = {};
    for (const key of owned) {
        if (base && base[key] !== undefined)
            out[key] = base[key];
    }
    const seen = Object.create(null);
    for (const row of rows || []) {
        const key = String(row.key ?? "").trim();
        if (key === "" || seen[key] || owned.indexOf(key) >= 0)
            return null;
        seen[key] = true;
        out[key] = String(row.value ?? "");
    }
    for (const key in original || {}) {
        if (!_absent(original[key]) && !seen[key] && owned.indexOf(key) < 0)
            out[key] = null;
    }
    return out;
}

// Sets one vpn.secrets entry; clearing a stored one leaves a null entry so the
// backend deletes it. undefined when nothing is left.
function secretsWith(secrets, key, text, original) {
    const out = Object.assign({}, secrets || {});
    if (text !== "")
        out[key] = text;
    else if (original && !_absent(original[key]))
        out[key] = null;
    else
        delete out[key];
    return Object.keys(out).length > 0 ? out : undefined;
}

// NM secret flags: bit 2 (value "2") means not saved, asked on connect.
function secretSaved(data, key) {
    const flags = data ? data[key + "-flags"] : undefined;
    return _absent(flags) || (Number(flags) & 2) === 0;
}

function withSecretSaved(data, key, saved) {
    const out = Object.assign({}, data || {});
    out[key + "-flags"] = saved ? "0" : "2";
    return out;
}

// Sets one vpn.data entry (blank removes it); other keys, the *-flags ones included, are kept. An empty result is undefined.
function withDataEntry(data, key, value) {
    const out = Object.assign({}, data || {});
    const t = String(value ?? "").trim();
    if (t === "")
        delete out[key];
    else
        out[key] = t;
    return Object.keys(out).length === 0 ? undefined : out;
}

// Enterprise (802.1X) form state -> EnterpriseConfig sent to the backend.
function enterpriseConfig(s) {
    let identity = s.identity.trim();
    if (identity && s.usernameSuffix && identity.indexOf("@") < 0)
        identity += "@" + s.usernameSuffix;
    const cfg = {
        "eap": s.eap,
        "identity": identity,
        "ca": s.eap === "pwd" ? "none" : s.ca
    };
    const inner = s.eap === "peap" || s.eap === "ttls";
    if (inner) {
        cfg.phase2 = s.phase2;
        if (s.anonymousIdentity.trim())
            cfg.anonymousIdentity = s.anonymousIdentity.trim();
    }
    if (!s.savePassword)
        cfg.askPassword = true;
    else if (s.eap === "tls" && s.privateKeyPassword)
        cfg.privateKeyPassword = s.privateKeyPassword;
    else if (s.eap !== "tls" && s.password)
        cfg.password = s.password;
    if (s.eap === "tls") {
        if (s.clientCertPath)
            cfg.clientCertPath = s.clientCertPath;
        if (s.privateKeyPath)
            cfg.privateKeyPath = s.privateKeyPath;
    }
    if (s.eap !== "pwd") {
        if (cfg.ca === "file" && s.caCertPem)
            cfg.caCertPem = s.caCertPem;
        else if (cfg.ca === "file" && s.caCertPath)
            cfg.caCertPath = s.caCertPath;
        const server = s.serverDomain.trim();
        if (server) {
            cfg.serverDomain = server;
            if (s.serverDomainSuffix)
                cfg.serverDomainSuffix = true;
        }
    }
    if (s.eap === "peap" && s.peapVersion)
        cfg.peapVersion = s.peapVersion;
    if (s.eap !== "pwd") {
        if (s.authFlags)
            cfg.authFlags = s.authFlags;
        if (s.opensslCiphers.trim())
            cfg.opensslCiphers = s.opensslCiphers.trim();
    }
    return cfg;
}

// opts: {usernameSuffix, usernameSuffixRequired, storedFiles}; storedFiles keys ca/clientCert mark blobs NM already holds.
function enterpriseConfigValid(cfg, opts) {
    const o = opts || {};
    const stored = o.storedFiles || {};
    if (!cfg.identity)
        return false;
    if (o.usernameSuffixRequired && !identityMatchesSuffix(cfg.identity, o.usernameSuffix))
        return false;
    if (!cfg.askPassword && cfg.eap !== "tls" && !cfg.password)
        return false;
    if (cfg.eap === "tls" && !cfg.clientCertPath && !stored.clientCert)
        return false;
    if (cfg.ca === "file" && !cfg.caCertPath && !cfg.caCertPem && !stored.ca)
        return false;
    if (cfg.ca === "system" && !cfg.serverDomain)
        return false;
    return true;
}

function identityMatchesSuffix(identity, suffix) {
    if (!suffix || identity.indexOf("@") < 0)
        return true;
    return identity.slice(identity.lastIndexOf("@") + 1).toLowerCase() === suffix.toLowerCase();
}

function withFlags(flags, mask, on) {
    return (on ? (flags | mask) : (flags & ~mask)) >>> 0;
}

var VPN_FORM_KEYS = {
    "openvpn": {
        "data": ["remote", "connection-type", "ca", "cert", "key", "cert-pass-flags", "username", "password-flags", "static-key", "static-key-direction", "local-ip", "remote-ip", "port", "proto-tcp", "dev-type", "cipher", "auth", "tunnel-mtu", "ta", "ta-dir"],
        "secrets": ["password", "cert-pass"]
    },
    "openconnect": {
        "data": ["gateway", "protocol", "cacert", "usercert", "userkey", "proxy"],
        "secrets": []
    }
};

const _VPN_DATA_DEFAULTS = {
    "openvpn": {
        "connection-type": "tls"
    },
    "openconnect": {
        "protocol": "anyconnect",
        "cookie-flags": "2",
        "gateway-flags": "2",
        "gwcert-flags": "2"
    }
};

function vpnForm(serviceType) {
    const t = String(serviceType ?? "");
    for (const form in VPN_FORM_KEYS) {
        if (t.endsWith("." + form))
            return form;
    }
    return "";
}

// sections: an array, or a function(settings) for types whose sections depend on the profile.
var CONNECTION_TYPES = [
    {
        "type": "802-3-ethernet",
        "group": "ethernet",
        "icon": "lan",
        "addable": true,
        "sections": ["general", "ethernet", "security", "ipv4", "ipv6"]
    },
    {
        "type": "802-11-wireless",
        "group": "wifi",
        "icon": "wifi",
        "addable": true,
        "sections": ["general", "wifi", "security", "ipv4", "ipv6"]
    },
    {
        "type": "wireguard",
        "group": "vpn",
        "icon": "vpn_key",
        "addable": true,
        "autoconnect": false,
        "sections": ["general", "wireguard", "ipv4", "ipv6"]
    },
    {
        "type": "vpn",
        "group": "vpn",
        "icon": "vpn_lock",
        "addable": true,
        "autoconnect": false,
        "sections": s => {
            const out = ["general"];
            const form = vpnForm(s.vpn ? s.vpn["service-type"] : "");
            if (form !== "")
                out.push(form);
            out.push("vpnData");
            for (const ip of ["ipv4", "ipv6"]) {
                if (!_absent(s[ip]))
                    out.push(ip);
            }
            return out;
        }
    },
    {
        "type": "gsm",
        "group": "cellular",
        "icon": "signal_cellular_alt",
        "addable": true,
        "autoconnect": false,
        "sections": ["general", "mobile", "ppp", "ipv4", "ipv6"]
    },
    {
        "type": "cdma",
        "group": "cellular",
        "icon": "signal_cellular_alt",
        "addable": false,
        "sections": ["general", "mobile", "ppp", "ipv4", "ipv6"]
    },
    {
        "type": "bluetooth",
        "group": "other",
        "icon": "bluetooth",
        "addable": false,
        "sections": s => {
            const out = ["general", "bluetooth"];
            if (s.bluetooth && s.bluetooth.type === "dun")
                out.push("mobile", "ppp");
            for (const ip of ["ipv4", "ipv6"]) {
                if (!_absent(s[ip]))
                    out.push(ip);
            }
            return out;
        }
    }
];

var GROUPS = ["ethernet", "wifi", "vpn", "cellular", "other"];

function typeInfo(type) {
    return CONNECTION_TYPES.find(t => t.type === type) || null;
}

function groupOf(type) {
    const info = typeInfo(type);
    if (info)
        return info.group;
    switch (String(type ?? "").split(":")[0]) {
    case "vpn":
    case "wireguard":
        return "vpn";
    case "gsm":
    case "cdma":
        return "cellular";
    default:
        return "other";
    }
}

// portType is the controller's type for a port profile, "" otherwise.
function isSupported(type, portType) {
    return typeInfo(type) !== null && (!portType || typeInfo(portType) !== null);
}

function sectionsFor(type, settings) {
    const info = typeInfo(type);
    return typeof info.sections === "function" ? info.sections(settings || {}) : info.sections.slice();
}

// Reads the 1.46+ names or their legacy aliases (master, slave-type).
function portOf(settings) {
    const c = settings ? settings.connection : undefined;
    if (!c)
        return null;
    const controller = c.controller || c.master;
    if (!controller)
        return null;
    return {
        "controller": controller,
        "type": c["port-type"] || c["slave-type"] || ""
    };
}

// NM ignores apn while auto-config is on, so the two move together.
// A stored profile without auto-config already has it off (NM's default), so an APN edit leaves the key out.
function applyApn(gsm, apn, original) {
    const out = Object.assign({}, gsm || {});
    const t = String(apn ?? "").trim();
    if (t === "") {
        delete out.apn;
        if (original && _absent(original.apn)) {
            if (_absent(original["auto-config"]))
                delete out["auto-config"];
            else
                out["auto-config"] = original["auto-config"];
        } else {
            out["auto-config"] = true;
        }
    } else {
        out.apn = t;
        if (original && original["auto-config"] === undefined)
            delete out["auto-config"];
        else
            out["auto-config"] = false;
    }
    return out;
}

function pppEcho(ppp) {
    return Number(ppp ? ppp["lcp-echo-interval"] : 0) > 0;
}

function applyPppEcho(ppp, on) {
    const out = Object.assign({}, ppp || {});
    if (on) {
        out["lcp-echo-interval"] = 30;
        out["lcp-echo-failure"] = 5;
    } else {
        delete out["lcp-echo-interval"];
        delete out["lcp-echo-failure"];
    }
    return out;
}

const _CHANNELS_A = [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165];

function hotspotChannels(band) {
    if (band === "bg")
        return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];
    return band === "a" ? _CHANNELS_A.slice() : [];
}

function isValidHotspotAddress(text) {
    const c = _parseCidr(text, 4, true);
    if (!c || c.prefix < 8 || c.prefix > 30)
        return false;
    const ip = c.address.split(".").reduce((n, p) => n * 256 + Number(p), 0);
    const host = ip % Math.pow(2, 32 - c.prefix);
    return host !== 0 && host !== Math.pow(2, 32 - c.prefix) - 1;
}

// type is a connection type, or "vpn:<service-type>" for a VPN plugin profile.
function newConnectionSettings(type, opts) {
    const colon = String(type ?? "").indexOf(":");
    const service = colon >= 0 ? type.slice(colon + 1) : "";
    if (colon >= 0)
        type = type.slice(0, colon);
    const s = {
        "connection": {
            "id": (opts && opts.name) || "",
            "type": type,
            "autoconnect": typeInfo(type)?.autoconnect !== false
        },
        "ipv4": {
            "method": "auto"
        },
        "ipv6": {
            "method": "auto"
        }
    };
    switch (type) {
    case "802-3-ethernet":
        s["802-3-ethernet"] = {};
        break;
    case "802-11-wireless":
        s["802-11-wireless"] = {
            "ssid": "",
            "mode": "infrastructure"
        };
        break;
    case "wireguard":
        s.connection["interface-name"] = "wg0";
        s.wireguard = opts && opts.privateKey ? {
            "private-key": opts.privateKey
        } : {};
        s.ipv4.method = "manual";
        s.ipv6.method = "ignore";
        break;
    case "vpn":
        s.vpn = {
            "data": copy(_VPN_DATA_DEFAULTS[vpnForm(service)]) || {}
        };
        if (service !== "")
            s.vpn["service-type"] = service;
        break;
    case "gsm":
        s.gsm = {
            "auto-config": true
        };
        break;
    }
    return s;
}

// Input keeps the backend's ID order; sorting is stable, so it survives within each group.
function groupProfiles(profiles) {
    const out = [];
    for (const group of GROUPS) {
        const members = (profiles || []).filter(p => groupOf(p.type) === group);
        if (members.length === 0)
            continue;
        members.sort((a, b) => (b.active ? 1 : 0) - (a.active ? 1 : 0));
        out.push({
            "group": group,
            "profiles": members
        });
    }
    return out;
}

function lastUsed(timestamp, nowSec) {
    if (!timestamp)
        return "never";
    const then = new Date(timestamp * 1000);
    const now = new Date(nowSec * 1000);
    const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    if (sameDay(then, now))
        return "today";
    if (sameDay(then, new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)))
        return "yesterday";
    return "date";
}
