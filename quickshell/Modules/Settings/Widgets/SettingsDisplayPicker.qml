pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Column {
    id: root

    property var displayPreferences: []
    property bool emptyMeansAll: true
    property bool allowEmpty: false
    property bool showLastDisplay: false
    property bool showOnLastDisplay: false
    property bool allowHideOnLastDisplay: false
    property bool hideOnLastDisplay: false
    readonly property bool localAllDisplays: !Array.isArray(displayPreferences) || displayPreferences.includes("all") || (emptyMeansAll && displayPreferences.length === 0)

    // A callback, not a signal: Qt 6.12 hands signal array parameters over as a V4Sequence that fails Array.isArray.
    property var preferencesHandler: null
    signal lastDisplayToggled(bool checked)
    signal hideOnLastDisplayToggled(bool checked)

    width: parent?.width ?? 0
    spacing: SettingsMetrics.groupGap

    function screenPref(screen) {
        const pref = {
            name: screen.name,
            model: screen.model || ""
        };
        const modelIndex = SettingsData.getScreenModelIndex(screen);
        if (modelIndex >= 0)
            pref.modelIndex = modelIndex;
        return pref;
    }

    SettingsToggleRow {
        text: I18n.tr("All displays")
        checked: root.localAllDisplays
        onToggled: checked => root.preferencesHandler?.(checked ? ["all"] : Quickshell.screens.map(screen => root.screenPref(screen)))
    }

    SettingsToggleRow {
        text: I18n.tr("Show on last display")
        visible: root.showLastDisplay
        enabled: !root.localAllDisplays
        checked: root.showOnLastDisplay
        onToggled: checked => root.lastDisplayToggled(checked)
    }

    SettingsToggleRow {
        text: I18n.tr("Hide on last display", "bar display assignment option")
        visible: root.allowHideOnLastDisplay
        checked: root.hideOnLastDisplay
        onToggled: checked => root.hideOnLastDisplayToggled(checked)
    }

    Repeater {
        model: Quickshell.screens

        SettingsToggleRow {
            required property var modelData

            text: SettingsData.getScreenDisplayName(modelData)
            description: modelData.width + "×" + modelData.height + " · " + (SettingsData.displayNameMode === "system" ? (modelData.model || I18n.tr("Unknown Model")) : modelData.name)
            enabled: !root.localAllDisplays
            checked: root.localAllDisplays || SettingsData.isScreenInPreferences(modelData, root.displayPreferences)
            onToggled: checked => {
                const prefs = (Array.isArray(root.displayPreferences) ? root.displayPreferences : []).filter(pref => pref !== "all" && !SettingsData.isScreenInPreferences(modelData, [pref]));
                if (checked)
                    prefs.push(root.screenPref(modelData));
                if (!root.allowEmpty && prefs.length === 0)
                    return;
                root.preferencesHandler?.(prefs);
            }
        }
    }
}
