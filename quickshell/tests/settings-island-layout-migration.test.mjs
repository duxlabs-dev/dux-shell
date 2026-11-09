import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

test("version 43 island layouts migrate into the configured compact widgets", () => {
    const migrated = store.migrateToVersion({
        configVersion: 43,
        barConfigs: [{
            id: "island",
            island: true,
            islandHomeLayout: [{ id: "workspaces" }, { id: "media" }],
            centerWidgets: [{ id: "music", enabled: false }, { id: "clipboard", enabled: true }]
        }]
    }, 44);

    assert.equal(migrated.configVersion, 44);
    assert.deepEqual(JSON.parse(JSON.stringify(migrated.barConfigs[0].centerWidgets.map(widget => [widget.id, widget.enabled]))), [
        ["workspaceSwitcher", true],
        ["music", true],
        ["clipboard", true]
    ]);
    assert.equal(migrated.barConfigs[0].islandHomeLayout, undefined);
    assert.equal(store.migrateToVersion(migrated, 44), null);
});


test("version 43 islands without a stored layout migrate the default home face", () => {
    for (const centerWidgets of [[], [{id: "weather"}, {id: "music", mediaArtworkCircular: false}]]) {
        const migrated = store.migrateToVersion({configVersion: 43, barConfigs: [{island: true, centerWidgets}]}, 44);
        const widgets = migrated.barConfigs[0].centerWidgets;
        assert.deepEqual(Array.from(widgets, widget => widget.id), ["music", "clock", "notificationButton", "privacyIndicator"]);
        assert.equal(widgets[0].mediaStyle, "activity");
        assert.equal(store.migrateToVersion(migrated, 44), null);
    }
    for (const bar of [{centerWidgets: [{id: "weather"}]}, {island: true, dot: true, centerWidgets: [{id: "weather"}]}]) {
        const migrated = store.migrateToVersion({configVersion: 43, barConfigs: [bar]}, 44);
        assert.deepEqual(Array.from(migrated.barConfigs[0].centerWidgets, widget => widget.id), ["weather"]);
    }
});
