import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const mux = loadScript(new URL("../Common/MuxBackends.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

test("tmux parser reads the pipe format and drops short lines", () => {
    const sessions = mux.BACKENDS.tmux.parse("main|3|1\nwork|1|0\n\nbroken\n");
    assert.deepEqual(plain(sessions), [
        { name: "main", windows: "3", attached: true },
        { name: "work", windows: "1", attached: false }
    ]);
});

test("zellij parser strips the bracket suffix and marks exited sessions", () => {
    const sessions = mux.BACKENDS.zellij.parse("main [Created 2h ago]\nold [Created 1d ago] (EXITED - attach to resurrect)\n");
    assert.deepEqual(plain(sessions), [
        { name: "main", windows: "N/A", attached: true },
        { name: "old", windows: "N/A", attached: false }
    ]);
});

test("herdr parser reads the sessions envelope and treats missing running as stopped", () => {
    const output = JSON.stringify({ sessions: [{ name: "default", running: true, default: true }, { name: "stopped", running: false }, { name: "unknown" }] });
    assert.deepEqual(plain(mux.BACKENDS.herdr.parse(output)), [
        { name: "default", windows: "N/A", attached: true },
        { name: "stopped", windows: "N/A", attached: false },
        { name: "unknown", windows: "N/A", attached: false }
    ]);
    assert.deepEqual(plain(mux.BACKENDS.herdr.parse("{}")), []);
    assert.throws(() => mux.BACKENDS.herdr.parse("not json"));
});

test("session filter matches names case-insensitively and by /regex/, ignoring bad patterns", () => {
    const filter = " Scratch, /^tmp_/, /[bad/ ";
    assert.equal(mux.isSessionExcluded("scratch", filter), true);
    assert.equal(mux.isSessionExcluded("tmp_build", filter), true);
    assert.equal(mux.isSessionExcluded("main", filter), false);
    assert.equal(mux.isSessionExcluded("main", ""), false);
});
