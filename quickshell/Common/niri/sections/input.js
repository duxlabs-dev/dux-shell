.pragma library
.import "../keymaps.js" as Keymaps

// Everything but warp already lives in SettingsData and reaches dms/input.kdl or dms/cursor.kdl (K2).
var defaults = { "input.warp": false };

var stored = {
    "input.layouts": "SettingsData:keyboardLayouts",
    "input.xkbOptions": "SettingsData:keyboardOptions",
    "input.variants": "SettingsData:keyboardVariants",
    "input.model": "SettingsData:keyboardModel",
    "input.keymapFile": "SettingsData:keyboardKeymapFile",
    "input.trackLayout": "SettingsData:keyboardTrackLayout",
    "input.numlock": "SettingsData:keyboardNumlock",
    "input.repeatDelay": "SettingsData:keyboardRepeatDelay",
    "input.repeatRate": "SettingsData:keyboardRepeatRate",
    "input.focusFollowsMouse": "SettingsData:focusFollowsMouse",
    "input.warp": "page",
    "input.tap": "SettingsData:touchpadTapToClick",
    "input.touchpadNatural": "SettingsData:touchpadNaturalScroll",
    "input.touchpadSpeed": "SettingsData:touchpadAccelSpeed",
    "input.touchpadScroll": "SettingsData:touchpadScrollFactor",
    "input.tapDrag": "SettingsData:touchpadTapAndDrag",
    "input.dragLock": "SettingsData:touchpadDragLock",
    "input.touchpadProfile": "SettingsData:touchpadAccelProfile",
    "input.touchpadScrollMethod": "SettingsData:touchpadScrollMethod",
    "input.clickMethod": "SettingsData:touchpadClickMethod",
    "input.dwt": "SettingsData:touchpadDisableWhileTyping",
    "input.dwtExternal": "SettingsData:touchpadDisableOnExternalMouse",
    "input.touchpadMiddle": "SettingsData:touchpadMiddleEmulation",
    "input.mouseSpeed": "SettingsData:mouseAccelSpeed",
    "input.mouseNatural": "SettingsData:mouseNaturalScroll",
    "input.mouseScroll": "SettingsData:mouseScrollFactor",
    "input.leftHanded": "SettingsData:mouseLeftHanded",
    "input.mouseProfile": "SettingsData:mouseAccelProfile",
    "input.mouseScrollMethod": "SettingsData:mouseScrollMethod",
    "input.mouseMiddle": "SettingsData:mouseMiddleEmulation",
    // The cursor rows edit fields of one object through SettingsData helpers, so they carry no settingKey.
    "input.cursorTheme": "SettingsData:cursorSettings",
    "input.cursorSize": "SettingsData:cursorSettings",
    "input.hideTyping": "SettingsData:cursorSettings",
    "input.hideIdle": "SettingsData:cursorSettings"
};

