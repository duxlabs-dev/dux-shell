import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const source = readFileSync(new URL("../Common/SettingsData.qml", import.meta.url), "utf8");
const Spec = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url));
const SpecUtil = loadScript(new URL("../DCommon/Common/settings/SpecUtil.js", import.meta.url));
const Store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
const Profiles = loadScript(new URL("../Common/settings/ConfigProfiles.js", import.meta.url));
const defaults = Object.fromEntries(Object.entries(Spec.SPEC).map(([k, s]) => [k, SpecUtil.cloneDef(s.def)]));

// settings.json holds `initial`; the reload puts every key back from it, missing keys as defaults.
function settings(initial, flags = {}) {
    const file = { settings: Object.assign({}, initial), writes: 0, setSettings(next) { this.settings = next; this.writes++; } };
    const context = vm.createContext(Object.assign({}, defaults, initial, {
        Spec, SpecUtil, Qt: { callLater() {} },
        isGreeterMode: false, _parseError: false, _hasLoaded: true, _loading: false, settingsConfigVersion: 1,
        _settingsFiles: new Map([["settings.json", file]]),
        _splitSettingsByFile: all => ({ "settings.json": all }),
        _mergeSessionState() {},
        _hooks: new Proxy({}, { get: () => () => {} })
    }, flags));
    context.root = context;
    context._getCurrentSettings = () => Store.toJson(context, new Set(Object.keys(file.settings)));
    context._loadSettings = () => {
        for (const key in Spec.SPEC)
            if (Spec.SPEC[key].persist !== false)
                context[key] = key in file.settings ? file.settings[key] : SpecUtil.cloneDef(Spec.SPEC[key].def);
    };
    const match = source.match(/^    function applyProfileSettings\([^\n]*\) \{\n[\s\S]*?^    \}/m);
    if (!match)
        throw new Error("applyProfileSettings not found in SettingsData.qml");
    vm.runInContext(match[0], context);
    return { context, file };
}

test("applying a profile while settings failed to parse writes nothing", () => {
    const { context, file } = settings({ fontFamily: "Comic Sans" }, { _parseError: true });
    assert.equal(context.applyProfileSettings({ fontFamily: "Inter" }, ["fontFamily"]), false);
    assert.equal(file.writes, 0);
    assert.equal(context.fontFamily, "Comic Sans");
});

test("a key the profile leaves out resets to its default, and keys out of scope stay", () => {
    const { context, file } = settings({ fontFamily: "Comic Sans", iconThemeDark: "Papirus", niriLayoutGapsOverride: 5 });
    assert.equal(context.applyProfileSettings({}, Profiles.settingsKeys(["fonts_motion", "icons"])), true);
    assert.equal(context.fontFamily, Spec.SPEC.fontFamily.def);
    assert.equal(context.iconThemeDark, Spec.SPEC.iconThemeDark.def);
    assert.equal(file.settings.niriLayoutGapsOverride, 5);
    assert.equal(context.niriLayoutGapsOverride, 5);
});
