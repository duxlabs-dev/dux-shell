import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";

const source = readFileSync(new URL("../Services/PluginService.qml", import.meta.url), "utf8");

// Mirrors Quickshell's FileView, where `loaded` is a bool property and not a connectable signal.
function fileView(disk, blockLoading) {
    return {
        createObject(_, props) {
            return {
                path: props.path,
                loaded: !!blockLoading,
                text() { return disk.get(this.path) ?? ""; },
                setText(content) { disk.set(this.path, content); },
                destroy() {}
            };
        }
    };
}

function service() {
    const disk = new Map();
    const context = vm.createContext({
        JSON, Object,
        _stateCache: {}, _stateLoaded: {}, _stateWriters: {}, _stateDirtyPlugins: {}, _stateDirCreated: true,
        _stateWriteTimer: { restart() {} },
        stateLoadFvComp: fileView(disk, true),
        stateSaveFvComp: fileView(disk, false),
        Paths: { state: "/state", strip: path => path, mkdir() {} },
        log: { warn() {} },
        pluginStateChanged() {}
    });
    context.root = context;
    for (const match of source.matchAll(/^    function (\w+)\([^\n]*\)(?:: \w+)? \{\n[\s\S]*?^    \}/gm))
        vm.runInContext(match[0], context);
    return { context, disk };
}

test("the first state save after a plugin reload reaches disk", () => {
    const { context, disk } = service();
    const path = context.getPluginStatePath("fixture");
    for (const existing of [false, true]) {
        disk.clear();
        context._stateCache = {};
        context._stateLoaded = {};
        context._stateWriters = {};
        if (existing)
            disk.set(path, JSON.stringify({ count: 0 }));
        context.savePluginState("fixture", "count", 1);
        context._flushDirtyStates();
        context._cleanupPluginStateWriter("fixture");
        context.savePluginState("fixture", "count", 2);
        context._flushDirtyStates();
        assert.equal(JSON.parse(disk.get(path)).count, 2);
    }
});
