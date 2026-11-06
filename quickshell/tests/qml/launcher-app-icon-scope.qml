import QtQuick
import QtTest
import Quickshell
import qs.Common
import qs.Services
import qs.Modals.DLauncherV2
import qs.Modals.DLauncherV2.Components
import qs.DCommon.Common as DC

ShellRoot {
    id: root
    property bool failed: false
    function check(condition, label) {
        if (!condition) {
            failed = true;
            console.log("FIXTURE_FAIL " + label);
        }
    }
    function findIcon(item) {
        if (item.iconValue !== undefined && item.fallbackText !== undefined)
            return item;
        for (const child of item.children ?? []) {
            const found = findIcon(child);
            if (found)
                return found;
        }
        return null;
    }
    PanelWindow {
        id: panel
        implicitWidth: 800; implicitHeight: 400
        TestCase { id: test; when: false }
        LauncherRow { id: row; x: 20; y: 20; width: 350 }
        LauncherTile { id: tile; x: 400; y: 20; width: 180; height: 240 }
    }
    Component.onCompleted: {
        Quickshell.watchFiles = false;
        DC.Style.theme = Theme;
        DC.Style.settings = SettingsData;
        DC.I18n.backend = I18n;
    }
    Timer {
        interval: 0
        running: SettingsData._hasLoaded && SessionData._hasLoaded
        onTriggered: {
            const types = ["app", "file", "setting", "plugin", "plugin_browse", "clipboard", "unknown", undefined];
            for (const enabled of [true, false]) {
                SettingsData.dankLauncherV2ShowAppIcons = enabled;
                for (const type of types) {
                    const item = {type: type, name: "Scope fixture", iconType: type === "plugin" ? "unicode" : "material", icon: type === "plugin" ? "😀" : "apps"};
                    row.item = item;
                    tile.item = item;
                    test.wait(0);
                    test.waitForPolish(panel, 20000);
                    const rowIcon = findIcon(row);
                    const tileIcon = findIcon(tile);
                    const expected = enabled || type !== "app";
                    check(rowIcon && rowIcon.visible === expected, "row " + type + " toggle=" + enabled);
                    check(tileIcon && tileIcon.visible === expected, "tile " + type + " toggle=" + enabled);
                    const text = row.children.find(child => child._richBudget !== undefined);
                    check(text && Math.abs(text.x - (LauncherMetrics.rowPadding + (expected ? rowIcon.x + rowIcon.width : 0))) < 1,
                        "row anchor " + type + " toggle=" + enabled);
                }
            }
            row.item = {type: "app", name: "App picker"};
            tile.item = row.item;
            test.wait(0);
            check(!findIcon(row).visible && !findIcon(tile).visible, "app picker follows app preference");
            console.log(root.failed ? "FIXTURE_FAIL see above" : "FIXTURE_PASS");
            Qt.quit();
        }
    }
}
