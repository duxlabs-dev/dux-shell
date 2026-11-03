pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.BarWidgetOptions
import "../../Common/settings/DockConfig.js" as DockConfig

Item {
    id: root

    property var parentModal: null
    property int catalogRevision: 0

    readonly property bool dockHosted: true
    readonly property var appsEntry: dock.appsEntry
    readonly property var appStore: ({
            "get": key => dock.config?.[key],
            "set": (key, value) => dock.setOption(key, value),
            "isDefault": keys => dock.isDefault(keys),
            "resetToDefault": keys => dock.resetToDefault(keys)
        })

    function value(key) {
        return dock.appsValue(key);
    }

    function set(key, value) {
        dock.setAppsOption(key, value);
    }

    function isDefault(keys) {
        return dock.apps.isDefault(keys);
    }

    function resetToDefault(keys) {
        dock.apps.resetToDefault(keys);
    }

    DockSelectionState {
        id: dock
    }

    Connections {
        target: PluginService

        function onPluginStateChanged() {
            root.catalogRevision++;
        }
        function onPluginDataChanged() {
            root.catalogRevision++;
        }
        function onPluginListUpdated() {
            root.catalogRevision++;
        }
        function onPluginLoaded() {
            root.catalogRevision++;
        }
    }

    readonly property var widgetChoices: {
        catalogRevision;
        return BarWidgetCatalog.widgets.filter(widget => !widget.barOnly).concat(PluginService.getAllPluginVariants().filter(variant => variant.loaded).map(variant => ({
                    id: variant.fullId,
                    text: variant.name,
                    icon: variant.icon
                })));
    }

    function widgetEntry(id) {
        return widgetChoices.find(widget => widget.id === id) ?? null;
    }

    readonly property var slotOptions: ({
            "dockLauncher": "launcherEnabled",
            "dockTrash": "showTrash"
        })

    // The bar names this widget "Apps dock", which reads wrong once it is listed inside a dock.
    function widgetName(id) {
        switch (id) {
        case "appsDock":
            return I18n.tr("Apps");
        case "dockLauncher":
            return I18n.tr("Launcher button");
        case "dockTrash":
            return I18n.tr("Trash");
        default:
            return widgetEntry(id)?.text ?? id;
        }
    }

    function widgetIcon(id) {
        switch (id) {
        case "dockLauncher":
            return "apps";
        case "dockTrash":
            return "delete";
        default:
            return widgetEntry(id)?.icon ?? "widgets";
        }
    }

    readonly property var orderedWidgets: {
        const widgets = dock.config?.widgets ?? [];
        const byId = new Map(widgets.map(item => [item.id, item]));
        return DockConfig.widgetOrder(widgets, dock.config?.order).map(id => byId.get(id));
    }

    function reorderWidgets(indices) {
        if (!dock.hasConfig)
            return;
        SettingsData.updateDockConfig(dock.selectedDockId, DockConfig.reorderWidgets(dock.config.widgets, dock.config.order, indices.map(i => root.orderedWidgets[i].id)));
    }

    function updateWidgets(widgets) {
        if (!dock.hasConfig)
            return;
        SettingsData.updateDockConfig(dock.selectedDockId, {
            widgets
        });
    }

    function configureWidget(item) {
        SettingsUiState.selectedDockId = dock.selectedDockId;
        SettingsUiState.selectedDockWidgetId = item.id;
        SettingsUiState.selectedWidgetTitle = root.widgetName(item.widgetId);
        SettingsUiState.selectedWidgetDescription = "";
        SettingsUiState.selectedWidgetIcon = root.widgetIcon(item.widgetId);
        root.parentModal?.navigateTo("bar_widget");
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "widgets"
            settingKey: "dockWidgets"
            tags: ["dock", "widgets", "apps", "add", "remove", "order"]

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["widgetExpansion"]
                readonly property var modes: ["popout", "inline"]

                text: I18n.tr("Open widgets")
                model: [I18n.tr("Popout"), I18n.tr("Inline", "adjective, dock widgets open inside the dock instead of a popout")]
                currentIndex: Math.max(0, modes.indexOf(dock.config?.widgetExpansion ?? "popout"))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    dock.setOption("widgetExpansion", modes[index]);
                }
            }

            SettingsReorderList {
                id: widgetList

                model: root.orderedWidgets
                onReordered: indices => root.reorderWidgets(indices)

                delegate: SettingsReorderRow {
                    id: widgetRow

                    required property var modelData

                    reorderList: widgetList
                    readonly property string slotOption: root.slotOptions[modelData.widgetId] ?? ""
                    readonly property bool shown: slotOption ? dock.config[slotOption] === true : modelData.enabled !== false

                    title: root.widgetName(modelData.widgetId)
                    iconName: root.widgetIcon(modelData.widgetId)
                    subtitle: removeButton.confirming ? I18n.tr("Confirm Delete") : ""
                    subtitleColor: Theme.error
                    body: SettingsSliderRow {
                        width: parent.width
                        visible: widgetRow.modelData.widgetId === "spacer"
                        height: visible ? implicitHeight : 0
                        text: I18n.tr("Size")
                        minimum: 0
                        maximum: 200
                        value: widgetRow.modelData.size ?? 20
                        onSliderValueChanged: value => SettingsData.updateDockWidget(dock.selectedDockId, widgetRow.modelData.id, {
                                size: value
                            })
                    }

                    Row {
                        spacing: Theme.spacingXS

                        DActionButton {
                            iconName: "settings"
                            visible: widgetRow.modelData.widgetId !== "appsDock" && !!BarWidgetCatalog.optionsFile(widgetRow.modelData.widgetId)
                            Accessible.name: I18n.tr("Settings")
                            onClicked: root.configureWidget(widgetRow.modelData)
                        }

                        DActionButton {
                            iconName: widgetRow.shown ? "visibility" : "visibility_off"
                            Accessible.name: widgetRow.shown ? I18n.tr("Hide") : I18n.tr("Show")
                            onClicked: {
                                if (widgetRow.slotOption) {
                                    dock.setOption(widgetRow.slotOption, !widgetRow.shown);
                                    return;
                                }
                                SettingsData.updateDockWidget(dock.selectedDockId, widgetRow.modelData.id, {
                                    enabled: !widgetRow.shown
                                });
                            }
                        }

                        SettingsDeleteButton {
                            id: removeButton
                            visible: !widgetRow.slotOption
                            onDeleteRequested: root.updateWidgets(dock.config.widgets.filter(item => item.id !== widgetRow.modelData.id))
                        }
                    }
                }
            }
        }

        Loader {
            width: parent.width
            active: root.appsEntry !== null
            visible: active
            sourceComponent: AppsDockOptions {
                page: root
            }
        }

        SettingsFabBar {
            shown: dock.hasConfig

            DFab {
                text: I18n.tr("Add widget")
                iconName: "add"
                onClicked: {
                    picker.widgets = root.widgetChoices.filter(widget => widget.id !== "appsDock" || !dock.config.widgets.some(item => item.widgetId === "appsDock"));
                    picker.show();
                }
            }
        }
    }

    WidgetSelectionPopup {
        id: picker

        parentModal: root.parentModal
        onWidgetSelected: widgetId => root.updateWidgets(dock.config.widgets.concat([
                {
                    id: dock.selectedDockId + "_" + Date.now(),
                    widgetId,
                    enabled: true
                }
            ]))
    }
}
