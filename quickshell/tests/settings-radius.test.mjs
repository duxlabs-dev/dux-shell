import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));
const spec = store.SpecModule;

test("legacy migration preserves explicit radii and defaults sparse settings to 50", () => {
    for (const version of [0, 18]) {
        for (const [radius, strength] of [[0, 0], [12, 38], [32, 100], [undefined, 50]]) {
            const original = { configVersion: version, cornerRadius: radius, niriLayoutRadiusOverride: 17 };
            const migrated = store.migrateToVersion(original, 26);
            assert.equal(migrated.radiusStrength, strength);
            assert.equal(migrated.configVersion, 26);
            assert.equal("cornerRadius" in migrated, false);
            assert.equal(migrated.niriLayoutRadiusOverride, 17);
            assert.equal(original.configVersion, version);
            assert.equal(original.cornerRadius, radius);
        }
    }
});

test("migration preserves a new value and does not rerun", () => {
    const migrated = store.migrateToVersion({ configVersion: 22, radiusStrength: 75, cornerRadius: 4 }, 25);
    assert.equal(migrated.radiusStrength, 75);
    assert.equal(store.migrateToVersion(migrated, 25), null);
    assert.equal(store.migrateToVersion(null, 25), null);
});

test("parse and sparse serialization use the same new default", () => {
    const root = { settingsConfigVersion: 25 };
    store.parse(root, {});
    assert.equal(root.radiusStrength, spec.SPEC.radiusStrength.def);
    assert.equal("radiusStrength" in store.toJson(root, new Set()), false);
    store.parse(root, { radiusStrength: 60 });
    assert.equal(store.toJson(root, new Set()).radiusStrength, 60);
    assert.equal("cornerRadius" in store.toJson(root, new Set()), false);
    store.parse(root, { radiusStrength: 200 });
    assert.equal(root.radiusStrength, 100);
    store.parse(root, { radiusStrength: "bad" });
    assert.equal(root.radiusStrength, spec.SPEC.radiusStrength.def);
});

test("changing strength invokes compositor layout update and persists", () => {
    const root = { radiusStrength: 50 };
    const calls = [];
    spec.set(root, "radiusStrength", 60, () => calls.push("save"), {
        updateCompositorLayout: (target, key, old) => calls.push([target.radiusStrength, key, old])
    });
    assert.equal(root.radiusStrength, 60);
    assert.deepEqual(calls, [[60, "radiusStrength", 50], "save"]);
});
