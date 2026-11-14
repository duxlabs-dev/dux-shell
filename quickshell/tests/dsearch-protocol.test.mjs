import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const protocol = loadScript(new URL("../Services/DSearchProtocol.js", import.meta.url));
const plain = value => JSON.parse(JSON.stringify(value));

test("version output of a dsearch from before semantic search still yields file search", () => {
    // Verbatim `dsearch version --json` of dsearch v2.0.0.
    const old = protocol.parseVersion('{\n  "build_time": "2026-10-20_19:24:41",\n  "commit": "9f706ca",\n  "index_schema": 5,\n  "version": "v2.0.0"\n}\n');
    assert.deepEqual(plain(old), { valid: true, version: "v2.0.0", indexVersion: 5, supportsTypeFilter: true, capabilities: [], socket: "" });
    assert.equal(protocol.parseVersion('{"index_schema": 1}').supportsTypeFilter, false);
    assert.equal(protocol.parseVersion("dsearch: command not found").valid, false);
    const current = protocol.parseVersion('{"index_schema":6,"capabilities":["semantic","collections"],"socket":"/run/user/1000/dsearch-42.sock"}');
    assert.deepEqual(plain(current.capabilities), ["semantic", "collections"]);
    assert.equal(current.socket, "/run/user/1000/dsearch-42.sock");
});

test("every line kind of the dankgo wire is told apart", () => {
    const kind = line => plain(protocol.decodeLine(line));
    assert.deepEqual(kind('{"apiVersion":1,"capabilities":["semantic"]}'), { kind: "hello", apiVersion: 1, capabilities: ["semantic"] });
    assert.deepEqual(kind('{"id":7,"result":{"hits":[]}}'), { kind: "response", id: 7, result: { hits: [] }, error: "" });
    assert.deepEqual(kind('{"id":8,"error":"query parameter required"}'), { kind: "response", id: 8, error: "query parameter required" });
    assert.deepEqual(kind('{"event":"model.progress","data":{"tower":"text"}}'), { kind: "event", topic: "model.progress", data: { tower: "text" } });
    assert.deepEqual(kind('{"error":"invalid json: x"}'), { kind: "orphanError", error: "invalid json: x" });
    assert.equal(kind("not json").kind, "invalid");
    assert.equal(kind("[1]").kind, "invalid");
});

test("a request is cut at the server's line limit by bytes, not characters", () => {
    const small = protocol.encodeRequest(3, "search", { query: "x" });
    assert.equal(small.line, '{"id":3,"method":"search","params":{"query":"x"}}\n');
    const wide = protocol.encodeRequest(4, "collections.set", { items: ["ş".repeat(600000)] });
    assert.match(wide.error, /too large/);
    assert.ok(wide.bytes > protocol.MAX_LINE_BYTES);
    assert.equal(protocol.encodeRequest(5, "x", { t: "ş".repeat(400000) }).error, undefined);
});

test("answers resolve by id in any order and silence expires by deadline", () => {
    const table = protocol.createRequestTable();
    const first = protocol.addRequest(table, "a", 1000);
    const second = protocol.addRequest(table, "b", 500);
    const forever = protocol.addRequest(table, "c", 0);
    assert.equal(protocol.takeRequest(table, second).callback, "b");
    assert.equal(protocol.takeRequest(table, second), null);
    assert.equal(protocol.nextDeadline(table), 1000);
    assert.deepEqual(Array.from(protocol.expiredRequests(table, 999)), []);
    assert.deepEqual(Array.from(protocol.expiredRequests(table, 1000)), [first]);
    assert.equal(protocol.pendingCount(table), 2);
    assert.deepEqual(Array.from(protocol.drainRequests(table), entry => entry.callback).sort(), ["a", "c"]);
    assert.equal(forever, 3);
});

