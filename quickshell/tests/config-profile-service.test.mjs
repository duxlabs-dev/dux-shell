import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import vm from "node:vm";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Services/ConfigProfileService.qml", import.meta.url), "utf8");
const functions = source.match(/^    function \w+\([^\n]*\) \{\n[\s\S]*?^    \}/gm);
const activeExpr = source.match(/readonly property string activeProfileId: (.*)$/m)?.[1];
const imageExtensions = JSON.parse(source.match(/readonly property var imageExtensions: (\[.*\])$/m)?.[1] ?? "null");
if (!activeExpr || !imageExtensions)
    throw new Error("activeProfileId or imageExtensions not found in ConfigProfileService.qml");
const Profiles = loadScript(new URL("../Common/settings/ConfigProfiles.js", import.meta.url));
const SpecUtil = loadScript(new URL("../DCommon/Common/settings/SpecUtil.js", import.meta.url));

const version = (file, property) => Number(readFileSync(new URL(file, import.meta.url), "utf8").match(new RegExp(`property int ${property}:\\s*(\\d+)`))[1]);
const SV = version("../Common/SettingsData.qml", "settingsConfigVersion");
const SSV = version("../Common/SessionData.qml", "sessionConfigVersion");
const clone = v => JSON.parse(JSON.stringify(v));

function profile(id, fields = {}) {
    return Object.assign({ id, name: id, groups: ["frame", "dock"], sync: false, configVersion: SV, sessionConfigVersion: SSV, settings: { frameEnabled: false }, session: { dockPins: {} } }, fields);
}

function fileText(p) {
    const out = Object.assign({ version: 1 }, p);
    delete out.id;
    return JSON.stringify(out);
}

// The real service functions over a live state and a `disk` of folder name -> profile.json text (undefined: none).
// `events` logs writes and applies in order; `procs` holds every command except mkdir, which succeeds at once.
function service({ profiles = [], files = {}, active = "a", applyOk = true, dir = "/cfg/profiles", realProc = false }) {
    const events = [], procs = [], toasts = [], imported = [];
    const disk = Object.assign(Object.fromEntries(profiles.map(p => [p.id, fileText(p)])), files);
    const live = { settings: { frameEnabled: true }, session: { dockPins: { main: "app.desktop" } } };
    const ctx = vm.createContext({
        Profiles, SpecUtil, imageExtensions,
        Qt: { callLater: fn => fn() },
        log: { warn() {} },
        I18n: { tr: s => s },
        profileImported: id => imported.push(id),
        profilesDir: dir, profiles: [], _entries: {}, _views: {}, _folderIds: [], _creating: {}, _deleting: {},
        _folderReady: false, _scanned: false, _applying: false, ready: true, draft: null, _pendingImport: "", capturingId: "", screenshotTargetId: "",
        SettingsData: {
            settingsConfigVersion: SV,
            pluginSettings: {},
            profileSettingsSnapshot: () => clone(live.settings),
            applyProfileSettings(values) {
                events.push("applySettings");
                return applyOk && !!Object.assign(live.settings, clone(values));
            },
            savePluginSettings() {}
        },
        PluginService: { enablePlugin() {}, disablePlugin() {}, pluginDataChanged() {} },
        SessionData: {
            sessionConfigVersion: SSV,
            activeConfigProfile: active,
            profileValues: keys => clone(Object.fromEntries(keys.filter(k => k in live.session).map(k => [k, live.session[k]]))),
            applyProfileValues(values) {
                events.push("applySession");
                Object.assign(live.session, clone(values));
            },
            set(key, value) {
                this[key] = value;
            }
        },
        ToastService: { showInfo() {}, showWarning() {}, showError: (title, detail) => toasts.push(detail) },
        Proc: {
            dmsBin: "/stub/dms",
            noTimeout: -1,
            runCommand(id, cmd, cb) {
                if (realProc) {
                    const r = spawnSync(cmd[0], cmd.slice(1), { encoding: "utf8" });
                    cb(r.stdout, r.status);
                } else if (cmd[0] === "mkdir") {
                    cb("", 0);
                } else {
                    procs.push({ cmd, cb });
                }
            }
        },
        profileView: {
            createObject(parent, { profileId: id }) {
                return {
                    setText(text) {
                        events.push("write:" + id);
                        disk[id] = text;
                        ctx._loaded(id, text);
                    },
                    destroy() {},
                    set path(_) {
                        if (disk[id] === undefined)
                            ctx._loadFailed(id, true);
                        else
                            ctx._loaded(id, disk[id]);
                    }
                };
            }
        },
        syncTimer: { restart() {}, stop() {} }
    });
    vm.runInContext("var root = this; String.prototype.arg = function (v) { return this.replace('%1', v); };", ctx);
    for (const fn of functions)
        vm.runInContext(fn, ctx);
    ctx._scanFolder = () => {};
    Object.defineProperty(ctx, "activeProfileId", { get: () => vm.runInContext(activeExpr, ctx) });
    Object.defineProperty(ctx, "activeProfile", { get: () => ctx.find(ctx.activeProfileId) });
    ctx._setFolders(Object.keys(disk));
    const setup = events.splice(0);
    return { ctx, events, procs, toasts, disk, live, setup, imported };
}

