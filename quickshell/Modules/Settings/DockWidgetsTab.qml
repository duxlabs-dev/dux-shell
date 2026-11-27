pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
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

    function itemTitle(item) {
        return BarWidgetCatalog.entryInfo(item)?.text ?? widgetName(item.widgetId);
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

    property var expandedSpacers: ({})
    readonly property bool hasFillSpacer: dock.config?.mode === "taskbar" && (dock.config?.widgets ?? []).some(DockConfig.isFillSpacer)
    readonly property var centerGroup: hasFillSpacer ? DockConfig.centerGroup(orderedWidgets.map(item => item.id), dock.config.widgets) : []
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
        SettingsUiState.selectedWidgetTitle = root.itemTitle(item);
        SettingsUiState.selectedWidgetDescription = BarWidgetCatalog.entryInfo(item)?.description ?? "";
        SettingsUiState.selectedWidgetIcon = root.widgetIcon(item.widgetId);
        root.parentModal?.navigateTo("bar_widget");
    }

    SettingsPage {
        SettingsDeferred {
            when: dock.hasConfig

            SettingsCard {
                width: parent.width
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
                        readonly property var info: BarWidgetCatalog.entryInfo(modelData)
                        readonly property bool shown: slotOption ? dock.config[slotOption] === true : modelData.enabled !== false

                        title: info?.text ?? root.widgetName(modelData.widgetId)
                        iconName: root.widgetIcon(modelData.widgetId)
                        subtitle: removeButton.confirming ? I18n.tr("Confirm Delete", "delete button confirmation text") : (info?.description ?? "")
                        subtitleColor: removeButton.confirming ? Theme.error : Theme.surfaceVariantText
                        readonly property bool expanded: root.expandedSpacers[modelData.id] === true
                        clickable: modelData.widgetId === "spacer"
                        Accessible.checkable: clickable
                        Accessible.checked: expanded
                        onClicked: root.expandedSpacers = Object.assign({}, root.expandedSpacers, {
                            [modelData.id]: !expanded
                        })

                        body: Column {
                            width: parent.width
                            visible: widgetRow.modelData.widgetId === "spacer" && widgetRow.expanded
                            height: visible ? implicitHeight : 0

                            SettingsToggleRow {
                                width: parent.width
                                visible: dock.config.mode === "taskbar"
                                text: I18n.tr("Fill", "dock spacer option: take up all free space in the taskbar")
                                checked: widgetRow.modelData.fill === true
                                onToggled: checked => SettingsData.updateDockWidget(dock.selectedDockId, widgetRow.modelData.id, checked ? {
                                        fill: true,
                                        center: false
                                    } : {
                                        fill: false
                                    })
                            }

                            SettingsSliderRow {
                                width: parent.width
                                text: widgetRow.modelData.fill === true && dock.config.mode === "taskbar" ? I18n.tr("Minimum size", "dock spacer option: least space a filling spacer keeps") : I18n.tr("Size")
                                minimum: 0
                                maximum: 1000
                                value: widgetRow.modelData.size ?? 20
                                onSliderDragFinished: value => SettingsData.updateDockWidget(dock.selectedDockId, widgetRow.modelData.id, {
                                        size: value
                                    })
                            }
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
                                readonly property bool centered: root.centerGroup.includes(widgetRow.modelData.id)
                                iconName: [SettingsData.Position.Left, SettingsData.Position.Right].includes(dock.config.position) ? "align_vertical_center" : "align_horizontal_center"
                                visible: root.hasFillSpacer && !DockConfig.isFillSpacer(widgetRow.modelData)
                                iconColor: centered ? Theme.primary : Theme.surfaceVariantText
                                tooltipText: I18n.tr("Center", "dock widget option: keep this widget's group in the middle of the taskbar")
                                Accessible.name: tooltipText
                                Accessible.checkable: true
                                Accessible.checked: centered
                                onClicked: root.updateWidgets(dock.config.widgets.map(item => {
                                    if (item.id === widgetRow.modelData.id)
                                        return Object.assign({}, item, {
                                            center: !centered
                                        });
                                    if (item.center !== true)
                                        return item;
                                    const cleared = Object.assign({}, item);
                                    delete cleared.center;
                                    return cleared;
                                }))
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

                            DIcon {
                                name: widgetRow.expanded ? "expand_less" : "expand_more"
                                size: Theme.iconSize
                                color: Theme.onSurfaceVariant
                                visible: widgetRow.modelData.widgetId === "spacer"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }

        SettingsDeferred {
            when: root.appsEntry !== null

            AppsDockOptions {
                page: root
            }
        }

        SettingsFabBar {
            shown: dock.hasConfig

            DFab {
                text: I18n.tr("Add widget")
                iconName: "add"
                onClicked: {
                    pickerLoader.active = true;
                    pickerLoader.item.widgets = root.widgetChoices.filter(widget => widget.id !== "appsDock" || !dock.config.widgets.some(item => item.widgetId === "appsDock"));
                    pickerLoader.item.show();
                }
            }
        }
    }

    LazyLoader {
        id: pickerLoader
        active: false

        WidgetSelectionPopup {
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
}