test("search parameters keep the names the router reads", () => {
    const wire = plain(protocol.buildSearchParams("fatura", { limit: 20, type: "all", ext: "pdf", folder: "/home", field: "filename", fuzzy: true, sort: "score", desc: false, minSize: 1, maxSize: 9, semantic: true, collections: ["shell.actions"], collectionLimit: 8 }));
    assert.deepEqual(wire, { query: "fatura", limit: 20, type: "all", extension: "pdf", folder: "/home", field: "filename", fuzzy: true, sort_by: "score", sort_desc: false, min_size: 1, max_size: 9, semantic: true, collections: ["shell.actions"], collection_limit: 8 });
    assert.deepEqual(plain(protocol.buildSearchParams("a", { limit: 5 })), { query: "a", limit: 5 });
    assert.deepEqual(plain(protocol.buildSearchParams("a", { collections: [] })), { query: "a" });
});

test("a search answer is normalized for the launcher, with or without the new fields", () => {
    const old = protocol.normalizeSearchResult({ hits: [{ id: "/a" }], total_hits: 1 });
    assert.deepEqual(plain(old.collections), {});
    assert.deepEqual(plain(old.directory_hits), []);
    assert.equal(old.total_hits, 1);
    const fresh = protocol.normalizeSearchResult({ hits: [], directory_hits: [{ id: "/d" }], collections: [{ collection: "shell.actions", hits: [{ id: "dark", score: 0.7 }] }, { collection: "shell.apps" }, null] });
    assert.deepEqual(plain(fresh.collections), { "shell.actions": [{ id: "dark", score: 0.7 }], "shell.apps": [] });
    assert.equal(fresh.directory_hits[0].id, "/d");
    assert.deepEqual(plain(protocol.normalizeSearchResult(null).hits), []);
});

test("semantic status reads towers keyed by name or listed, and tolerates absent parts", () => {
    const keyed = protocol.normalizeStatus({ enabled: true, embedder: { available: false, reason: "libonnxruntime.so not found" }, model: { dir: "/m", towers: { text: { installed: true, bytes: 300 }, image: { installed: false } } }, collections: { "shell.actions": 40 }, indexing: { pending: 3, done: 9, paused_reason: "battery" } });
    assert.equal(keyed.enabled, true);
    assert.equal(keyed.embedderAvailable, false);
    assert.equal(keyed.embedderReason, "libonnxruntime.so not found");
    assert.deepEqual(plain(keyed.model.towers.text), { installed: true, bytes: 300, total: 0, partial: false, error: "" });
    assert.equal(keyed.model.towers.audio.installed, false);
    assert.equal(keyed.collections["shell.actions"], 40);
    assert.equal(keyed.indexing.pausedReason, "battery");
    const listed = protocol.normalizeStatus({ model: { towers: [{ tower: "audio", installed: true, size: 7 }, { name: "bogus", installed: true }], error: "disk full" } });
    assert.deepEqual(plain(listed.model.towers.audio), { installed: true, bytes: 7, total: 0, partial: false, error: "" });
    assert.equal(Object.keys(listed.model.towers).length, 3);
    assert.equal(listed.model.error, "disk full");
    assert.equal(protocol.normalizeStatus(undefined).enabled, false);
});

test("download progress becomes a fraction and a phase", () => {
    assert.deepEqual(plain(protocol.normalizeProgress({ tower: "image", bytes: 50, total: 200, state: "downloading" })), { tower: "image", bytes: 50, total: 200, fraction: 0.25, state: "downloading", phase: "active", error: "" });
    assert.equal(protocol.normalizeProgress({ tower: "text", bytes: 9, total: 9, state: "done" }).phase, "done");
    assert.equal(protocol.normalizeProgress({ tower: "text", bytes: 9, total: 9, state: "done" }).fraction, 1);
    assert.equal(protocol.normalizeProgress({ tower: "text", bytes: 1, total: 0, state: "verifying" }).fraction, 0);
    const failed = protocol.normalizeProgress({ tower: "audio", bytes: 1, total: 9, state: "failed", error: "sha256 mismatch" });
    assert.equal(failed.phase, "error");
    assert.equal(failed.error, "sha256 mismatch");
    assert.equal(protocol.normalizeProgress({ tower: "video" }), null);
    assert.equal(protocol.normalizeProgress({ tower: "text", bytes: 12, total: 4 }).fraction, 1);
});

