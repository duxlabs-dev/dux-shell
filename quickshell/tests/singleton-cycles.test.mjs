import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = fileURLToPath(new URL("../", import.meta.url));

const KNOWN_CYCLES = [
    ["Paths", "SettingsData"],
    ["SessionData", "SessionService"],
    ["CompositorService", "HyprlandService"],
    ["CompositorService", "MangoService"],
    ["CompositorService", "NiriService"],
    ["CompositorService", "NiriService", "Theme"]
].map(members => members.join(","));

function stripLiterals(source) {
    let out = "";
    let state = null;
    for (let i = 0; i < source.length; i++) {
        const c = source[i];
        if (state === null) {
            if (source.startsWith("//", i)) { state = "line"; i++; continue; }
            if (source.startsWith("/*", i)) { state = "block"; i++; continue; }
            if (c === '"' || c === "'" || c === "`") { state = c; out += " "; continue; }
            out += c;
        } else if (state === "line") {
            if (c === "\n") { state = null; out += c; }
        } else if (state === "block") {
            if (source.startsWith("*/", i)) { state = null; i++; }
        } else {
            if (c === "\\") { i++; continue; }
            if (c === state) { state = null; out += " "; }
        }
    }
    return out;
}

function stripDeferredBodies(source) {
    const pattern = /\bfunction\s+\w+\s*\([^)]*\)\s*\{|\bon[A-Z]\w*\s*:\s*(?:\w+\s*=>\s*|function\s*\([^)]*\)\s*)?\{/;
    for (;;) {
        const match = pattern.exec(source);
        if (!match) return source;
        let depth = 0;
        let i = match.index + match[0].length - 1;
        for (; i < source.length; i++) {
            if (source[i] === "{") depth++;
            else if (source[i] === "}" && --depth === 0) break;
        }
        source = source.slice(0, match.index) + " ".repeat(i + 1 - match.index) + source.slice(i + 1);
    }
}

function singletonSources() {
    const sources = new Map();
    for (const dir of ["Common", "Services"]) {
        for (const name of readdirSync(root + dir)) {
            if (!name.endsWith(".qml")) continue;
            const text = readFileSync(root + dir + "/" + name, "utf8");
            if (text.trimStart().startsWith("pragma Singleton"))
                sources.set(name.slice(0, -4), text);
        }
    }
    return sources;
}

function creationGraph(sources) {
    const graph = new Map();
    for (const [name, text] of sources) {
        const scanned = stripDeferredBodies(stripLiterals(text));
        const refs = new Set();
        for (const [identifier] of scanned.matchAll(/\b[A-Z]\w+\b/g))
            if (sources.has(identifier) && identifier !== name) refs.add(identifier);
        graph.set(name, refs);
    }
    return graph;
}

function findCycles(graph) {
    const found = new Set();
    const walk = (node, stack, seen) => {
        for (const next of graph.get(node) ?? []) {
            const at = stack.indexOf(next);
            if (at !== -1) {
                found.add([...new Set(stack.slice(at))].sort().join(","));
            } else if (!seen.has(next)) {
                seen.add(next);
                walk(next, [...stack, next], seen);
            }
        }
    };
    for (const node of graph.keys()) walk(node, [node], new Set([node]));
    return found;
}

test("no new creation-time cycles between Common and Services singletons", () => {
    const sources = singletonSources();

    const cycles = findCycles(creationGraph(sources));
    const added = [...cycles].filter(cycle => !KNOWN_CYCLES.includes(cycle));

    assert.deepEqual(added, [], "new singleton cycle(s) reachable during construction: " + added.join(" | "));
});
