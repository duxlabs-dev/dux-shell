import assert from "node:assert/strict";
import test from "node:test";
import { inflateSync } from "node:zlib";
import { loadScript } from "./qml-script.mjs";

const input = loadScript(new URL("../Common/niri/sections/input.js", import.meta.url));
const { assemble } = loadScript(new URL("../Common/niri/assemble.js", import.meta.url));

const section = { id: "input", toKdl: input.toKdl };

test("writes nothing while every page key is at its default", () => {
    assert.equal(assemble([section], Object.assign({}, input.defaults)), "");
});

test("warp-mouse-to-focus goes in the input block once turned on", () => {
    assert.equal(assemble([section], { "input.warp": true }), "input {\n    warp-mouse-to-focus\n}\n");
});

test("every key DMS already writes binds to a SettingsData property, never to the page", () => {
    for (const key in input.stored) {
        assert.ok(key.startsWith("input."), key);
        if (input.stored[key] === "page")
            assert.ok(key in input.defaults, key);
        else
            assert.match(input.stored[key], /^SettingsData:\w+$/, key);
    }
    assert.equal(input.stored["input.layouts"], "SettingsData:keyboardLayouts");
});

test("every search entry names a known key and carries search words", () => {
    for (const entry of input.search) {
        assert.ok(entry.key in input.stored, entry.key);
        assert.ok(entry.words.length > 1, entry.key);
    }
});

test("the switch shortcut swaps only the grp: option and keeps the others", () => {
    assert.equal(input.switchOf("compose:ralt,grp:caps_toggle"), "grp:caps_toggle");
    assert.equal(input.switchOf("grp:unknown"), "");
    assert.equal(input.withSwitch("compose:ralt,grp:caps_toggle", "grp:alt_shift_toggle"), "compose:ralt,grp:alt_shift_toggle");
    assert.equal(input.withSwitch("grp:caps_toggle", ""), "");
    assert.equal(input.withSwitch("", "grp:win_space_toggle"), "grp:win_space_toggle");
});

test("top row follows the first layout through the Keybinds board tables", () => {
    assert.equal(input.topRow(""), "QWERTY");
    assert.equal(input.topRow(" fr ,de"), "AZERTY");
    assert.equal(input.topRow("de,us"), "QWERTZ");
    assert.equal(input.topRow("xx"), "QWERTY");
});

// A synthetic XCursor file: one TOC entry per image, BGRA pixels.
function buildXcursor(images) {
    const headerSize = 16;
    let size = headerSize + images.length * 12;
    const chunks = [];
    for (let i = 0; i < images.length; i++) {
        const image = images[i];
        size += 56 + image.width * image.height * 4;
        const bytes = new Uint8Array(16 + 20 + image.width * image.height * 4);
        const view = new DataView(bytes.buffer);
        view.setUint32(0, 36, true);
        view.setUint32(4, 0xfffd0002, true);
        view.setUint32(8, image.size, true);
        view.setUint32(12, 1, true);
        view.setUint32(16, image.width, true);
        view.setUint32(20, image.height, true);
        view.setUint32(24, image.xhot || 0, true);
        view.setUint32(28, image.yhot || 0, true);
        view.setUint32(32, 0, true);
        let p = 36;
        for (let k = 0; k < image.width * image.height; k++) {
            bytes[p] = image.pixels[k * 4 + 2];
            bytes[p + 1] = image.pixels[k * 4 + 1];
            bytes[p + 2] = image.pixels[k * 4];
            bytes[p + 3] = image.pixels[k * 4 + 3];
            p += 4;
        }
        chunks.push(bytes);
    }
    const out = new Uint8Array(size);
    const view = new DataView(out.buffer);
    out.set([0x58, 0x63, 0x75, 0x72], 0);
    view.setUint32(4, 16, true);
    view.setUint32(8, 1, true);
    view.setUint32(12, images.length, true);
    let position = headerSize + images.length * 12;
    for (let i = 0; i < images.length; i++) {
        const at = headerSize + i * 12;
        view.setUint32(at, 0xfffd0002, true);
        view.setUint32(at + 4, images[i].size, true);
        view.setUint32(at + 8, position, true);
        out.set(chunks[i], position);
        position += chunks[i].length;
    }
    return out.buffer;
}