var search = [
    { key: "input.layouts", title: "Keyboard layout", words: ["keyboard", "layout", "xkb", "language"] },
    { key: "input.xkbOptions", title: "Switch layout shortcut", words: ["switch", "layout", "shortcut", "xkb", "options", "compose"] },
    { key: "input.variants", title: "Variant", words: ["variant", "xkb", "colemak", "dvorak"] },
    { key: "input.model", title: "Model", words: ["model", "xkb", "pc104"] },
    { key: "input.keymapFile", title: "Keymap file", words: ["keymap", "file", "xkb"] },
    { key: "input.trackLayout", title: "Remember layout", words: ["remember", "layout", "window", "track"] },
    { key: "input.numlock", title: "Num Lock at startup", words: ["numlock", "num", "lock", "startup"] },
    { key: "input.repeatDelay", title: "Repeat delay", words: ["repeat", "delay", "key"] },
    { key: "input.repeatRate", title: "Repeat rate", words: ["repeat", "rate", "speed"] },
    { key: "input.focusFollowsMouse", title: "Focus follows mouse", words: ["focus", "follows", "mouse", "hover", "sloppy"] },
    { key: "input.warp", title: "Pointer jumps to focus", words: ["warp", "pointer", "jump", "focus"] },
    { key: "input.tap", title: "Tap to click", words: ["tap", "click", "touchpad"] },
    { key: "input.touchpadNatural", title: "Natural scrolling", words: ["natural", "scroll", "direction", "touchpad"] },
    { key: "input.touchpadSpeed", title: "Touchpad pointer speed", words: ["pointer", "speed", "acceleration", "sensitivity", "touchpad"] },
    { key: "input.touchpadScroll", title: "Touchpad scroll speed", words: ["scroll", "speed", "factor", "touchpad"] },
    { key: "input.tapDrag", title: "Tap and drag", words: ["tap", "drag", "touchpad"] },
    { key: "input.dragLock", title: "Drag lock", words: ["drag", "lock", "touchpad"] },
    { key: "input.touchpadProfile", title: "Touchpad acceleration profile", words: ["acceleration", "profile", "flat", "adaptive", "touchpad"] },
    { key: "input.touchpadScrollMethod", title: "Touchpad scroll method", words: ["scroll", "method", "two-finger", "edge", "touchpad"] },
    { key: "input.clickMethod", title: "Click method", words: ["click", "method", "clickfinger", "button", "areas"] },
    { key: "input.dwt", title: "Disable while typing", words: ["disable", "typing", "dwt", "touchpad"] },
    { key: "input.dwtExternal", title: "Disable with external mouse", words: ["disable", "external", "mouse", "touchpad"] },
    { key: "input.touchpadMiddle", title: "Touchpad middle click emulation", words: ["middle", "click", "emulation", "touchpad"] },
    { key: "input.mouseSpeed", title: "Mouse pointer speed", words: ["mouse", "pointer", "speed", "acceleration", "sensitivity"] },
    { key: "input.mouseNatural", title: "Mouse natural scrolling", words: ["mouse", "natural", "scroll"] },
    { key: "input.mouseScroll", title: "Mouse scroll speed", words: ["mouse", "scroll", "speed", "wheel"] },
    { key: "input.leftHanded", title: "Left-handed", words: ["left", "handed", "mouse", "buttons", "swap"] },
    { key: "input.mouseProfile", title: "Mouse acceleration profile", words: ["mouse", "acceleration", "profile", "flat", "adaptive"] },
    { key: "input.mouseScrollMethod", title: "Mouse scroll method", words: ["mouse", "scroll", "method", "button"] },
    { key: "input.mouseMiddle", title: "Mouse middle click emulation", words: ["mouse", "middle", "click", "emulation"] },
    { key: "input.cursorTheme", title: "Cursor Theme", words: ["cursor", "pointer", "theme", "xcursor"] },
    { key: "input.cursorSize", title: "Cursor Size", words: ["cursor", "size", "bigger"] },
    { key: "input.hideTyping", title: "Hide cursor while typing", words: ["hide", "cursor", "typing"] },
    { key: "input.hideIdle", title: "Hide cursor when idle", words: ["hide", "cursor", "idle", "inactive", "timeout"] }
];

// A wrong value can leave the user unable to type: the section asks « keep? » and goes back after 15 s.
var risky = ["input.layouts", "input.xkbOptions", "input.variants", "input.model", "input.keymapFile"];

// The first six letters of the first layout, as the Keybinds board draws them.
function topRow(layouts) {
    const code = String(layouts || "").split(",")[0].trim().toLowerCase();
    return Keymaps.rows(code)[2].filter(key => key.sym !== undefined).slice(0, 6).map(key => key.label).join("");
}

var switchGroups = ["grp:alt_shift_toggle", "grp:ctrl_shift_toggle", "grp:caps_toggle", "grp:win_space_toggle"];

function _options(text) {
    return String(text || "").split(",").map(o => o.trim()).filter(o => o !== "");
}

// The known layout-switch option in an xkb options list, or "" for none or a custom one.
function switchOf(options) {
    return _options(options).find(o => switchGroups.indexOf(o) >= 0) || "";
}

