.pragma library

// The Go core names overlays <Base>-dms-<8 hex>; anything else is not an overlay.
const OVERLAY = /^(.+)-dms-[0-9a-f]{8}$/;
const UNMANAGED = "System Default";
// The pack its own command builds in theme colors; the Go core runs it as a generation.
const SELF = "dux-icons";
const CLEAR = "clear";
const APPLY = "apply:";
// "apply:<pack>", or "apply/<style>:<pack>" when the self-built pack is not drawn its default way.
const REQUEST = /^apply(?:\/([^:]*))?:(.*)$/;
// Badge outlines on the 64-unit canvas the pack's templates use; the first is drawn when no shape is asked for.
const OUTLINES = {
    circle: '<circle cx="32" cy="32" r="32"/>',
    squircle: '<path d="M64 32C64 36.22 63.93 41.69 63.8 44.66C63.67 47.62 63.47 48.3 63.21 49.79C62.94 51.27 62.61 52.44 62.21 53.56C61.8 54.69 61.33 55.64 60.78 56.53C60.23 57.42 59.62 58.2 58.91 58.91C58.2 59.62 57.42 60.23 56.53 60.78C55.64 61.33 54.69 61.8 53.56 62.21C52.44 62.61 51.27 62.94 49.79 63.21C48.3 63.47 47.62 63.67 44.66 63.8C41.69 63.93 36.22 64 32 64C27.78 64 22.31 63.93 19.34 63.8C16.38 63.67 15.7 63.47 14.21 63.21C12.73 62.94 11.56 62.61 10.44 62.21C9.31 61.8 8.36 61.33 7.47 60.78C6.58 60.23 5.8 59.62 5.09 58.91C4.38 58.2 3.77 57.42 3.22 56.53C2.67 55.64 2.2 54.69 1.79 53.56C1.39 52.44 1.06 51.27 0.79 49.79C0.53 48.3 0.33 47.62 0.2 44.66C0.07 41.69 0 36.22 0 32C0 27.78 0.07 22.31 0.2 19.34C0.33 16.38 0.53 15.7 0.79 14.21C1.06 12.73 1.39 11.56 1.79 10.44C2.2 9.31 2.67 8.36 3.22 7.47C3.77 6.58 4.38 5.8 5.09 5.09C5.8 4.38 6.58 3.77 7.47 3.22C8.36 2.67 9.31 2.2 10.44 1.79C11.56 1.39 12.73 1.06 14.21 0.79C15.7 0.53 16.38 0.33 19.34 0.2C22.31 0.07 27.78 0 32 0C36.22 0 41.69 0.07 44.66 0.2C47.62 0.33 48.3 0.53 49.79 0.79C51.27 1.06 52.44 1.39 53.56 1.79C54.69 2.2 55.64 2.67 56.53 3.22C57.42 3.77 58.2 4.38 58.91 5.09C59.62 5.8 60.23 6.58 60.78 7.47C61.33 8.36 61.8 9.31 62.21 10.44C62.61 11.56 62.94 12.73 63.21 14.21C63.47 15.7 63.67 16.38 63.8 19.34C63.93 22.31 64 27.78 64 32Z"/>',
    rounded: '<rect width="64" height="64" rx="14"/>',
    square: '<rect width="64" height="64"/>',
    hexagon: '<path d="M29.5 0.67A5 5 0 0 1 34.5 0.67L57.88 14.17A5 5 0 0 1 60.38 18.5L60.38 45.5A5 5 0 0 1 57.88 49.83L34.5 63.33A5 5 0 0 1 29.5 63.33L6.12 49.83A5 5 0 0 1 3.62 45.5L3.62 18.5A5 5 0 0 1 6.12 14.17Z"/>',
    cookie: '<path d="M62.42 32C62.79 33.14 63.21 34.34 63.34 35.53C63.47 36.72 63.46 37.97 63.2 39.12C62.94 40.27 62.4 41.4 61.77 42.42C61.14 43.43 60.23 44.34 59.41 45.2C58.58 46.06 57.62 46.79 56.81 47.59C56 48.39 55.23 49.12 54.55 49.98C53.86 50.83 53.31 51.75 52.72 52.72C52.12 53.69 51.62 54.78 50.97 55.78C50.31 56.78 49.63 57.86 48.78 58.7C47.93 59.54 46.94 60.32 45.88 60.83C44.82 61.34 43.6 61.63 42.42 61.77C41.23 61.9 39.96 61.76 38.77 61.66C37.58 61.55 36.41 61.25 35.28 61.12C34.15 60.98 33.09 60.84 32 60.84C30.91 60.84 29.85 60.98 28.72 61.12C27.59 61.25 26.42 61.55 25.23 61.66C24.04 61.76 22.77 61.9 21.58 61.77C20.4 61.63 19.18 61.34 18.12 60.83C17.06 60.32 16.07 59.54 15.22 58.7C14.37 57.86 13.69 56.78 13.03 55.78C12.38 54.78 11.88 53.69 11.28 52.72C10.69 51.75 10.14 50.83 9.45 49.98C8.77 49.12 8 48.39 7.19 47.59C6.38 46.79 5.42 46.06 4.59 45.2C3.77 44.34 2.86 43.43 2.23 42.42C1.6 41.4 1.06 40.27 0.8 39.12C0.54 37.97 0.53 36.72 0.66 35.53C0.79 34.34 1.21 33.14 1.58 32C1.95 30.86 2.5 29.79 2.88 28.72C3.27 27.65 3.64 26.65 3.89 25.58C4.13 24.52 4.23 23.45 4.34 22.32C4.46 21.19 4.44 19.99 4.59 18.8C4.75 17.62 4.9 16.35 5.3 15.22C5.69 14.1 6.25 12.97 6.98 12.05C7.72 11.13 8.69 10.34 9.7 9.7C10.71 9.06 11.92 8.64 13.03 8.22C14.15 7.8 15.34 7.56 16.41 7.19C17.49 6.82 18.5 6.49 19.49 6.02C20.47 5.54 21.37 4.96 22.32 4.34C23.28 3.73 24.21 2.96 25.23 2.34C26.26 1.73 27.34 1.05 28.47 0.66C29.6 0.27 30.82 0 32 0C33.18 0 34.4 0.27 35.53 0.66C36.66 1.05 37.74 1.73 38.77 2.34C39.79 2.96 40.72 3.73 41.68 4.34C42.63 4.96 43.53 5.54 44.51 6.02C45.5 6.49 46.51 6.82 47.59 7.19C48.66 7.56 49.85 7.8 50.97 8.22C52.08 8.64 53.29 9.06 54.3 9.7C55.31 10.34 56.28 11.13 57.02 12.05C57.75 12.97 58.31 14.1 58.7 15.22C59.1 16.35 59.25 17.62 59.41 18.8C59.56 19.99 59.54 21.19 59.66 22.32C59.77 23.45 59.87 24.52 60.11 25.58C60.36 26.65 60.73 27.65 61.12 28.72C61.5 29.79 62.05 30.86 62.42 32Z"/>',
    clover: '<path d="M29.14 5.10A4.0 4.0 0 0 0 34.86 5.10A17.0 17.0 0 1 1 58.90 29.14A4.0 4.0 0 0 0 58.90 34.86A17.0 17.0 0 1 1 34.86 58.90A4.0 4.0 0 0 0 29.14 58.90A17.0 17.0 0 1 1 5.10 34.86A4.0 4.0 0 0 0 5.10 29.14A17.0 17.0 0 1 1 29.14 5.10Z"/>'
};
const SHAPES = Object.keys(OUTLINES);