test("an xcursor file reads back its images with straight RGBA pixels", () => {
    const red = { "size": 24, "width": 2, "height": 2, "xhot": 1, "yhot": 1, "pixels": [255, 0, 0, 255, 255, 0, 0, 128, 10, 20, 30, 255, 0, 0, 0, 0] };
    const big = { "size": 48, "width": 3, "height": 1, "xhot": 0, "yhot": 0, "pixels": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] };
    const images = input.xcursorImages(buildXcursor([red, big]));
    assert.equal(images.length, 2);
    assert.equal(images[0].size, 24);
    assert.equal(images[0].width, 2);
    assert.equal(images[0].xhot, 1);
    assert.deepEqual(Array.from(images[0].pixels.slice(0, 8)), [255, 0, 0, 255, 255, 0, 0, 128]);
    assert.equal(images[1].size, 48);
    assert.deepEqual(Array.from(images[1].pixels), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
});

test("xcursorImages rejects what is not an xcursor file", () => {
    assert.equal(input.xcursorImages(new ArrayBuffer(0)).length, 0);
    assert.equal(input.xcursorImages(buildXcursor([])).length, 0);
    const notXcursor = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
    assert.equal(input.xcursorImages(notXcursor.buffer).length, 0);
});

test("the preview picks the largest image that fits the size, else the smallest", () => {
    const images = input.xcursorImages(buildXcursor([
        { "size": 24, "width": 2, "height": 2, "pixels": [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4] },
        { "size": 48, "width": 2, "height": 2, "pixels": [9, 9, 9, 9, 8, 8, 8, 8, 7, 7, 7, 7, 6, 6, 6, 6] }
    ]));
    assert.equal(input.pickCursorImage(images, 32).size, 24);
    assert.equal(input.pickCursorImage(images, 64).size, 48);
    assert.equal(input.pickCursorImage(images, 48).size, 48);
    assert.equal(input.pickCursorImage([], 32), undefined);
});

test("a cursor image encodes to an inflated png data url", () => {
    const pixels = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0];
    const url = input.pngDataUrl(pixels, 2, 2);
    assert.ok(url.startsWith("data:image/png;base64,"), url);
    const bytes = new Uint8Array(Buffer.from(url.split(",")[1], "base64"));
    assert.deepEqual([...bytes.slice(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const view = new DataView(bytes.buffer);
    assert.equal(view.getUint32(16), 2);
    assert.equal(view.getUint32(20), 2);
    let at = 8;
    let idat = [];
    while (at < bytes.length) {
        const length = view.getUint32(at);
        const type = String.fromCharCode(...bytes.slice(at + 4, at + 8));
        if (type === "IDAT")
            idat.push(...bytes.slice(at + 8, at + 8 + length));
        at += 12 + length;
    }
    const raw = inflateSync(Uint8Array.from(idat));
    assert.deepEqual(Array.from(raw), [0, 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 0, 255, 255, 0, 0, 0, 0]);
});

test("a png cursor file passes through untouched while an xcursor file does not", () => {
    const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2]).buffer;
    assert.equal(input.isPng(png), true);
    assert.equal(input.isPng(buildXcursor([{ "size": 24, "width": 1, "height": 1, "pixels": [1, 2, 3, 4] }])), false);
});

test("each preview role names cursor files, and theme dirs go from xdg to home", () => {
    assert.deepEqual(input.cursorRoles.default[0], "left_ptr");
    assert.ok(input.cursorRoles.text.includes("xterm"));
    assert.ok(input.cursorRoles.resize.length > 0);
    const dirs = input.cursorThemeDirs(["/usr/share", "/usr/local/share"], "/xdg/me", "Bibata");
    assert.deepEqual(dirs, ["/usr/share/icons/Bibata", "/usr/local/share/icons/Bibata", "/xdg/me/.icons/Bibata", "/xdg/me/.local/share/icons/Bibata"]);
});

test("base64 round trips between encode and decode", () => {
    const bytes = new Uint8Array([0, 1, 2, 250, 251, 252, 253, 254, 255, 77, 200]);
    assert.deepEqual(Array.from(input.b64decode(input.b64(bytes))), Array.from(bytes));
    assert.equal(input.b64decode("").byteLength, 0);
    assert.deepEqual(Array.from(input.b64decode(input.b64(new Uint8Array([65])))), [65]);
    assert.deepEqual(Array.from(input.b64decode("Zm9v\r\nYmFy")), [102, 111, 111, 98, 97, 114]);
});

test("the probe quotes theme dirs and names against the shell", () => {
    const command = input.cursorProbe(["/usr/share/icons/Bi'bata", "/usr/local/share/icons"], "default");
    assert.equal(command[0], "sh");
    assert.equal(command[1], "-c");
    const script = command[2];
    assert.ok(script.includes("'/usr/share/icons/Bi'\\''bata'"), script);
    assert.ok(script.includes("left_ptr"), script);
    assert.ok(script.includes("base64"), script);
    assert.ok(!script.includes("Bi'bata/cursors"), script);
});
