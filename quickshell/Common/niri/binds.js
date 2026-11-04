.pragma library

const ESCAPES = {
    "n": "\n",
    "t": "\t"
};

// Splits an action the way KDL reads node arguments: spaces separate, "…" keeps spaces, backslash escapes.
function tokens(text) {
    const s = String(text ?? "");
    const out = [];
    let cur = "";
    let started = false;
    let quoted = false;
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (quoted) {
            if (c === "\\" && i + 1 < s.length) {
                i++;
                cur += ESCAPES[s[i]] ?? s[i];
            } else if (c === "\"") {
                quoted = false;
            } else {
                cur += c;
            }
        } else if (c === "\"") {
            quoted = true;
            started = true;
        } else if (/\s/.test(c)) {
            if (started)
                out.push(cur);
            cur = "";
            started = false;
        } else {
            cur += c;
            started = true;
        }
    }
    if (started)
        out.push(cur);
    return out;
}

// What a spawn-like bind runs, as its compositor would: niri's spawn is an argument list with no shell,
// spawn-sh and the other compositors' spawn, spawn_shell and exec give sh one command line.
// null when the action spawns nothing, [] when it spawns but names no program.
function spawnArgv(action, provider) {
    const m = String(action ?? "").trim().match(/^(spawn|spawn-sh|spawn_shell|exec)(?:\s+([\s\S]*))?$/);
    if (!m)
        return null;
    const rest = (m[2] ?? "").trim();
    const parts = tokens(rest);
    if (m[1] === "spawn" && provider === "niri")
        return parts;
    // A quoted spawn-sh line is one token; an unquoted one is the line itself
    const line = m[1] === "spawn-sh" && parts.length === 1 ? parts[0] : rest;
    return line ? ["sh", "-c", line] : [];
}

// niri msg argv for a niri bind action: key=value properties become --key flags.
function niriActionArgv(action) {
    const argv = ["niri", "msg", "action"];
    for (const part of tokens(action)) {
        const eq = part.indexOf("=");
        if (eq <= 0) {
            argv.push(part);
            continue;
        }
        const key = part.slice(0, eq);
        const value = part.slice(eq + 1);
        if (key !== "skip-confirmation")
            argv.push("--" + key + "=" + value);
        else if (value === "true")
            argv.push("--skip-confirmation");
    }
    return argv;
}
