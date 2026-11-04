import QtQuick
import QtTest
import "../../Common/IslandLayout.js" as IslandLayout

TestCase {
    name: "IslandLayout"

    function test_migrateLegacyLayout() {
        const config = {
            island: true,
            islandHomeLayout: [{id: "workspaces"}, {id: "media"}, {id: "clock", enabled: false}],
            leftWidgets: [{id: "workspaceSwitcher", enabled: false, showWorkspaceApps: true}],
            centerWidgets: [{id: "music"}, {id: "clipboard", enabled: true}],
            islandMediaArtworkCircular: false
        };
        IslandLayout.migrate(config);
        compare(config.centerWidgets.map(entry => entry.id), ["workspaceSwitcher", "music", "clipboard"]);
        verify(config.centerWidgets[0].showWorkspaceApps);
        verify(config.centerWidgets[0].enabled);
        compare(config.centerWidgets[1].mediaTitleMode, "changes");
        compare(config.centerWidgets[1].mediaArtworkCircular, false);
        verify(config.islandHomeLayout === undefined);
        const serialized = JSON.stringify(config);
        IslandLayout.migrate(config);
        compare(JSON.stringify(config), serialized);
    }

    function test_widgetsRespectConfiguredLayout() {
        const config = {centerWidgets: [{id: "music", enabled: false}, {id: "customPlugin", enabled: true}, "clipboard", "island"]};
        const original = JSON.stringify(config);
        const widgets = IslandLayout.widgets(config);
        compare(widgets.map(entry => entry.id), ["music", "customPlugin", "clipboard"]);
        compare(widgets[0].enabled, false);
        compare(widgets[0].mediaTitleMode, "changes");
        compare(widgets[0].mediaAlwaysVisible, true);
        compare(JSON.stringify(config), original);
        compare(IslandLayout.widgets({centerWidgets: []}).length, 0);
    }

    function test_islandPresentations() {
        compare(IslandLayout.groupForWidget("workspaceSwitcher"), "workspaces");
        compare(IslandLayout.groupForWidget("music"), "media");
        compare(IslandLayout.groupForWidget("clock"), "clock");
        compare(IslandLayout.groupForWidget("customPlugin"), "customPlugin");
        compare(IslandLayout.groupForWidget("controlCenterButton"), "controlCenterButton");
    }

    function test_regularBarsUnchanged() {
        for (const config of [{centerWidgets: ["clock"], islandHomeLayout: [{id: "media"}]}, {island: true, dot: true, islandHomeLayout: [{id: "media"}]}]) {
            const original = JSON.stringify(config);
            IslandLayout.migrate(config);
            compare(JSON.stringify(config), original);
        }
    }
}
