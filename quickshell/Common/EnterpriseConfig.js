.pragma library

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
