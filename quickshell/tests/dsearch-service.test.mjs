import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Services/DSearchService.qml", import.meta.url), "utf8");
const protocol = loadScript(new URL("../Services/DSearchProtocol.js", import.meta.url));
const collections = loadScript(new URL("../Services/DSearchCollections.js", import.meta.url));

function service(state, methods) {
    const sent = [];
    const context = vm.createContext(Object.assign({
        Protocol: protocol,
        Collections: collections,
        log: { warn() {} },
        dsearchAvailable: true,
        semanticReady: false,
        semanticEnabled: true,
        collectionsSupported: true,
        collectionActions: "shell.actions",
        collectionSettings: "shell.settings",
        collectionApps: "shell.apps",
        _instance: "/run/dsearch-1.sock",
        _dirty: false,
        _registered: {},
        _inflight: {},
        ensureChecked() {},
        searchResultsReceived() {},
        errorOccurred() {},
        _send(method, params, callback) { sent.push({ method, params, callback }); }
    }, state));
    context.root = context;
    const found = [];
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\) \{\n[\s\S]*?^    \}/gm)) {
        if (!methods.includes(match[1]))
            continue;
        found.push(match[1]);
        vm.runInContext(match[0], context);
    }
    assert.deepEqual(found.sort(), [...methods].sort());
    return { context, sent };
}

test("semantic parameters reach dsearch only while semantic search is ready", () => {
    const params = { limit: 20, semantic: true, collections: ["shell.apps"], collectionLimit: 8 };
    const off = service({ semanticReady: false }, ["search"]);
    off.context.search("fatura", params, () => {});
    assert.deepEqual(JSON.parse(JSON.stringify(off.sent[0].params)), { query: "fatura", limit: 20 });
    const on = service({ semanticReady: true }, ["search"]);
    on.context.search("fatura", params, () => {});
    assert.equal(on.sent[0].params.semantic, true);
    assert.deepEqual(Array.from(on.sent[0].params.collections), ["shell.apps"]);
    assert.equal(on.sent[0].params.collection_limit, 8);
    assert.equal(params.semantic, true, "the caller's object is left alone");
    const bare = service({ semanticReady: true }, ["search"]);
    bare.context.search("fatura", { collections: ["shell.apps"], collectionLimit: 8 }, () => {});
    assert.deepEqual(JSON.parse(JSON.stringify(bare.sent[0].params)), { query: "fatura" }, "dsearch refuses collections without semantic");
});

test("without a running service the search goes through the CLI with the caller's own parameters", () => {
    const commands = [];
    const answers = [];
    const { context, sent } = service({
        semanticReady: true,
        _searchViaCli: (query, params, callback) => commands.push({ query, params, callback }),
    }, ["search"]);
    const params = { limit: 20, type: "file", semantic: true, collections: ["shell.apps"] };
    context.search("rapor", params, answer => answers.push(answer));
    sent[0].callback({ error: "dsearch is not running", code: "unavailable" });
    assert.equal(commands.length, 1);
    assert.equal(commands[0].query, "rapor");
    assert.equal(commands[0].params, params);
    assert.equal(answers.length, 0, "the CLI answers, not the failed socket");
});

test("the CLI command line carries every file filter and parses its answer like the socket's", () => {
    const runs = [];
    const answers = [];
    const { context } = service({
        Proc: { runCommand: (id, command, callback, debounce, timeout) => runs.push({ id, command, callback, debounce, timeout }) }
    }, ["_searchViaCli", "_finishSearch"]);
    context._searchViaCli("a b", { limit: 5, type: "dir", ext: "pdf", folder: "/h", field: "filename", fuzzy: true, sort: "score", desc: false, minSize: 1, maxSize: 2 }, answer => answers.push(answer));
    assert.deepEqual(Array.from(runs[0].command), ["dsearch", "search", "a b", "--json", "-n", "5", "-t", "dir", "-e", "pdf", "--folder", "/h", "-f", "filename", "--fuzzy", "--sort", "score", "--desc=false", "--min-size", "1", "--max-size", "2"]);
    assert.equal(runs[0].id, "dsearch-search-dir");
    runs[0].callback('{"hits":[{"id":"/x"}]}', 0);
    runs[0].callback("", 124);
    runs[0].callback("", 1);
    runs[0].callback("garbage", 0);
    assert.equal(answers[0].result.hits[0].id, "/x");
    assert.deepEqual(answers.slice(1).map(answer => answer.error), ["search timed out", "search failed", "failed to parse search response"]);
});

