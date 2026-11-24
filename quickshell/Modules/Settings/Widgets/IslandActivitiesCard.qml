pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

Column {
    id: root

    required property var store
    property string keyPrefix: "island"

    readonly property bool activitiesEnabled: root.store.setting("islandActivitiesEnabled")
    readonly property var sourceOverrides: root.store.setting("islandActivitySourceOverrides") || {}
    readonly property var overrideSources: [...new Set(IslandActivityService.entries.filter(entry => entry.persistent).map(entry => entry.source).concat(Object.keys(root.sourceOverrides)))]
    function sourceOverride(source, key) {
        return root.sourceOverrides[source]?.[key] || "activity";
    }

    function setSourceOverride(source, key, value) {
        const overrides = Object.assign({}, root.sourceOverrides);
        const sourceSettings = Object.assign({}, overrides[source] || {});
        if (value === "activity")
            delete sourceSettings[key];
        else
            sourceSettings[key] = value;
        if (Object.keys(sourceSettings).length)
            overrides[source] = sourceSettings;
        else
            delete overrides[source];
        root.store.apply("islandActivitySourceOverrides", overrides);
    }

    width: parent?.width ?? 0
    spacing: SettingsMetrics.cardGap

    SettingsCard {
        iconName: "animation"
        title: I18n.tr("Live activities", "island activity settings")
        settingKey: root.keyPrefix + "LiveActivities"
        tags: ["island", "activities", "live", "plugins", "ipc"]

        SettingsToggleRow {
            settingKey: root.keyPrefix + "ActivitiesEnabled"
            tags: ["island", "activities", "plugins", "ipc"]
            resetStore: root.store
            resetKeys: ["islandActivitiesEnabled"]
            text: I18n.tr("Plugin activities", "island activity settings")
            description: I18n.tr("Let plugins and IPC clients show progress, timers and other live updates in the island", "island activity settings")
            checked: root.activitiesEnabled
            onToggled: checked => root.store.apply("islandActivitiesEnabled", checked)
        }

        SettingsSliderRow {
            settingKey: root.keyPrefix + "ActivityDuration"
            tags: ["island", "activities", "preview", "duration", "timeout"]
            visible: root.activitiesEnabled
            resetStore: root.store
            resetKeys: ["islandActivityDuration"]
            text: I18n.tr("Preview duration", "island activity settings")
            description: I18n.tr("How long a new activity stays open before the island returns to its usual content", "island activity settings")
            minimum: 1000
            maximum: 15000
            step: 500
            unit: "ms"
            value: root.store.setting("islandActivityDuration")
            onSliderValueChanged: value => root.store.apply("islandActivityDuration", value)
        }

        SettingsSliderRow {
            settingKey: root.keyPrefix + "ActivitySlotLimit"
            tags: ["island", "activities", "persistent", "slots", "ongoing"]
            visible: root.activitiesEnabled
            resetStore: root.store
            resetKeys: ["islandActivitySlotLimit"]
            text: I18n.tr("Persistent activity slots", "island activity settings")
            description: I18n.tr("Ongoing activities kept as small icons beside the island content. 0 hides them", "island activity settings")
            minimum: 0
            maximum: 6
            step: 1
            value: root.store.setting("islandActivitySlotLimit")
            onSliderValueChanged: value => root.store.apply("islandActivitySlotLimit", value)
        }

        SettingsTextFieldRow {
            settingKey: root.keyPrefix + "ExcludedSources"
            tags: ["island", "activities", "hidden", "exclude", "block", "plugins", "ipc"]
            visible: root.activitiesEnabled
            resetStore: root.store
            resetKeys: ["islandExcludedSources"]
            text: I18n.tr("Hidden activity sources", "island activity settings")
            description: I18n.tr("Comma-separated plugin or IPC source IDs that never show here", "island activity settings")
            value: (root.store.setting("islandExcludedSources") || []).join(", ")
            onEditingFinished: value => root.store.apply("islandExcludedSources", value.split(",").map(id => id.trim()).filter(id => id))
        }

        Repeater {
            model: NotificationInterceptorService.entries

            SettingsToggleRow {
                required property var modelData
                tags: ["island", "activities", "notifications", "intercept", "plugins"]
                text: modelData.label
                description: modelData.description || modelData.source + " · " + modelData.id
                checked: NotificationInterceptorService.enabled(modelData)
                onToggled: checked => NotificationInterceptorService.setEnabled(modelData.source, modelData.id, checked)
            }
        }
    }

    SettingsCard {
        iconName: "tune"
        title: I18n.tr("Activity sources", "island activity settings: per-source overrides card title")
        settingKey: root.keyPrefix + "ActivitySourceOverrides"
        tags: ["island", "activities", "sources", "position", "click", "plugins"]
        visible: root.activitiesEnabled && root.overrideSources.length > 0

        SettingsRow {
            iconName: "info"
            iconColor: Theme.surfaceVariantText
            resetStore: root.store
            resetKeys: ["islandActivitySourceOverrides"]
            title: I18n.tr("Overrides", "island activity settings: per-source overrides row")
            subtitle: I18n.tr("Change where an activity sits, what it shows when collapsed and what a click opens", "island activity settings: per-source overrides description")
        }

        Repeater {
            model: root.overrideSources

            Column {
                id: sourceOptions

                required property string modelData

                width: parent.width
                spacing: SettingsMetrics.groupGap

                SettingsDropdownRow {
                    text: I18n.tr("Activity position", "island activity settings") + " · " + sourceOptions.modelData
                    optionValues: ["activity", "left", "center", "right"]
                    options: [I18n.tr("Set by activity", "island activity settings"), I18n.tr("Left", "island activity settings"), I18n.tr("Center", "island activity settings"), I18n.tr("Right", "island activity settings")]
                    currentValue: root.sourceOverride(sourceOptions.modelData, "position")
                    onValueChanged: value => root.setSourceOverride(sourceOptions.modelData, "position", value)
                }

                SettingsDropdownRow {
                    text: I18n.tr("Collapsed content", "island activity settings") + " · " + sourceOptions.modelData
                    optionValues: ["activity", "icon", "label"]
                    options: [I18n.tr("Set by activity", "island activity settings"), I18n.tr("Icon", "island activity settings"), I18n.tr("Label", "island activity settings")]
                    currentValue: root.sourceOverride(sourceOptions.modelData, "compact")
                    onValueChanged: value => root.setSourceOverride(sourceOptions.modelData, "compact", value)
                }

                SettingsDropdownRow {
                    text: I18n.tr("Click action", "island activity settings") + " · " + sourceOptions.modelData
                    optionValues: ["activity", "live", "home", "media", "clipboard", "controlcenter", "notificationcenter"]
                    options: [I18n.tr("Set by activity", "island activity settings"), I18n.tr("Live activity", "island activity settings"), I18n.tr("Dashboard", "island activity settings"), I18n.tr("Media", "island activity settings"), I18n.tr("Clipboard", "island activity settings"), I18n.tr("Control Center", "island activity settings"), I18n.tr("Notifications", "island activity settings")]
                    currentValue: root.sourceOverride(sourceOptions.modelData, "clickActivity")
                    onValueChanged: value => root.setSourceOverride(sourceOptions.modelData, "clickActivity", value)
                }
            }
        }
    }
}
