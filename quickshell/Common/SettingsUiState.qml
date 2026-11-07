pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    property string selectedBarId: "default"
    property string selectedWallpaperScreen: ""
    // Which dock the Dock hub pages are editing.
    property string dockHubSelection: ""
    // Set only while the widget settings page is showing a dock-hosted widget; empty means bar-hosted.
    property string selectedDockId: ""
    property string selectedDockWidgetId: ""
    property string selectedDesktopWidgetId: ""
    // "" = new profile
    property string selectedConfigProfileId: ""
    // Kept editor form per profile id ("" = new profile)
    property var configProfileEdits: ({})

    function dropConfigProfileEdits(id) {
        const rest = Object.assign({}, configProfileEdits);
        delete rest[id];
        configProfileEdits = rest;
    }
    property bool selectedConfigProfileImported: false
    property string selectedWidgetSection: ""
    property int selectedWidgetIndex: -1
    property string selectedWidgetTitle: ""
    property string selectedWidgetDescription: ""
    property string selectedWidgetIcon: ""
    property string selectedFcitx5Addon: ""
    property string selectedFcitx5AddonTitle: ""
    property string selectedFcitx5SubAddon: ""
    property string selectedFcitx5SubAddonTitle: ""

    // The dot has its own page, so bar selection never lands on it.
    function normalizeSelectedBar() {
        const config = SettingsData.getBarConfig(selectedBarId);
        if (config && !SettingsData.isDotBarConfig(config))
            return;
        selectedBarId = SettingsData.barConfigs.find(cfg => !SettingsData.isDotBarConfig(cfg))?.id ?? "default";
    }

    Connections {
        target: SettingsData

        function onBarConfigsChanged() {
            root.normalizeSelectedBar();
        }
    }
}
