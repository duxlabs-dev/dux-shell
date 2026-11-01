.pragma library

// Node names that make niri run a program.
const spawnName = /^spawn(-sh)?(-at-startup)?$/;
// Every KDL newline ends a node, not only \n: missing one would let a spawn hide as an argument.
const newline = /[\n\r\u000B\u000C\u0085\u2028\u2029]/;
const raw = /r?(#*)"/y;
const bare = /[^\s\u0085(){}[\]\/\\";=]+/y;

// KDL escapes (\u{..}, \x) in a quoted node name, so "sp\u{61}wn" is read as niri reads it.
function unescape(text) {
    return text.replace(/\\u\{([0-9a-fA-F]{1,6})\}/g, (_, hex) => String.fromCodePoint(Math.min(parseInt(hex, 16), 0x10FFFF))).replace(/\\\s+/g, "").replace(/\\(.)/g, "$1");
}

// 1-based lines of the spawn nodes niri would run. Comments, strings and slashdashed nodes are
// skipped; an unclosed string or comment ends the scan, niri refuses such a text anyway.
function spawnLines(text) {
    const st = {
        s: String(text ?? ""),
        found: [],
        i: 0,
        line: 1,
        depth: 0,
        nodeStart: true,
        skipNode: false,   // this node is slashdashed
        skipBlock: false,  // the next children block is slashdashed
        hiddenFrom: -1,    // depth of the slashdashed block we are in
        joined: false      // a backslash joins the next line to this node
    };
    while (st.i < st.s.length && step(st)) {}
    return st.found;
}

// Reads one token; false when an unclosed string or comment ends the scan.
function step(st) {
    const s = st.s;
    const c = s[st.i];
    if (newline.test(c) || c === ";")
        return endNode(st, c);
    if (c === "\\")
        st.joined = true;
    if (/\s/.test(c) || c === "\\") {
        st.i++;
        return true;
    }
    if (s.startsWith("//", st.i))
        return lineComment(st);
    if (s.startsWith("/*", st.i))
        return blockComment(st);
    if (s.startsWith("/-", st.i))
        return slashdash(st);
    if (c === "{")
        return openBlock(st);
    if (c === "}")
        return closeBlock(st);
    if (c === "(")
        return typeAnnotation(st);
    if (c === '"')
        return quoted(st);
    return word(st);
}

function jump(st, to) {
    for (; st.i < to; st.i++)
        if (st.s[st.i] === "\n")
            st.line++;
}

function name(st, value) {
    if (st.nodeStart && !st.skipNode && st.hiddenFrom < 0 && spawnName.test(value) && st.found[st.found.length - 1] !== st.line)
        st.found.push(st.line);
    st.nodeStart = false;
    st.skipBlock = false;
}

function endNode(st, c) {
    if (c === ";" || !st.joined) {
        if (st.hiddenFrom < 0)
            st.skipNode = false;
        st.nodeStart = true;
        st.skipBlock = false;
    }
    if (c !== "\r")
        st.joined = false;
    jump(st, st.i + 1);
    return true;
}

function lineComment(st) {
    let end = st.i;
    while (end < st.s.length && !newline.test(st.s[end]))
        end++;
    jump(st, end);
    return true;
}

function blockComment(st) {
    const s = st.s;
    let open = 0;
    let end = st.i;
    do {
        if (end >= s.length)
            return false;
        if (s.startsWith("/*", end) || s.startsWith("*/", end)) {
            open += s[end] === "/" ? 1 : -1;
            end += 2;
        } else {
            end++;
        }
    } while (open > 0);
    jump(st, end);
    return true;
}

function slashdash(st) {
    if (st.nodeStart)
        st.skipNode = true;
    else
        st.skipBlock = true;
    st.i += 2;
    return true;
}

function openBlock(st) {
    st.depth++;
    if (st.hiddenFrom < 0 && (st.skipNode || st.skipBlock))
        st.hiddenFrom = st.depth;
    st.nodeStart = true;
    st.skipBlock = false;
    st.i++;
    return true;
}

function closeBlock(st) {
    if (st.depth === st.hiddenFrom) {
        st.hiddenFrom = -1;
        st.skipNode = false;
    }
    st.depth--;
    st.nodeStart = true;
    st.i++;
    return true;
}

// Index just past the string starting at `at` (quoted, """ or raw), `at` if none starts there, -1 if unclosed.
function stringEnd(s, at) {
    if (s[at] === '"') {
        const fence = s.startsWith('"""', at) ? '"""' : '"';
        let end = at + fence.length;
        while (end < s.length && !s.startsWith(fence, end))
            end += s[end] === "\\" ? 2 : 1;
        return end >= s.length ? -1 : end + fence.length;
    }
    raw.lastIndex = at;
    const r = raw.exec(s);
    if (!r || (r[0][0] !== "r" && r[1] === ""))
        return at;
    const end = s.indexOf('"' + r[1], at + r[0].length);
    return end < 0 ? -1 : end + 1 + r[1].length;
}

// The type is a string like any other: a ")" inside its quotes does not close it, as niri reads it.
function typeAnnotation(st) {
    const s = st.s;
    let end = st.i + 1;
    while (end < s.length && s[end] !== ")") {
        const after = stringEnd(s, end);
        if (after < 0)
            return false;
        end = after > end ? after : end + 1;
    }
    if (end >= s.length)
        return false;
    jump(st, end + 1);
    return true;
}

function quoted(st) {
    const s = st.s;
    const fence = s.startsWith('"""', st.i) ? '"""' : '"';
    const end = stringEnd(s, st.i);
    if (end < 0)
        return false;
    name(st, unescape(s.slice(st.i + fence.length, end - fence.length)));
    jump(st, end);
    return true;
}

// Raw string (r"..", #".."#) or bare word.
function word(st) {
    const s = st.s;
    raw.lastIndex = st.i;
    const r = raw.exec(s);
    if (r && (r[0][0] === "r" || r[1] !== "")) {
        const end = stringEnd(s, st.i);
        if (end < 0)
            return false;
        name(st, s.slice(st.i + r[0].length, end - 1 - r[1].length));
        jump(st, end);
        return true;
    }
    bare.lastIndex = st.i;
    const b = bare.exec(s);
    name(st, b ? b[0] : s[st.i]);
    jump(st, b ? st.i + b[0].length : st.i + 1);
    return true;
}