test("dsearch's own status and progress shapes are read", () => {
    const status = protocol.normalizeStatus({ enabled: true, embedder: { available: true }, model: { dir: "/m", ready: true, towers: [{ tower: "text", installed: true, bytes: 300, total: 300, partial: false }, { tower: "image", installed: false, bytes: 40, total: 190, partial: true }] }, pending: { "shell.apps": 12 }, download: { active: true, towers: { image: { tower: "image", bytes: 40, total: 190, state: "downloading" } } } });
    assert.deepEqual(plain(status.model.towers.image), { installed: false, bytes: 40, total: 190, partial: true, error: "" });
    assert.equal(status.pending["shell.apps"], 12);
    assert.equal(status.download.active, true);
    assert.equal(status.download.towers.image.fraction, 40 / 190);
    assert.equal(protocol.normalizeStatus({ download: { error: "disk full" } }).download.error, "disk full");
    const end = protocol.normalizeProgress({ state: "finished" });
    assert.deepEqual([end.tower, end.phase], ["", "done"]);
    const failed = protocol.normalizeProgress({ state: "failed", error: "sha256 mismatch" });
    assert.deepEqual([failed.tower, failed.phase, failed.error], ["", "error", "sha256 mismatch"]);
    assert.equal(protocol.normalizeProgress({ state: "downloading" }), null, "a tower-less report is only ever an end");
    assert.equal(protocol.normalizeProgress({ tower: "text", state: "verifying", bytes: 1, total: 2 }).phase, "active");
});

test("redial delays grow and then give up", () => {
    const delays = [0, 1, 2, 3, 4, 5].map(attempt => protocol.reconnectDelay(attempt));
    assert.equal(delays[5], null);
    assert.ok(delays.slice(0, 5).every((delay, i, all) => i === 0 || delay > all[i - 1]));
});

test("socket directory follows the dankgo rule", () => {
    assert.equal(protocol.socketDirectory({ runtimeDir: "/run/user/1000" }), "/run/user/1000");
    assert.equal(protocol.socketDirectory({ runtimeDir: "/run/user/1000", flatpakId: "org.x.App" }), "/run/user/1000/app/org.x.App");
    assert.equal(protocol.socketDirectory({ tmpDir: "/var/tmp" }), "/var/tmp");
    assert.equal(protocol.socketDirectory({}), "/tmp");
});

test("socket discovery lists live dsearch sockets in dankgo order and ignores the rest", async t => {
    const dir = mkdtempSync(join(tmpdir(), "dsearch-socks-"));
    const servers = [];
    t.after(() => {
        servers.forEach(server => server.close());
        rmSync(dir, { recursive: true, force: true });
    });
    const listen = path => new Promise(resolve => servers.push(net.createServer().listen(path, resolve)));
    const live = process.pid;
    await listen(join(dir, `danksearch-${live}.sock`));
    await listen(join(dir, `dsearch-${live}.sock`));
    await listen(join(dir, "dsearch-4194999.sock"));
    await listen(join(dir, "dsearch-notapid.sock"));
    writeFileSync(join(dir, `dsearch-${live + 1}.sock`), "a regular file");
    const [command, ...args] = Array.from(protocol.socketListCommand(dir));
    const out = execFileSync(command, args, { encoding: "utf8" });
    assert.deepEqual(Array.from(protocol.parseSocketList(out)), [join(dir, `dsearch-${live}.sock`), join(dir, `danksearch-${live}.sock`)]);
    assert.deepEqual(Array.from(protocol.parseSocketList("")), []);
});