function isOverlay(name) {
    return OVERLAY.test(name || "");
}

function baseName(name) {
    const match = OVERLAY.exec(name || "");
    return match ? match[1] : (name || "");
}

// Shell form of baseName(); both must strip the same suffix.
function shBase(variable) {
    return "${" + variable + "%-dms-" + "[0-9a-f]".repeat(8) + "}";
}

function isSelf(name) {
    return name === SELF;
}

// What a picker shows for a theme; the stored value stays the directory name.
function label(name) {
    return name === SELF ? "Dux Icons" : name;
}

function generates(picked, recolor) {
    return picked === SELF || (!!recolor && !!picked && picked !== UNMANAGED);
}

// Shell line listing the self-built pack once its command is installed, built or not.
function shListSelf() {
    return `{ command -v ${SELF} || [ -x "$HOME/.local/bin/${SELF}" ]; } >/dev/null 2>&1 && echo ${SELF}`;
}

function parseState(text) {
    try {
        const state = JSON.parse(text);
        if (state && typeof state.base === "string" && typeof state.applied === "string")
            return state;
    } catch (e) {}
    return null;
}

function covers(state, picked) {
    return !!state && !!picked && picked !== UNMANAGED && state.base === picked && isOverlay(state.applied) && baseName(state.applied) === picked;
}

// Ignores states not naming an overlay of the picked pack: the name reaches shell and sed arguments.
function appliedName(picked, enabled, state) {
    return enabled && covers(state, picked) ? state.applied : picked;
}

// The recolored files of the picked pack, or null; the shell's icon index stays on that pack.
function manifest(picked, enabled, state) {
    if (!enabled || !covers(state, picked))
        return null;
    const dir = state.dir;
    if (typeof dir !== "string" || !dir.startsWith("/") || dir.split("/").pop() !== state.applied)
        return null;
    if (!state.icons || typeof state.icons !== "object")
        return null;
    return {
        dir,
        icons: state.icons
    };
}

// The self-built pack is a whole theme, so the shell indexes the generation itself.
function indexName(picked, enabled, state) {
    return enabled && picked === SELF && covers(state, picked) ? state.applied : picked;
}

function iconUrl(found, name) {
    const rel = found && name ? found.icons[name] : "";
    // Anything but a string is an inherited member, not an entry.
    if (typeof rel !== "string" || rel === "" || rel.startsWith("/") || rel.split("/").includes(".."))
        return "";
    return "file://" + found.dir + "/" + rel;
}

