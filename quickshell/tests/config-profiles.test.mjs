import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const profiles = loadScript(new URL("../Common/settings/ConfigProfiles.js", import.meta.url));
const settingsSpec = loadScript(new URL("../Common/settings/SettingsSpec.js", import.meta.url)).SPEC;
const sessionSpec = loadScript(new URL("../Common/settings/SessionSpec.js", import.meta.url)).SPEC;

function version(file, property) {
    return Number(readFileSync(new URL(file, import.meta.url), "utf8").match(new RegExp(`property int ${property}:\\s*(\\d+)`))[1]);
}

const SV = version("../Common/SettingsData.qml", "settingsConfigVersion");
const SSV = version("../Common/SessionData.qml", "sessionConfigVersion");
const plain = value => JSON.parse(JSON.stringify(value));
const persistedSettings = Object.keys(settingsSpec).filter(k => settingsSpec[k].persist !== false);

for (const [name, map, expected] of [["SETTINGS_MAP", profiles.SETTINGS_MAP, persistedSettings], ["SESSION_MAP", profiles.SESSION_MAP, Object.keys(sessionSpec)]]) {
    test(`${name}: every persisted key is in exactly one group or never, and no key is stale`, () => {
        const known = [...profiles.GROUPS, "never"];
        assert.deepEqual(Object.keys(map).filter(g => !known.includes(g)), [], "unknown groups");
        const seen = Object.values(map).flat();
        assert.deepEqual(expected.filter(k => !seen.includes(k)), [], `new keys: add each to a group (or "never") in ${name} in Common/settings/ConfigProfiles.js`);
        assert.deepEqual(seen.filter((k, i) => seen.indexOf(k) !== i), [], "keys in more than one group");
        assert.deepEqual(seen.filter(k => !expected.includes(k)), [], `removed keys: delete them from ${name} in Common/settings/ConfigProfiles.js`);
    });
}

test("auth, greeter and history settings never travel with a profile", () => {
    const hooks = ["scheduleAuthApply", "scheduleGreeterAutoLoginSync", "markGreeterSyncPending", "syncLauncherHistory"];
    assert.deepEqual(persistedSettings.filter(k => hooks.includes(settingsSpec[k].onChange) && !profiles.SETTINGS_MAP.never.includes(k)), []);
});

test("an old profile is migrated once and the input is left alone", () => {
    const old = { groups: ["control_center"], configVersion: 26, sessionConfigVersion: SSV, settings: { controlCenterColumns: 4 }, session: {} };
    const migrated = profiles.migrate(old, SV, SSV);
    assert.deepEqual([migrated.settings.controlCenterColumns, migrated.configVersion], [8, SV]);
    assert.equal(old.settings.controlCenterColumns, 4);
    assert.equal(profiles.migrate(migrated, SV, SSV), null);
});

test("scoped drops values whose JSON kind differs from the spec default", () => {
    const profile = {
        groups: ["bar", "cursor", "fonts_motion", "time_weather", "dark_mode", "dock"],
        settings: { barConfigs: {}, cursorSettings: [], fontFamily: 3, fontScale: "2", showSeconds: "yes", clockFormat: "24h" },
        session: { isLightMode: 1, dockPins: { dock: [] } }
    };
    const out = profiles.scoped(profile);
    assert.deepEqual(plain(out.settings), { clockFormat: "24h" });
    assert.deepEqual(plain(out.session), { dockPins: { dock: [] } });
});
