import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: widgetsTab

    property var parentModal: null
    property string selectedBarId: SettingsUiState.selectedBarId

    onSelectedBarIdChanged: {
        if (SettingsUiState.selectedBarId !== selectedBarId)
            SettingsUiState.selectedBarId = selectedBarId;
    }

    Connections {
        target: SettingsUiState

        function onSelectedBarIdChanged() {
            if (widgetsTab.selectedBarId !== SettingsUiState.selectedBarId)
                widgetsTab.selectedBarId = SettingsUiState.selectedBarId;
        }
    }

    property var selectedBarConfig: {
        selectedBarId;
        SettingsData.barConfigs;
        const index = SettingsData.barConfigs.findIndex(cfg => cfg.id === selectedBarId);
        return index !== -1 ? SettingsData.barConfigs[index] : SettingsData.barConfigs[0];
    }

    property bool selectedBarIsVertical: {
        selectedBarId;
        const pos = selectedBarConfig?.position ?? SettingsData.Position.Top;
        return pos === SettingsData.Position.Left || pos === SettingsData.Position.Right;
    }

    readonly property bool dankIslandOwnsSelectedBarCenter: {
        SettingsData.barConfigs;
        selectedBarId;
        return SettingsData.isIslandBarConfig(SettingsData.getBarConfig(selectedBarId));
    }

    readonly property bool islandSatellitesHidden: {
        SettingsData.barConfigs;
        selectedBarId;
        const bc = SettingsData.getBarConfig(selectedBarId);
        if (!SettingsData.isIslandBarConfig(bc))
            return false;
        return SettingsData.isDotBarConfig(bc) || !SettingsData.islandSetting(bc, "islandSatellitesEnabled");
    }

    property bool hasMultipleBars: SettingsData.barConfigs.length > 1
    property int pluginCatalogRevision: 0

    property string highlightedId: ""
    property string highlightedSection: ""

    property alias reorderGroup: dragGroup

    SettingsReorderGroup {
        id: dragGroup

        coordinateItem: widgetsTab
        onTransferred: (source, sourceIndex, target, targetIndex) => widgetsTab.moveWidget(source.groupKey, target.groupKey, source.model[sourceIndex].id, targetIndex, sourceIndex)
    }

    readonly property var widgetAvailability: {
        const dgopWarning = DgopService.dgopAvailable ? undefined : I18n.tr("Requires %1", "missing program").arg("dgop");
        return {
            "layout": {
                "enabled": CompositorService.isMango && MangoService.available,
                "warning": !CompositorService.isMango ? I18n.tr("Requires MangoWC compositor") : (!MangoService.available ? I18n.tr("Mango service not available") : undefined)
            },
            "cpuUsage": {
                "enabled": DgopService.dgopAvailable,
                "warning": dgopWarning
            },
            "memUsage": {
                "enabled": DgopService.dgopAvailable,
                "warning": dgopWarning
            },
            "diskUsage": {
                "enabled": DgopService.dgopAvailable,
                "warning": dgopWarning
            },
            "cpuTemp": {
                "enabled": DgopService.dgopAvailable,
                "warning": dgopWarning
            },
            "gpuTemp": {
                "enabled": DgopService.dgopAvailable,
                "warning": dgopWarning ?? I18n.tr("This widget prevents GPU power off states, which can significantly impact battery life on laptops. It is not recommended to use this on laptops with hybrid graphics.")
            },
            "network_speed_monitor": {
                "enabled": DgopService.dgopAvailable,
                "warning": dgopWarning
            },
            "systemUpdate": {
                "enabled": SystemUpdateService.sysupdateAvailable,
                "warning": SystemUpdateService.sysupdateAvailable ? undefined : I18n.tr("Requires DMS server with sysupdate capability")
            }
        };
    }

    property var baseWidgetDefinitions: {
        pluginCatalogRevision;
        var coreWidgets = BarWidgetCatalog.widgets.map(widget => Object.assign({
                "enabled": true
            }, widget, widgetsTab.widgetAvailability[widget.id] ?? {}));

        var allPluginVariants = PluginService.getAllPluginVariants();
        for (var i = 0; i < allPluginVariants.length; i++) {
            var variant = allPluginVariants[i];
            coreWidgets.push({
                "id": variant.fullId,
                "pluginId": variant.pluginId,
                "text": variant.name,
                "description": variant.description,
                "icon": variant.icon,
                "enabled": variant.loaded,
                "warning": !variant.loaded ? I18n.tr("Plugin is disabled - enable in Plugins settings to use") : undefined
            });
        }

        return coreWidgets;
    }

    focus: true
    Keys.onPressed: function (event) {
        var flat = flatList();
        if (flat.length === 0)
            return;
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            var focusedRow = focusedWidgetRow();
            if (focusedRow) {
                highlightedSection = focusedRow.section;
                highlightedId = focusedRow.id;
            }
            widgetsTab.forceActiveFocus();
            var dir = event.key === Qt.Key_Down ? 1 : -1;
            if (ctrl) {
                if (highlightedId !== "")
                    moveWithinSection(highlightedSection, highlightedId, dir);
            } else {
                var idx = -1;
                for (var i = 0; i < flat.length; i++) {
                    if (flat[i].section === highlightedSection && flat[i].id === highlightedId) {
                        idx = i;
                        break;
                    }
                }
                if (idx < 0) {
                    var f = dir > 0 ? flat[0] : flat[flat.length - 1];
                    highlightedSection = f.section;
                    highlightedId = f.id;
                } else {
                    idx = Math.max(0, Math.min(flat.length - 1, idx + dir));
                    highlightedSection = flat[idx].section;
                    highlightedId = flat[idx].id;
                }
            }
            event.accepted = true;
        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && ctrl) {
            if (highlightedId !== "")
                moveAcrossSections(highlightedSection, highlightedId, event.key === Qt.Key_Right ? 1 : -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            if (highlightedId !== "") {
                toggleHighlighted();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (highlightedId !== "") {
                configureHighlighted();
                event.accepted = true;
            }
        }
    }

    Connections {
        target: PluginService

        function onPluginDataChanged() {
            widgetsTab.pluginCatalogRevision++;
        }

        function onPluginListUpdated() {
            widgetsTab.pluginCatalogRevision++;
        }

        function onPluginLoaded() {
            widgetsTab.pluginCatalogRevision++;
        }

        function onPluginStateChanged() {
            widgetsTab.pluginCatalogRevision++;
        }

        function onPluginUnloaded() {
            widgetsTab.pluginCatalogRevision++;
        }
    }

    property var defaultLeftWidgets: [
        {
            "id": "launcherButton",
            "enabled": true
        },
        {
            "id": "workspaceSwitcher",
            "enabled": true
        },
        {
            "id": "focusedWindow",
            "enabled": true
        }
    ]
    property var defaultCenterWidgets: [
        {
            "id": "music",
            "enabled": true
        },
        {
            "id": "clock",
            "enabled": true
        },
        {
            "id": "weather",
            "enabled": true
        }
    ]
    property var defaultRightWidgets: [
        {
            "id": "systemTray",
            "enabled": true
        },
        {
            "id": "clipboard",
            "enabled": true
        },
        {
            "id": "notificationButton",
            "enabled": true
        },
        {
            "id": "battery",
            "enabled": true
        },
        {
            "id": "controlCenterButton",
            "enabled": true
        }
    ]

    function getWidgetsForSection(sectionId) {
        switch (sectionId) {
        case "left":
            return selectedBarConfig?.leftWidgets || [];
        case "center":
            return selectedBarConfig?.centerWidgets || [];
        case "right":
            return selectedBarConfig?.rightWidgets || [];
        default:
            return [];
        }
    }

    function setWidgetsForSection(sectionId, widgets) {
        if (sectionId === "center" && dankIslandOwnsSelectedBarCenter)
            return;
        switch (sectionId) {
        case "left":
            SettingsData.updateBarConfig(selectedBarId, {
                leftWidgets: widgets
            });
            break;
        case "center":
            SettingsData.updateBarConfig(selectedBarId, {
                centerWidgets: widgets
            });
            break;
        case "right":
            SettingsData.updateBarConfig(selectedBarId, {
                rightWidgets: widgets
            });
            break;
        }
    }

    function getWidgetsForPopup() {
        const config = SettingsData.getBarConfig(selectedBarId);
        return baseWidgetDefinitions.filter(widget => {
            if (widget.warning && widget.warning.includes("Plugin is disabled"))
                return false;
            if (widget.enabled === false)
                return false;
            return !(widget.single && SettingsData.barWidgetEntry(config, widget.id));
        }).map(widget => {
            if (widget.id !== "island")
                return widget;
            if (SettingsData.isIslandBarConfig(config))
                return Object.assign({}, widget, {
                    "disabled": true,
                    "description": I18n.tr("This bar is the Island", "bar widget picker: island widget unavailable on an island-layout bar")
                });
            if (!SettingsData.islandWidgetBlocked(config))
                return widget;
            return Object.assign({}, widget, {
                "disabled": true,
                "description": I18n.tr("An Island bar already covers a display this bar is on", "bar widget picker: island widget blocked by an island-layout bar sharing a display")
            });
        });
    }

    function addWidgetToSection(widgetId, targetSection) {
        if (targetSection === "center" && dankIslandOwnsSelectedBarCenter)
            return;
        SettingsData.addBarWidget(selectedBarId, targetSection, widgetId);
    }

    function removeWidgetFromSection(sectionId, widgetIndex) {
        var widgets = getWidgetsForSection(sectionId).slice();
        if (widgetIndex >= 0 && widgetIndex < widgets.length)
            widgets.splice(widgetIndex, 1);
        setWidgetsForSection(sectionId, widgets);
    }

    function cloneWidgetData(widget) {
        if (typeof widget === "string")
            return {
                "id": widget,
                "enabled": true
            };
        return Object.assign({}, widget);
    }

    function handleItemEnabledChanged(sectionId, itemId, enabled) {
        var widgets = getWidgetsForSection(sectionId).slice();
        for (var i = 0; i < widgets.length; i++) {
            var widget = widgets[i];
            var widgetId = typeof widget === "string" ? widget : widget.id;
            if (widgetId !== itemId)
                continue;
            var newWidget = cloneWidgetData(widget);
            newWidget.enabled = enabled;
            widgets[i] = newWidget;
            break;
        }
        setWidgetsForSection(sectionId, widgets);
    }

    function barKey(sectionId) {
        return sectionId === "left" ? "leftWidgets" : sectionId === "center" ? "centerWidgets" : "rightWidgets";
    }

    function sectionItem(sectionId) {
        return sectionId === "left" ? leftSection : sectionId === "center" ? centerSection : sectionId === "right" ? rightSection : null;
    }

    function reorderSection(sectionId, orderedIds) {
        var remaining = getWidgetsForSection(sectionId).slice();
        var reordered = [];
        orderedIds.forEach(id => {
            var idx = remaining.findIndex(w => (typeof w === "string" ? w : w.id) === id);
            if (idx < 0)
                return;
            reordered.push(remaining.splice(idx, 1)[0]);
        });
        setWidgetsForSection(sectionId, reordered.concat(remaining));
    }

    function moveWidget(fromSection, toSection, movedId, toIndex, sourceIndex = -1) {
        if (dankIslandOwnsSelectedBarCenter && (fromSection === "center" || toSection === "center"))
            return;
        if (fromSection === toSection) {
            var arr = getWidgetsForSection(fromSection).slice();
            var fi = arr.findIndex(w => (typeof w === "string" ? w : w.id) === movedId);
            if (fi < 0)
                return;
            var m = arr.splice(fi, 1)[0];
            arr.splice(Math.max(0, Math.min(toIndex, arr.length)), 0, m);
            setWidgetsForSection(fromSection, arr);
            return;
        }
        var src = getWidgetsForSection(fromSection).slice();
        var fromIdx = sourceIndex >= 0 ? sourceIndex : src.findIndex(w => (typeof w === "string" ? w : w.id) === movedId);
        if (fromIdx < 0 || fromIdx >= src.length)
            return;
        var moved = src.splice(fromIdx, 1)[0];
        var dst = getWidgetsForSection(toSection).slice();
        dst.splice(Math.max(0, Math.min(toIndex, dst.length)), 0, moved);
        var updates = {};
        updates[barKey(fromSection)] = src;
        updates[barKey(toSection)] = dst;
        SettingsData.updateBarConfig(selectedBarId, updates);
    }

    // A row reached with Tab has focus but no cursor, so the cursor starts from it
    function focusedWidgetRow() {
        for (var item = Window.activeFocusItem; item; item = item.parent) {
            if (item.reorderList === undefined || !item.modelData?.id)
                continue;
            for (var section = item.parent; section; section = section.parent) {
                if (section.sectionId !== undefined)
                    return {
                        "section": section.sectionId,
                        "id": item.modelData.id
                    };
            }
            return null;
        }
        return null;
    }

    function flatList() {
        var out = [];
        ["left", "center", "right"].forEach(s => {
            getWidgetsForSection(s).forEach(w => {
                out.push({
                    "section": s,
                    "id": (typeof w === "string" ? w : w.id)
                });
            });
        });
        return out;
    }

    function moveWithinSection(sectionId, id, delta) {
        var ids = getWidgetsForSection(sectionId).map(w => typeof w === "string" ? w : w.id);
        var pos = ids.indexOf(id);
        var next = pos + delta;
        if (pos < 0 || next < 0 || next >= ids.length)
            return;
        ids.splice(pos, 1);
        ids.splice(next, 0, id);
        reorderSection(sectionId, ids);
    }

    function moveAcrossSections(sectionId, id, delta) {
        var order = dankIslandOwnsSelectedBarCenter ? ["left", "right"] : ["left", "center", "right"];
        var si = order.indexOf(sectionId);
        var ti = si + delta;
        if (si < 0 || ti < 0 || ti >= order.length)
            return;
        var to = order[ti];
        moveWidget(sectionId, to, id, getWidgetsForSection(to).length);
        highlightedSection = to;
    }

    function toggleHighlighted() {
        if (highlightedId === "" || highlightedSection === "")
            return;
        var w = getWidgetsForSection(highlightedSection).find(x => (typeof x === "string" ? x : x.id) === highlightedId);
        if (w === undefined)
            return;
        var en = (typeof w === "string") ? true : (w.enabled !== false);
        handleItemEnabledChanged(highlightedSection, highlightedId, !en);
    }

    function configureHighlighted() {
        const index = getWidgetsForSection(highlightedSection).findIndex(x => (typeof x === "string" ? x : x.id) === highlightedId);
        if (index < 0)
            return;
        if (!BarWidgetCatalog.configurable(getItemsForSection(highlightedSection)[index]))
            return;
        configureWidget(highlightedSection, index);
    }

    function handleSpacerSizeChanged(sectionId, widgetIndex, newSize) {
        var widgets = getWidgetsForSection(sectionId).slice();
        if (widgetIndex < 0 || widgetIndex >= widgets.length)
            return;
        var widget = widgets[widgetIndex];
        var widgetId = typeof widget === "string" ? widget : widget.id;
        if (widgetId !== "spacer")
            return;
        var newWidget = cloneWidgetData(widget);
        newWidget.size = newSize;
        widgets[widgetIndex] = newWidget;
        setWidgetsForSection(sectionId, widgets);
    }

    function configureWidget(sectionId, widgetIndex) {
        SettingsUiState.selectedDockId = "";
        const item = getItemsForSection(sectionId)[widgetIndex];
        if (!item)
            return;
        if (item.pluginId) {
            parentModal?.navigateTo(SettingsTabs.pluginPrefix + item.pluginId);
            return;
        }
        SettingsUiState.selectedWidgetSection = sectionId;
        SettingsUiState.selectedWidgetIndex = widgetIndex;
        SettingsUiState.selectedWidgetTitle = item.text;
        SettingsUiState.selectedWidgetDescription = item.description ?? "";
        SettingsUiState.selectedWidgetIcon = item.icon ?? "";
        parentModal?.navigateTo("bar_widget");
    }

    function getItemsForSection(sectionId) {
        var widgets = [];
        var widgetData = getWidgetsForSection(sectionId);
        widgetData.forEach(widget => {
            var isString = typeof widget === "string";
            var widgetId = isString ? widget : widget.id;
            var widgetDef = baseWidgetDefinitions.find(w => w.id === widgetId);
            if (!widgetDef) {
                // Skipping entries would desync row indices from the config array (issue #2844)
                widgetDef = {
                    "id": widgetId,
                    "text": widgetId || I18n.tr("Unknown"),
                    "description": "",
                    "icon": "extension",
                    "warning": I18n.tr("Unavailable")
                };
            }

            var item = Object.assign({}, isString ? {} : widget, widgetDef);
            item.enabled = isString ? true : widget.enabled !== false;
            widgets.push(item);
        });
        return widgets;
    }

    Component.onCompleted: {
        const leftWidgets = selectedBarConfig?.leftWidgets;
        const centerWidgets = selectedBarConfig?.centerWidgets;
        const rightWidgets = selectedBarConfig?.rightWidgets;

        if (!leftWidgets)
            setWidgetsForSection("left", defaultLeftWidgets);
        if (!centerWidgets)
            setWidgetsForSection("center", defaultCenterWidgets);
        if (!rightWidgets)
            setWidgetsForSection("right", defaultRightWidgets);

        const sections = ["left", "center", "right"];
        sections.forEach(sectionId => {
            var widgets = getWidgetsForSection(sectionId).slice();
            var updated = false;
            for (var i = 0; i < widgets.length; i++) {
                var widget = widgets[i];
                if (typeof widget === "object" && widget.id === "spacer" && !widget.size) {
                    widgets[i] = Object.assign({}, widget, {
                        "size": 20
                    });
                    updated = true;
                }
            }
            if (updated)
                setWidgetsForSection(sectionId, widgets);
        });
    }

    LazyLoader {
        id: widgetSelectionPopupLoader
        active: false

        WidgetSelectionPopup {
            id: widgetSelectionPopupItem
            parentModal: widgetsTab.parentModal
            onWidgetSelected: (widgetId, targetSection) => {
                widgetsTab.addWidgetToSection(widgetId, targetSection);
            }
        }
    }

    function showWidgetSelectionPopup(sectionId) {
        widgetSelectionPopupLoader.active = true;
        if (!widgetSelectionPopupLoader.item)
            return;
        widgetSelectionPopupLoader.item.targetSection = sectionId;
        widgetSelectionPopupLoader.item.widgets = widgetsTab.getWidgetsForPopup();
        widgetSelectionPopupLoader.item.show();
    }

    SettingsPage {
        id: mainColumn

        TapHandler {
            onTapped: widgetsTab.forceActiveFocus()
        }

        SettingsCard {
            iconName: "toolbar"
            title: I18n.tr("Bar")
            visible: hasMultipleBars

            SettingsRow {
                body: DButtonGroup {
                    id: barSelectorGroup
                    arrowKeysSelect: false
                    width: parent.width
                    model: SettingsData.barConfigs.map(cfg => cfg.name || ("Bar " + (SettingsData.barConfigs.indexOf(cfg) + 1)))
                    currentIndex: {
                        const idx = SettingsData.barConfigs.findIndex(cfg => cfg.id === selectedBarId);
                        return idx >= 0 ? idx : 0;
                    }
                    checkEnabled: false
                    onSelectionChanged: (index, selected) => {
                        if (!selected)
                            return;
                        if (index >= 0 && index < SettingsData.barConfigs.length)
                            selectedBarId = SettingsData.barConfigs[index].id;
                    }
                }
            }
        }

        SettingsCard {
            iconName: "widgets"
            title: I18n.tr("Sections", "bar widget settings heading for left, center, right sections")

            headerActions: DButton {
                text: I18n.tr("Reset")
                iconName: "refresh"
                buttonHeight: Theme.buttonHeightXS
                backgroundColor: Theme.secondaryContainer
                textColor: Theme.onSecondaryContainer
                onClicked: {
                    setWidgetsForSection("left", defaultLeftWidgets);
                    setWidgetsForSection("center", defaultCenterWidgets);
                    setWidgetsForSection("right", defaultRightWidgets);
                }
            }

            SettingsRow {
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Drag the handle to reorder. Tap a widget for its settings, use the switch to hide it without changing spacing, or X to remove it.")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }
            }

            SettingsRow {
                iconName: "info"
                iconColor: Theme.surfaceVariantText
                visible: widgetsTab.islandSatellitesHidden
                title: I18n.tr("Satellites", "island settings: satellite widgets card title")
                subtitle: I18n.tr("Not shown on this bar, so its section widgets stay hidden", "widgets settings: island satellites are not rendered on this bar")
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingL

            WidgetsTabSection {
                id: leftSection
                width: parent.width
                title: selectedBarIsVertical ? I18n.tr("Top section") : I18n.tr("Left section")
                sectionId: "left"
                barId: widgetsTab.selectedBarId
                allWidgets: widgetsTab.baseWidgetDefinitions
                items: widgetsTab.getItemsForSection("left")
                onItemEnabledChanged: (sectionId, itemId, enabled) => {
                    widgetsTab.handleItemEnabledChanged(sectionId, itemId, enabled);
                }
                highlightedId: widgetsTab.highlightedId
                highlightedSection: widgetsTab.highlightedSection
                onItemOrderChanged: (sectionId, indices) => {
                    const items = widgetsTab.getWidgetsForSection(sectionId);
                    widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                }
                reorderGroup: dragGroup
                onDragStarted: {
                    widgetsTab.highlightedSection = "";
                    widgetsTab.highlightedId = "";
                }
                onAddWidget: sectionId => {
                    showWidgetSelectionPopup(sectionId);
                }
                onRemoveWidget: (sectionId, index) => {
                    widgetsTab.removeWidgetFromSection(sectionId, index);
                }
                onSpacerSizeChanged: (sectionId, index, size) => {
                    widgetsTab.handleSpacerSizeChanged(sectionId, index, size);
                }
                onConfigureWidget: (sectionId, index) => widgetsTab.configureWidget(sectionId, index)
            }

            SettingsCard {
                width: parent.width
                iconName: "view_in_ar"
                title: I18n.tr("Home compact", "island settings: home face card title")
                settingKey: "islandHomeLayout"
                tags: ["island", "home", "compact", "layout", "groups", "order"]
                visible: widgetsTab.dankIslandOwnsSelectedBarCenter

                SettingsRow {
                    iconName: "info"
                    iconColor: Theme.surfaceVariantText
                    title: selectedBarIsVertical ? I18n.tr("Middle section", "widgets settings: bar section replaced by the island") : I18n.tr("Center section", "widgets settings: bar section replaced by the island")
                    subtitle: I18n.tr("The Island takes its place on this bar", "widgets settings: the island replaces the bar's center section")
                }

                Loader {
                    width: parent.width
                    readonly property bool isSettingsRow: true
                    readonly property bool transparentSlot: true
                    height: item?.implicitHeight ?? 0
                    active: widgetsTab.dankIslandOwnsSelectedBarCenter
                    sourceComponent: IslandHomeLayoutEditor {
                        settingKey: ""
                        barId: widgetsTab.selectedBarId
                    }
                }

                SettingsRow {
                    body: Flow {
                        width: parent.width
                        spacing: Theme.spacingS

                        DButton {
                            text: I18n.tr("Launcher", "island settings: button to launcher tab")
                            iconName: "grid_view"
                            onClicked: {
                                if (!widgetsTab.parentModal)
                                    return;
                                SettingsSearchService.navigateToSection("launcherStyle");
                                widgetsTab.parentModal.navigateTo("launcher");
                            }
                        }

                        DButton {
                            text: I18n.tr("Time & weather", "island settings: button to weather tab")
                            iconName: "cloud"
                            onClicked: {
                                if (!widgetsTab.parentModal)
                                    return;
                                SettingsSearchService.navigateToSection("weatherEnabled");
                                widgetsTab.parentModal.navigateTo("time_weather");
                            }
                        }
                    }
                }
            }

            WidgetsTabSection {
                id: centerSection
                width: parent.width
                visible: !widgetsTab.dankIslandOwnsSelectedBarCenter
                title: selectedBarIsVertical ? I18n.tr("Middle section") : I18n.tr("Center section")
                sectionId: "center"
                barId: widgetsTab.selectedBarId
                allWidgets: widgetsTab.baseWidgetDefinitions
                items: widgetsTab.getItemsForSection("center")
                onItemEnabledChanged: (sectionId, itemId, enabled) => {
                    widgetsTab.handleItemEnabledChanged(sectionId, itemId, enabled);
                }
                highlightedId: widgetsTab.highlightedId
                highlightedSection: widgetsTab.highlightedSection
                onItemOrderChanged: (sectionId, indices) => {
                    const items = widgetsTab.getWidgetsForSection(sectionId);
                    widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                }
                reorderGroup: dragGroup
                onDragStarted: {
                    widgetsTab.highlightedSection = "";
                    widgetsTab.highlightedId = "";
                }
                onAddWidget: sectionId => {
                    showWidgetSelectionPopup(sectionId);
                }
                onRemoveWidget: (sectionId, index) => {
                    widgetsTab.removeWidgetFromSection(sectionId, index);
                }
                onSpacerSizeChanged: (sectionId, index, size) => {
                    widgetsTab.handleSpacerSizeChanged(sectionId, index, size);
                }
                onConfigureWidget: (sectionId, index) => widgetsTab.configureWidget(sectionId, index)
            }

            WidgetsTabSection {
                id: rightSection
                width: parent.width
                title: selectedBarIsVertical ? I18n.tr("Bottom section") : I18n.tr("Right section")
                sectionId: "right"
                barId: widgetsTab.selectedBarId
                allWidgets: widgetsTab.baseWidgetDefinitions
                items: widgetsTab.getItemsForSection("right")
                onItemEnabledChanged: (sectionId, itemId, enabled) => {
                    widgetsTab.handleItemEnabledChanged(sectionId, itemId, enabled);
                }
                highlightedId: widgetsTab.highlightedId
                highlightedSection: widgetsTab.highlightedSection
                onItemOrderChanged: (sectionId, indices) => {
                    const items = widgetsTab.getWidgetsForSection(sectionId);
                    widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                }
                reorderGroup: dragGroup
                onDragStarted: {
                    widgetsTab.highlightedSection = "";
                    widgetsTab.highlightedId = "";
                }
                onAddWidget: sectionId => {
                    showWidgetSelectionPopup(sectionId);
                }
                onRemoveWidget: (sectionId, index) => {
                    widgetsTab.removeWidgetFromSection(sectionId, index);
                }
                onSpacerSizeChanged: (sectionId, index, size) => {
                    widgetsTab.handleSpacerSizeChanged(sectionId, index, size);
                }
                onConfigureWidget: (sectionId, index) => widgetsTab.configureWidget(sectionId, index)
            }
        }
    }

    SettingsReorderPreview {
        group: dragGroup
    }
}