test("a search answer reaches the callback normalized, a failure keeps the old error texts", () => {
    const answers = [];
    const { context, sent } = service({}, ["search", "_finishSearch"]);
    context.search("a", {}, answer => answers.push(answer));
    sent[0].callback({ result: { hits: [{ id: "/a" }] } });
    context.search("b", {}, answer => answers.push(answer));
    sent[1].callback({ error: "request timed out", code: "timeout" });
    context.search("c", {}, answer => answers.push(answer));
    sent[2].callback({ error: "boom", code: "server" });
    assert.equal(answers[0].result.hits[0].id, "/a");
    assert.deepEqual(Array.from(answers[0].result.directory_hits), []);
    assert.equal(answers[1].error, "search timed out");
    assert.equal(answers[2].error, "search failed");
    const empty = [];
    context.search("", {}, answer => empty.push(answer));
    assert.equal(empty[0].error, "query is required");
    const missing = [];
    service({ dsearchAvailable: false }, ["search"]).context.search("a", {}, answer => missing.push(answer));
    assert.equal(missing[0].error, "dsearch not available");
});

function registration(overrides) {
    const items = { "shell.actions": [{ id: "dark", title: "Dark", text: "t", keywords: [] }], "shell.apps": [{ id: "a.desktop", title: "A", text: "", keywords: [] }] };
    const { context, sent } = service(Object.assign({
        _collectionSources: () => Object.keys(items).map(name => ({ name, items: items[name] })),
        setCollection(name, list, callback) { sent.push({ name, list, callback }); }
    }, overrides), ["_registerNow", "_adoptInstance"]);
    return { context, sent, items };
}

test("an unchanged catalog is not sent again, a changed collection is sent alone", () => {
    const { context, sent, items } = registration();
    context._registerNow();
    assert.deepEqual(sent.map(call => call.name).sort(), ["shell.actions", "shell.apps"]);
    sent.splice(0).forEach(call => call.callback({ result: {} }));
    context._registerNow();
    assert.equal(sent.length, 0);
    items["shell.actions"] = [...items["shell.actions"], { id: "wifi", title: "Wi-Fi", text: "t", keywords: [] }];
    context._registerNow();
    assert.deepEqual(sent.map(call => call.name), ["shell.actions"]);
});

test("a new dsearch instance forgets what it was told, a failed send is retried", () => {
    const { context, sent } = registration();
    context._registerNow();
    sent.splice(0).forEach(call => call.callback({ result: {} }));
    context._adoptInstance("/run/dsearch-1.sock");
    context._registerNow();
    assert.equal(sent.length, 0, "the same dsearch keeps what it was told");
    context._adoptInstance("/run/dsearch-2.sock");
    context._registerNow();
    assert.equal(sent.length, 2, "a dsearch that started since is told everything");
    sent.splice(0).forEach(call => call.callback({ error: "model unavailable" }));
    assert.equal(context._dirty, true);
    context._registerNow();
    assert.equal(sent.length, 2, "nothing was acknowledged, so both are offered again");
});

test("a send that is still in flight is not duplicated", () => {
    const { context, sent } = registration();
    context._registerNow();
    context._registerNow();
    assert.equal(sent.length, 2);
});

test("nothing is registered while semantic search is off", () => {
    const { context, sent } = registration({ semanticEnabled: false });
    context._registerNow();
    assert.equal(sent.length, 0);
});

test("an acknowledgement from a previous dsearch instance is not trusted", () => {
    const { context, sent } = registration();
    context._registerNow();
    const stale = sent.splice(0);
    context._instance = "/run/dsearch-2.sock";
    stale.forEach(call => call.callback({ result: {} }));
    assert.deepEqual(JSON.parse(JSON.stringify(context._registered)), {});
});
