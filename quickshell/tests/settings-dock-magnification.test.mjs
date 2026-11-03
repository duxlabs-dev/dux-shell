import assert from "node:assert/strict";
import test from "node:test";
import { loadScript } from "./qml-script.mjs";

const store = loadScript(new URL("../Common/settings/SettingsStore.js", import.meta.url));

function migrate(dock, widget) {
    const settings = { configVersion: 41, dockConfigs: [Object.assign({ id: "dock", widgets: [Object.assign({ id: "dock_apps", widgetId: "appsDock" }, widget)] }, dock)] };
    return JSON.parse(JSON.stringify(store.migrateToVersion(settings, 42))).dockConfigs[0];
}

test("dock apps sizing folds into the dock and the widget copies are dropped", () => {
    const cases = [
        { dock: {}, widget: { appsDockEnlargeOnHover: true, appsDockEnlargePercentage: 140 }, magnification: true, scale: 140 },
        { dock: {}, widget: { appsDockEnlargeOnHover: true, appsDockEnlargePercentage: 100 }, magnification: true, scale: 105 },
        { dock: { magnification: true, magnificationScale: 150 }, widget: { appsDockEnlargeOnHover: true, appsDockEnlargePercentage: 110 }, magnification: true, scale: 150 },
        { dock: { magnification: false, magnificationScale: 130 }, widget: { appsDockEnlargeOnHover: false, appsDockEnlargePercentage: 140 }, magnification: false, scale: 130 },
        { dock: { iconSize: 40 }, widget: { appsDockIconSizePercentage: 150 }, iconSize: 60 },
        { dock: { iconSize: 48 }, widget: { appsDockIconSizePercentage: 100 }, iconSize: 48 }
    ];
    for (const { dock, widget, magnification, scale, iconSize } of cases) {
        const migrated = migrate(dock, widget);
        if (magnification !== undefined) {
            assert.equal(migrated.magnification === true, magnification);
            assert.equal(migrated.magnificationScale, scale);
        }
        if (iconSize !== undefined)
            assert.equal(migrated.iconSize, iconSize);
        assert.deepEqual(migrated.widgets, [{ id: "dock_apps", widgetId: "appsDock" }]);
    }
});