const removed = procs => clone(procs.filter(p => p.cmd[0] === "rm").map(p => p.cmd));

test("switching writes the outgoing synced profile and moves the pointer", () => {
    const { ctx, disk } = service({ profiles: [profile("a", { sync: true }), profile("b")] });
    assert.equal(ctx.activate("b"), true);
    assert.equal(JSON.parse(disk.a).settings.frameEnabled, true);
    assert.equal(ctx.SessionData.activeConfigProfile, "b");
});

test("a failed settings apply keeps the active profile and applies no session values", () => {
    const { ctx, events, live } = service({ profiles: [profile("a"), profile("b")], applyOk: false });
    assert.equal(ctx.activate("b"), false);
    assert.equal(ctx.SessionData.activeConfigProfile, "a");
    assert.ok(!events.includes("applySession"));
    assert.deepEqual(live.session.dockPins, { main: "app.desktop" });
});

test("an old profile is migrated and written back once; a newer or current one is never written", () => {
    const old = service({ profiles: [profile("a", { configVersion: SV - 1 })] });
    assert.deepEqual(old.setup, ["write:a"]);
    assert.equal(JSON.parse(old.disk.a).configVersion, SV);
    old.ctx._loaded("a", old.disk.a);
    assert.deepEqual(old.events, []);

    const newer = service({ profiles: [profile("a", { settings: { frameEnabled: false, keyFromNewerShell: 1 } }), profile("b", { configVersion: SV + 1, sync: true })] });
    assert.equal(newer.ctx.activate("b"), true);
    newer.ctx._sync();
    assert.equal(newer.ctx.updateFromCurrent("b"), false);
    assert.equal(newer.ctx.updateProfile("b", "B", ["colors"], true), false);
    assert.deepEqual(newer.setup.concat(newer.events).filter(e => e.startsWith("write")), []);
});

test("unreadable profile folders are never written or deleted, and block the Default profile", () => {
    for (const text of ["{ not json", "[]", fileText(profile("x", { version: 2 })), fileText(profile("x", { name: " " }))]) {
        const { ctx, events, procs, setup } = service({ files: { bad: text }, active: "" });
        ctx.ensureDefault();
        assert.equal(ctx.updateFromCurrent("bad"), false);
        assert.equal(ctx.setImageFromFile("bad", "/x/y.jpg"), false);
        assert.equal(ctx.deleteProfile("bad"), false);
        ctx._finishCapture("bad", true, "");
        ctx.startDraft();
        procs.find(p => p.cmd[0] === "find").cb("bad\n", 0);
        assert.deepEqual(setup.concat(events), [], text);
        assert.deepEqual(removed(procs), [], text);
    }
});