function withSwitch(options, group) {
    const kept = _options(options).filter(o => !o.startsWith("grp:"));
    if (group)
        kept.push(group);
    return kept.join(",");
}

function toKdl(state) {
    const lines = [];
    if (state["input.warp"])
        lines.push("warp-mouse-to-focus");
    return [{ block: "input", lines: lines }];
}

// Real cursor previews: the three shapes shown per theme, and the files they live in.
// File names follow the XCursor theme spec; "default" covers left_ptr aliases too.
var cursorRoles = {
    "default": ["left_ptr", "default", "arrow"],
    "text": ["text", "xterm"],
    "resize": ["right_side", "sb_h_double_arrow", "ew-resize", "col-resize", "size_hor"]
};

function cursorThemeDirs(dataDirs, homeDir, theme) {
    const dirs = dataDirs.map(d => d + "/icons/" + theme);
    dirs.push(homeDir + "/.icons/" + theme);
    dirs.push(homeDir + "/.local/share/icons/" + theme);
    return dirs;
}

function isPng(buffer) {
    const bytes = new Uint8Array(buffer);
    return bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
}

// XCursor files: 16-byte header, a table of contents, then image chunks of BGRA pixels.
function xcursorImages(buffer) {
    const bytes = new Uint8Array(buffer);
    if (bytes.length < 16)
        return [];
    const view = new DataView(bytes.buffer);
    // "Xcur" as read little-endian; big-endian writers exist but are not installed here.
    if (view.getUint32(0, true) !== 0x72756358 || view.getUint32(4, true) < 16)
        return [];
    const count = view.getUint32(12, true);
    const images = [];
    for (let i = 0; i < count; i++) {
        const entry = 16 + i * 12;
        if (entry + 12 > bytes.length || view.getUint32(entry, true) !== 0xfffd0002)
            continue;
        const position = view.getUint32(entry + 8, true);
        if (position + 36 > bytes.length)
            continue;
        const width = view.getUint32(position + 16, true);
        const height = view.getUint32(position + 20, true);
        if (width === 0 || height === 0 || position + 36 + width * height * 4 > bytes.length)
            continue;
        const pixels = new Array(width * height * 4);
        let p = position + 36;
        for (let k = 0; k < width * height; k++) {
            pixels[k * 4] = bytes[p + 2];
            pixels[k * 4 + 1] = bytes[p + 1];
            pixels[k * 4 + 2] = bytes[p];
            pixels[k * 4 + 3] = bytes[p + 3];
            p += 4;
        }
        images.push({
            "size": view.getUint32(entry + 4, true),
            "width": width,
            "height": height,
            "xhot": view.getUint32(position + 24, true),
            "yhot": view.getUint32(position + 28, true),
            "pixels": pixels
        });
    }
    return images;
}

// The image that shows best at the wanted size: the largest that fits, else the smallest.
function pickCursorImage(images, preferred) {
    let best;
    for (let i = 0; i < images.length; i++) {
        const image = images[i];
        if (best === undefined)
            best = image;
        else if (best.size <= preferred ? image.size <= preferred && image.size > best.size : image.size < best.size)
            best = image;
    }
    return best;
}

const crcTable = (() => {
    const table = new Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++)
            c = (c & 1) ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        table[n] = c >>> 0;
    }
    return table;
})();

