pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/settings/DockConfig.js" as DockConfig
import "../DBar/OverflowLayout.js" as OverflowLayout

Item {
    id: root

    property var parentModal: null

    readonly property string dockId: SettingsUiState.selectedDockId
    readonly property bool dockHosted: dockId !== ""
    readonly property string barId: SettingsUiState.selectedBarId
    readonly property string section: SettingsUiState.selectedWidgetSection
    readonly property int index: SettingsUiState.selectedWidgetIndex
    readonly property var entry: {
        if (dockHosted)
            return SettingsData.getDockConfig(dockId)?.widgets.find(item => item.id === SettingsUiState.selectedDockWidgetId) ?? null;
        SettingsData.barConfigs;
        const config = SettingsData.getBarConfig(barId);
        const raw = (config?.[section + "Widgets"] ?? [])[index];
        if (raw === undefined)
            return null;
        return typeof raw === "string" ? ({
                "id": raw,
                "enabled": true
            }) : raw;
    }
    readonly property string widgetType: entry?.widgetId ?? entry?.id ?? ""
    readonly property bool sectionAutoOverflow: SettingsData.getBarConfig(barId)?.[section + "OverflowMode"] !== "bar"
    readonly property bool hasPill: !dockHosted && !["spacer", "separator", "island"].includes(widgetType)
    readonly property bool barBackground: !(SettingsData.barConfigs.find(config => config.id === barId)?.noBackground ?? false)
    readonly property bool barScrollOverridesWidgets: {
        if (dockHosted)
            return false;
        SettingsData.barConfigs;
        const config = SettingsData.getBarConfig(barId);
        return (config?.scrollEnabled ?? true) && !config?.island && (config?.overrideWidgetScroll ?? false) && (config?.scrollYBehavior ?? "workspace") !== "none";
    }
    readonly property string barScrollOverrideHint: I18n.tr("Disabled by Override widget scroll", "bar widget scroll row, Override widget scroll is the Bar Scroll wheel toggle name")
    readonly property var store: ({
            "get": key => root.value(key),
            "set": (key, value) => root.set(key, value),
            "isDefault": keys => root.isDefault(keys),
            "resetToDefault": keys => root.resetToDefault(keys)
        })

    // Options the dock surface itself reads live on the dock configuration; a bar keeps per-instance
    // copies under bar-prefixed keys. One options page, two homes.
    readonly property var _barAppKeys: ({
            "maxVisibleApps": "barMaxVisibleApps",
            "maxVisibleRunningApps": "barMaxVisibleRunningApps",
            "showOverflowBadge": "barShowOverflowBadge"
        })

    readonly property var appStore: ({
            "get": key => {
                if (!root.dockHosted)
                    return root.value(root._barAppKeys[key] ?? key);
                const config = SettingsData.getDockConfig(root.dockId);
                return config ? config[key] : DockConfig.create("", "")[key];
            },
            "set": (key, value) => {
                if (!root.dockHosted) {
                    root.set(root._barAppKeys[key] ?? key, value);
                    return;
                }
                SettingsData.updateDockConfig(root.dockId, {
                    [key]: value
                });
            },
            "isDefault": keys => keys.every(key => JSON.stringify(root.appStore.get(key)) === JSON.stringify(root.appDefault(key))),
            "resetToDefault": keys => keys.forEach(key => root.appStore.set(key, root.appDefault(key)))
        })

    function appDefault(key) {
        if (dockHosted)
            return DockConfig.create("", "")[key];
        return defaultOption(_barAppKeys[key] ?? key);
    }

    readonly property var _dockAppsDefaults: ({
            "appsDockHideIndicators": false
        })

    function defaultOption(key) {
        if (!dockHosted && key === "overflowMode")
            return "section";
        if (!dockHosted && key === "overflowPriority")
            return 0;
        if (dockHosted && widgetType === "appsDock" && key in _dockAppsDefaults)
            return _dockAppsDefaults[key];
        return SettingsData.widgetDefaults(widgetType)[key];
    }

    function value(key) {
        if (!dockHosted && key === "overflowMode")
            return entry?.overflowMode ?? "section";
        if (!dockHosted && key === "overflowPriority")
            return OverflowLayout.priority(entry);
        if (dockHosted && widgetType === "appsDock" && key in _dockAppsDefaults)
            return entry?.[key] ?? _dockAppsDefaults[key];
        return SettingsData.widgetOption(widgetType, entry, key);
    }

    function set(key, newValue) {
        const updates = {};
        updates[key] = newValue;
        if (dockHosted)
            SettingsData.updateDockWidget(dockId, SettingsUiState.selectedDockWidgetId, updates);
        else
            SettingsData.updateBarWidget(barId, section, index, updates);
    }

    function isDefault(keys) {
        return keys.every(key => defaultOption(key) === undefined || JSON.stringify(value(key)) === JSON.stringify(defaultOption(key)));
    }

    function resetToDefault(keys) {
        for (const key of keys) {
            const fallback = defaultOption(key);
            if (fallback !== undefined)
                set(key, fallback);
        }
    }

    function load() {
        const file = root.dockHosted && BarWidgetCatalog.get(widgetType)?.barOnly ? "" : BarWidgetCatalog.optionsFile(widgetType);
        if (!file) {
            optionsLoader.source = "";
            return;
        }
        optionsLoader.setSource("BarWidgetOptions/" + file, {
            "page": root
        });
    }

    onWidgetTypeChanged: load()
    Component.onCompleted: load()

    SettingsPage {
        SettingsCard {
            visible: root.widgetType === "weather"
            title: I18n.tr("Weather")

            SettingsNavRow {
                title: I18n.tr("Weather")
                iconName: "partly_cloudy_day"
                onClicked: keyboard => root.parentModal?.navigateTo("weather", keyboard)
            }
        }

        SettingsCard {
            settingKey: "barWidgetGeneral"

            SettingsToggleRow {
                iconName: SettingsUiState.selectedWidgetIcon
                text: root.dockHosted ? I18n.tr("Show in dock") : I18n.tr("Show in bar")
                description: SettingsUiState.selectedWidgetDescription
                checked: root.entry?.enabled !== false
                onToggled: checked => root.set("enabled", checked)
            }

            SettingsDropdownRow {
                readonly property string sectionMode: root.sectionAutoOverflow ? "auto" : "bar"
                readonly property var placementValues: ["section"].concat(["auto", "bar", "always"].filter(mode => mode !== sectionMode))
                readonly property var placementLabels: [sectionMode].concat(placementValues.slice(1)).map(mode => mode === "auto" ? I18n.tr("Auto") : mode === "bar" ? I18n.tr("Keep in Bar") : I18n.tr("Always in overflow", "bar widget placement option, the widget always lives in the overflow menu"))
                readonly property string placementValue: root.value("overflowMode") === sectionMode ? "section" : root.value("overflowMode")

                visible: !root.dockHosted && !OverflowLayout.pinned(root.widgetType)
                resetStore: root.store
                resetKeys: ["overflowMode"]
                text: I18n.tr("Placement")
                description: I18n.tr("Auto moves this widget into overflow when the bar runs out of space", "bar widget placement dropdown description")
                options: placementLabels
                currentValue: placementLabels[Math.max(0, placementValues.indexOf(placementValue))]
                onValueChanged: value => root.set("overflowMode", placementValues[placementLabels.indexOf(value)])
            }

            SettingsSliderRow {
                visible: !root.dockHosted && !OverflowLayout.pinned(root.widgetType) && OverflowLayout.placement(root.entry, root.sectionAutoOverflow ? "auto" : "bar") === "auto"
                resetStore: root.store
                resetKeys: ["overflowPriority"]
                text: I18n.tr("Overflow priority", "bar widget setting, how early an auto widget moves into overflow")
                description: I18n.tr("Lower priorities move into overflow first", "bar widget overflow priority slider description")
                value: root.value("overflowPriority")
                minimum: -10
                maximum: 10
                onSliderValueChanged: value => root.set("overflowPriority", value === 0 ? undefined : value)
            }

            SettingsToggleRow {
                visible: root.hasPill
                tags: ["widget", "background", "pill", "transparent"]
                text: I18n.tr("Background")
                checked: root.entry?.background ?? root.barBackground
                onToggled: checked => root.set("background", checked === root.barBackground ? undefined : checked)
            }
        }

        Loader {
            id: optionsLoader
            width: parent.width
            asynchronous: true
            opacity: status === Loader.Ready ? 1 : 0

            Behavior on opacity {
                enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
                NumberAnimation {
                    duration: SettingsMetrics.fadeDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }
        }

        Item {
            width: parent.width
            height: optionsLoader.status === Loader.Loading ? Theme.iconButtonSize * 2 : 0
            visible: optionsLoader.status === Loader.Loading

            DSpinner {
                anchors.centerIn: parent
            }
        }
    }
}