test("delete refuses the active profile and removes only an inactive profile's folder", () => {
    const { ctx, procs } = service({ profiles: [profile("a"), profile("b")] });
    assert.equal(ctx.deleteProfile("a"), false);
    assert.equal(ctx.deleteProfile("b"), true);
    assert.deepEqual(removed(procs), [["rm", "-rf", "--", "/cfg/profiles/b"]]);
});

test("the draft sweep removes only id-named folders without a profile.json", t => {
    const root = mkdtempSync(join(tmpdir(), "profiles-sweep-"));
    t.after(() => rmSync(root, { recursive: true, force: true }));
    const dir = join(root, "profiles");
    const outside = join(root, "outside");
    mkdirSync(outside);
    const mk = (name, json) => {
        mkdirSync(join(dir, name), { recursive: true });
        if (json !== undefined)
            writeFileSync(join(dir, name, "profile.json"), json);
    };
    mk("a", fileText(profile("a")));
    mk("bad", "{ nope");
    mk("old_1");
    mk("x y");
    mkdirSync(join(dir, "dangling"));
    symlinkSync(join(root, "missing.json"), join(dir, "dangling", "profile.json"));
    symlinkSync(outside, join(dir, "linked"));
    const { ctx } = service({ profiles: [profile("a")], files: { bad: "{ nope" }, dir, realProc: true });
    const draft = ctx.startDraft();
    assert.deepEqual(readdirSync(dir).sort(), ["a", "bad", "dangling", "linked", draft, "x y"].sort());
    assert.ok(readdirSync(outside).length === 0 && readdirSync(join(dir, "a")).includes("profile.json"));
});

test("applying groups changes only those groups and keeps the active profile", () => {
    const { ctx, live } = service({ profiles: [profile("a"), profile("b")] });
    assert.equal(ctx.applyGroups("b", ["dock"]), true);
    assert.deepEqual(clone(live), { settings: { frameEnabled: true }, session: { dockPins: {} } });
    assert.equal(ctx.SessionData.activeConfigProfile, "a");
});

test("plugins a profile doesn't know keep their settings on switch", () => {
    const { ctx } = service({ profiles: [profile("a"), profile("b", { groups: ["plugins"], pluginSettings: { known: { enabled: false } } })] });
    ctx.SettingsData.pluginSettings = { known: { enabled: true }, later: { enabled: true, x: 1 } };
    assert.equal(ctx.activate("b"), true);
    assert.deepEqual(clone(ctx.SettingsData.pluginSettings), { known: { enabled: false }, later: { enabled: true, x: 1 } });
});

test("import never activates or applies, and failed imports and exports show the CLI's reason", () => {
    const { ctx, events, procs, toasts, disk, imported } = service({ profiles: [profile("a")] });
    ctx.importProfile("/tmp/in.tar.gz");
    procs.at(-1).cb("b\n", 0);
    disk.b = fileText(profile("b"));
    ctx._setFolders(Object.keys(disk));
    assert.deepEqual(imported, ["b"]);
    assert.equal(ctx.SessionData.activeConfigProfile, "a");
    assert.deepEqual(events, []);
    ctx.importProfile("/tmp/in.tar.gz");
    procs.at(-1).cb("invalid profile archive: not a gzip file\n", 1);
    ctx.exportProfile("a", "/tmp/a.tar.gz");
    procs.at(-1).cb("failed to read profile: gone\n", 1);
    assert.deepEqual(toasts, ["invalid profile archive: not a gzip file", "failed to read profile: gone"]);
});

test("an image onto the current file name never removes that file, whether the copy works or fails", () => {
    for (const code of [0, 1]) {
        const { ctx, procs } = service({ profiles: [profile("a", { thumbnail: "preview.jpg" })] });
        assert.equal(ctx.setImageFromFile("a", "/x/y.jpg"), true);
        procs[0].cb("", code);
        assert.deepEqual(removed(procs), [], String(code));
    }
});