function crc32(bytes) {
    let c = 0xffffffff;
    for (let i = 0; i < bytes.length; i++)
        c = crcTable[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}

function adler32(bytes) {
    let a = 1;
    let b = 0;
    for (let i = 0; i < bytes.length; i++) {
        a = (a + bytes[i]) % 65521;
        b = (b + a) % 65521;
    }
    return ((b << 16) | a) >>> 0;
}

function pngChunk(type, data) {
    const out = new Uint8Array(12 + data.length);
    new DataView(out.buffer).setUint32(0, data.length);
    for (let i = 0; i < 4; i++)
        out[4 + i] = type.charCodeAt(i);
    out.set(data, 8);
    new DataView(out.buffer).setUint32(8 + data.length, crc32(out.slice(4, 8 + data.length)));
    return out;
}

function b64(bytes) {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let out = "";
    for (let i = 0; i < bytes.length; i += 3) {
        const b0 = bytes[i];
        const b1 = bytes[i + 1];
        const b2 = bytes[i + 2];
        out += alphabet[b0 >> 2];
        out += alphabet[((b0 & 3) << 4) | ((b1 === undefined ? 0 : b1) >> 4)];
        out += b1 === undefined ? "=" : alphabet[((b1 & 15) << 2) | ((b2 === undefined ? 0 : b2) >> 6)];
        out += b2 === undefined ? "=" : alphabet[b2 & 63];
    }
    return out;
}

function b64decode(text) {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const clean = String(text).replace(/[^A-Za-z0-9+/=]/g, "");
    const out = new Uint8Array(Math.floor(clean.length / 4) * 3);
    let at = 0;
    for (let i = 0; i + 3 < clean.length; i += 4) {
        const six = c => clean[i + c] === "=" ? 0 : alphabet.indexOf(clean[i + c]);
        const v = (six(0) << 18) | (six(1) << 12) | (six(2) << 6) | six(3);
        out[at++] = (v >> 16) & 255;
        if (clean[i + 2] !== "=")
            out[at++] = (v >> 8) & 255;
        if (clean[i + 3] !== "=")
            out[at++] = v & 255;
    }
    return out.subarray(0, at);
}

// QML cannot read local files through XMLHttpRequest, so one probe prints the first
// readable cursor file as base64 and the page decodes it. Names come first: the
// default cursor has more aliases than the niche ones.
function shQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function cursorProbe(dirs, role) {
    const names = (cursorRoles[role] || []).map(shQuote).join(" ");
    const dirArgs = dirs.map(shQuote).join(" ");
    const script = "for n in " + names + "; do for d in " + dirArgs + "; do"
        + " f=\"$d/cursors/$n\"; [ -r \"$f\" ] && { base64 -w0 -- \"$f\"; exit 0; }; done; done; exit 1";
    return ["sh", "-c", script];
}

// A PNG data url for the QML Image, no library: stored (uncompressed) deflate blocks only.
function pngDataUrl(pixels, width, height) {
    const raw = new Uint8Array(height * (1 + width * 4));
    for (let y = 0; y < height; y++) {
        raw[y * (1 + width * 4)] = 0;
        for (let x = 0; x < width * 4; x++)
            raw[y * (1 + width * 4) + 1 + x] = pixels[y * width * 4 + x];
    }
    const blocks = [];
    for (let at = 0; at < raw.length; at += 65535) {
        const len = Math.min(65535, raw.length - at);
        const block = new Uint8Array(5 + len);
        block[0] = at + len >= raw.length ? 1 : 0;
        new DataView(block.buffer).setUint16(1, len, true);
        new DataView(block.buffer).setUint16(3, len ^ 0xffff, true);
        block.set(raw.slice(at, at + len), 5);
        blocks.push(block);
    }
    const idat = [0x78, 0x01];
    let size = 2 + 4;
    for (const block of blocks)
        size += block.length;
    const deflate = new Uint8Array(size);
    deflate[0] = 0x78;
    deflate[1] = 0x01;
    let at = 2;
    for (const block of blocks) {
        deflate.set(block, at);
        at += block.length;
    }
    new DataView(deflate.buffer).setUint32(at, adler32(raw));

    const header = new Uint8Array(13);
    const view = new DataView(header.buffer);
    view.setUint32(0, width);
    view.setUint32(4, height);
    header[8] = 8;
    header[9] = 6;
    const ihdr = pngChunk("IHDR", header);
    const idatChunk = pngChunk("IDAT", deflate);
    const iend = pngChunk("IEND", new Uint8Array(0));
    const png = new Uint8Array(8 + ihdr.length + idatChunk.length + iend.length);
    png.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);
    png.set(ihdr, 8);
    png.set(idatChunk, 8 + ihdr.length);
    png.set(iend, 8 + ihdr.length + idatChunk.length);
    return "data:image/png;base64," + b64(png);
}