function isOwn(platform, lastApplied, picks) {
    return platform === lastApplied || picks.includes(baseName(platform));
}

// Saves the platform theme once; the picked pack and its overlays are DMS's own and skipped.
function backupScript(quotedFile, readCommand, quotedPicked) {
    return `b=${quotedFile}; [ -e "$b" ] && exit 0; cur=$(${readCommand}); cur=${shBase("cur")}; case "$cur" in ''|${quotedPicked}) ;; *) mkdir -p "$(dirname "$b")" && printf '%s\\n' "$cur" > "$b" ;; esac`;
}

function shapes() {
    return SHAPES;
}

function shapeUrl(shape, color) {
    return "data:image/svg+xml;utf8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="${color}">${OUTLINES[shape]}</svg>`);
}

// The self-built pack's drawing style as one string. The shape is always named, so the pack's own default never shows.
function style(monoApps, shape, gradient) {
    const parts = [];
    if (monoApps)
        parts.push("mono");
    if (gradient)
        parts.push("gradient");
    if (SHAPES.includes(shape))
        parts.push("shape=" + shape);
    return parts.join(",");
}

// The flags of a style, for `icon-folders` ("") or a theme run ("icon-").
function styleArgs(style, prefix) {
    const flags = [];
    for (const part of (style || "").split(",")) {
        if (part === "mono")
            flags.push(`--${prefix}mono-apps`);
        else if (part === "gradient")
            flags.push(`--${prefix}gradient`);
        else if (part.startsWith("shape="))
            flags.push(`--${prefix}shape`, part.substring(6));
    }
    return flags;
}

function wanted(picked, recolor, present, style) {
    if (generates(picked, recolor))
        return picked === SELF && style ? `apply/${style}:${picked}` : APPLY + picked;
    return present ? CLEAR : "";
}

function packOf(want) {
    const match = REQUEST.exec(want);
    return match ? match[2] : "";
}

function args(want, mode, stateDir) {
    const base = ["matugen", "icon-folders", "--state-dir", stateDir];
    if (want === CLEAR)
        return base.concat(["--clear"]);
    const match = REQUEST.exec(want);
    return base.concat(["--icon-theme", match[2], "--mode", mode], styleArgs(match[1], ""));
}

// Retries once when the state on disk names another overlay: older args landed last.
function needsRun(want, done, retried, generated, covered) {
    if (want !== done)
        return true;
    return generated && !covered && retried !== want;
}

// One theme directory name per line, plus a SYSDEFAULT:<name> line for the platform's current theme.
function parseThemeList(output) {
    const themes = [UNMANAGED];
    let systemDefault = null;
    for (const raw of (output || "").split("\n")) {
        const line = raw.trim();
        if (line.startsWith("SYSDEFAULT:")) {
            systemDefault = baseName(line.substring(11).trim());
            continue;
        }
        if (line && !isOverlay(line) && !themes.includes(line))
            themes.push(line);
    }
    return {
        systemDefault,
        themes
    };
}

function parseProbe(text) {
    try {
        const probe = JSON.parse(text);
        if (probe && typeof probe.supported === "boolean")
            return {
                supported: probe.supported,
                code: typeof probe.code === "string" ? probe.code : "",
                reason: typeof probe.reason === "string" ? probe.reason : ""
            };
    } catch (e) {}
    return null;
}

// `dms icon-theme list`: each theme's name mapped to whether it can be removed and the files that preview it.
function parseLibrary(text) {
    const themes = {};
    try {
        for (const theme of JSON.parse(text).themes) {
            if (theme && typeof theme.name === "string" && Array.isArray(theme.icons))
                themes[theme.name] = {
                    removable: theme.removable === true,
                    icons: theme.icons.filter(file => typeof file === "string" && file.startsWith("/"))
                };
        }
    } catch (e) {}
    return themes;
}

// `dms icon-theme list`: each cursor theme mapped to whether it can be removed and its default pointer.
function parseCursorLibrary(text) {
    const cursors = {};
    try {
        for (const cursor of JSON.parse(text).cursors) {
            if (cursor && typeof cursor.name === "string") {
                const pointer = typeof cursor.pointer === "string" && cursor.pointer.startsWith("data:image/png;base64,") ? cursor.pointer : "";
                cursors[cursor.name] = {
                    removable: cursor.removable === true,
                    pointer: pointer
                };
            }
        }
    } catch (e) {}
    return cursors;
}

// `dms icon-theme install|remove`: the themes it touched, or a refusal's code with the themes in the way.
function parseReply(text) {
    const reply = {
        themes: [],
        code: "",
        reason: ""
    };
    try {
        const parsed = JSON.parse(text);
        if (Array.isArray(parsed.themes))
            reply.themes = parsed.themes.filter(name => typeof name === "string");
        if (typeof parsed.code === "string")
            reply.code = parsed.code;
        if (typeof parsed.error === "string")
            reply.reason = parsed.error;
    } catch (e) {}
    return reply;
}
