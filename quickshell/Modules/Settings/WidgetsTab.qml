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

    // The cursor is a row position, so any rebuild of the lists drops it unless the keyboard caused it.
    property bool keepHighlight: false
    function keepingHighlight(write) {
        keepHighlight = true;
        try {
            write();
        } finally {
            keepHighlight = false;
        }
    }
    onSelectedBarConfigChanged: {
        if (keepHighlight)
            return;
        highlightedSection = "";
        highlightedIndex = -1;
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

    // A dot only has room for the island's own groups.
    readonly property bool islandTakesBarWidgets: dankIslandOwnsSelectedBarCenter && !SettingsData.isDotBarConfig(selectedBarConfig)
    // Bar widgets the island already rebuilds as its own groups.
    readonly property var islandActivityWidgetIds: ["music", "clock", "workspaceSwitcher", "weather", "battery", "notificationButton", "privacyIndicator", "keyboard_layout_name", "systemTray", "controlCenterButton"]

    readonly property bool islandSatellitesHidden: {
        SettingsData.barConfigs;
        selectedBarId;
        const bc = SettingsData.getBarConfig(selectedBarId);
        if (!SettingsData.isIslandBarConfig(bc))
            return false;
        return SettingsData.isDotBarConfig(bc) || !SettingsData.islandSetting(bc, "islandSatellitesEnabled");
    }

    readonly property var selectableBars: SettingsData.barConfigs.filter(cfg => cfg.enabled || !SettingsData.isDotBarConfig(cfg))
    property bool hasMultipleBars: selectableBars.length > 1
    property int pluginCatalogRevision: 0

    property int highlightedIndex: -1
    property string highlightedSection: ""

    property alias reorderGroup: dragGroup

    SettingsReorderGroup {
        id: dragGroup

        coordinateItem: widgetsTab
        onTransferred: (source, sourceIndex, target, targetIndex) => widgetsTab.moveWidget(source.groupKey, target.groupKey, sourceIndex, targetIndex)
    }

    property var baseWidgetDefinitions: {
        pluginCatalogRevision;
        return BarWidgetCatalog.definitions();
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
                highlightedIndex = focusedRow.index;
            }
            widgetsTab.forceActiveFocus();
            var dir = event.key === Qt.Key_Down ? 1 : -1;
            if (ctrl) {
                if (highlightedIndex >= 0)
                    moveWithinSection(highlightedSection, highlightedIndex, dir);
            } else {
                var idx = -1;
                for (var i = 0; i < flat.length; i++) {
                    if (flat[i].section === highlightedSection && flat[i].index === highlightedIndex) {
                        idx = i;
                        break;
                    }
                }
                if (idx < 0) {
                    var f = dir > 0 ? flat[0] : flat[flat.length - 1];
                    highlightedSection = f.section;
                    highlightedIndex = f.index;
                } else {
                    idx = Math.max(0, Math.min(flat.length - 1, idx + dir));
                    highlightedSection = flat[idx].section;
                    highlightedIndex = flat[idx].index;
                }
            }
            event.accepted = true;
        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) && ctrl) {
            if (highlightedIndex >= 0)
                moveAcrossSections(highlightedSection, highlightedIndex, event.key === Qt.Key_Right ? 1 : -1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Space) {
            if (highlightedIndex >= 0) {
                toggleHighlighted();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (highlightedIndex >= 0) {
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
        case "island":
            return SettingsData.islandWidgetEntries(selectedBarConfig);
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
        case "island":
            SettingsData.setIslandWidgetEntries(selectedBarId, widgets);
            break;
        }
    }

    function getIslandWidgetsForPopup() {
        const present = SettingsData.islandWidgetEntries(selectedBarConfig).map(entry => entry.id);
        const groups = BarWidgetCatalog.islandGroups.filter(group => !present.includes(group.id)).map(group => Object.assign({
                "category": I18n.tr("Island activities", "island widgets settings: category of widgets rebuilt for the island")
            }, group));
        if (!islandTakesBarWidgets)
            return groups;
        const barWidgets = baseWidgetDefinitions.filter(widget => {
            if (widget.enabled === false || widget.id === "island" || islandActivityWidgetIds.includes(widget.id))
                return false;
            return !(widget.single && present.includes(widget.id));
        }).map(widget => Object.assign({
                "category": I18n.tr("Bar widgets")
            }, widget));
        return groups.concat(barWidgets);
    }

    function getWidgetsForPopup(sectionId) {
        if (sectionId === "island")
            return getIslandWidgetsForPopup();
        return BarWidgetCatalog.addable(SettingsData.getBarConfig(selectedBarId), baseWidgetDefinitions);
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

    function handleItemEnabledChanged(sectionId, index, enabled) {
        var widgets = getWidgetsForSection(sectionId).slice();
        if (index < 0 || index >= widgets.length)
            return;
        var newWidget = cloneWidgetData(widgets[index]);
        newWidget.enabled = enabled;
        widgets[index] = newWidget;
        setWidgetsForSection(sectionId, widgets);
    }

    function barKey(sectionId) {
        return sectionId === "left" ? "leftWidgets" : sectionId === "center" ? "centerWidgets" : "rightWidgets";
    }

    function moveWidget(fromSection, toSection, sourceIndex, toIndex) {
        if (dankIslandOwnsSelectedBarCenter && (fromSection === "center" || toSection === "center"))
            return;
        var src = getWidgetsForSection(fromSection).slice();
        if (sourceIndex < 0 || sourceIndex >= src.length)
            return;
        var moved = src.splice(sourceIndex, 1)[0];
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
                        "index": item.index
                    };
            }
            return null;
        }
        return null;
    }

    function flatList() {
        var out = [];
        const sections = dankIslandOwnsSelectedBarCenter ? ["left", "island", "right"] : ["left", "center", "right"];
        sections.forEach(s => {
            getWidgetsForSection(s).forEach((w, i) => {
                out.push({
                    "section": s,
                    "index": i
                });
            });
        });
        return out;
    }

    function moveWithinSection(sectionId, index, delta) {
        var widgets = getWidgetsForSection(sectionId).slice();
        var next = index + delta;
        if (index < 0 || next < 0 || next >= widgets.length)
            return;
        widgets.splice(next, 0, widgets.splice(index, 1)[0]);
        keepingHighlight(() => setWidgetsForSection(sectionId, widgets));
        highlightedIndex = next;
    }

    function moveAcrossSections(sectionId, index, delta) {
        var order = dankIslandOwnsSelectedBarCenter ? ["left", "right"] : ["left", "center", "right"];
        var si = order.indexOf(sectionId);
        var ti = si + delta;
        if (si < 0 || ti < 0 || ti >= order.length)
            return;
        var to = order[ti];
        var toLength = getWidgetsForSection(to).length;
        keepingHighlight(() => moveWidget(sectionId, to, index, toLength));
        highlightedSection = to;
        highlightedIndex = toLength;
    }

    function toggleHighlighted() {
        if (highlightedIndex < 0 || highlightedSection === "")
            return;
        var w = getWidgetsForSection(highlightedSection)[highlightedIndex];
        if (w === undefined || BarWidgetCatalog.islandGroup(typeof w === "string" ? w : w.id)?.locked)
            return;
        keepingHighlight(() => handleItemEnabledChanged(highlightedSection, highlightedIndex, !(typeof w === "string" ? true : w.enabled !== false)));
    }

    function configureHighlighted() {
        if (highlightedIndex >= getWidgetsForSection(highlightedSection).length)
            return;
        if (!BarWidgetCatalog.configurable(getItemsForSection(highlightedSection)[highlightedIndex]))
            return;
        configureWidget(highlightedSection, highlightedIndex);
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
        if (item.islandGroup) {
            if (!item.settings || !parentModal)
                return;
            SettingsSearchService.navigateToSection(item.settings.section);
            parentModal.navigateTo(item.settings.tab);
            return;
        }
        SettingsUiState.selectedWidgetSection = sectionId;
        SettingsUiState.selectedWidgetIndex = widgetIndex;
        const info = BarWidgetCatalog.displayInfo(item);
        SettingsUiState.selectedWidgetTitle = info.text;
        SettingsUiState.selectedWidgetDescription = info.description ?? "";
        SettingsUiState.selectedWidgetIcon = item.icon ?? "";
        parentModal?.navigateTo("bar_widget");
    }

    // A dot has no home face, so its groups have no settings to open.
    function islandGroupDefinition(id) {
        const definition = Object.assign({
            "islandGroup": true
        }, BarWidgetCatalog.islandGroup(id));
        if (SettingsData.isDotBarConfig(selectedBarConfig))
            delete definition.settings;
        return definition;
    }

    function getItemsForSection(sectionId) {
        var widgets = [];
        var widgetData = getWidgetsForSection(sectionId);
        widgetData.forEach(widget => {
            var isString = typeof widget === "string";
            var widgetId = isString ? widget : widget.id;
            var widgetDef = sectionId === "island" && SettingsData.isIslandHomeGroup(widgetId) ? islandGroupDefinition(widgetId) : baseWidgetDefinitions.find(w => w.id === widgetId);
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
        widgetSelectionPopupLoader.item.widgets = widgetsTab.getWidgetsForPopup(sectionId);
        widgetSelectionPopupLoader.item.show();
    }

    SettingsPage {
        id: mainColumn

        TapHandler {
            onTapped: widgetsTab.forceActiveFocus()
        }

        SettingsDeferred {
            when: hasMultipleBars

            SettingsCard {
                iconName: "toolbar"
                title: I18n.tr("Bar")

                SettingsRow {
                    body: DButtonGroup {
                        id: barSelectorGroup
                        arrowKeysSelect: false
                        width: parent.width
                        model: widgetsTab.selectableBars.map(cfg => cfg.name || ("Bar " + (SettingsData.barConfigs.indexOf(cfg) + 1)))
                        currentIndex: Math.max(0, widgetsTab.selectableBars.findIndex(cfg => cfg.id === widgetsTab.selectedBarId))
                        checkEnabled: false
                        onSelectionChanged: (index, selected) => {
                            if (!selected)
                                return;
                            const config = widgetsTab.selectableBars[index];
                            if (config)
                                widgetsTab.selectedBarId = config.id;
                        }
                    }
                }
            }
        }

        SettingsDeferred {
            SettingsCard {
                iconName: "widgets"
                title: I18n.tr("Sections", "bar widget settings heading for left, center, right sections")

                headerActions: DButton {
                    text: I18n.tr("Reset")
                    iconName: "refresh"
                    buttonHeight: Theme.buttonHeightXS
                    variant: "tonal"
                    onClicked: {
                        setWidgetsForSection("left", defaultLeftWidgets);
                        setWidgetsForSection("center", defaultCenterWidgets);
                        setWidgetsForSection("right", defaultRightWidgets);
                        if (widgetsTab.dankIslandOwnsSelectedBarCenter)
                            setWidgetsForSection("island", SettingsData.islandHomeLayoutDefault());
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
                    iconName: "view_in_ar"
                    iconColor: Theme.surfaceVariantText
                    visible: widgetsTab.dankIslandOwnsSelectedBarCenter
                    title: I18n.tr("The Island takes its place on this bar", "widgets settings: the island replaces the bar's center section")
                    subtitle: I18n.tr("Island widgets above the clock sit before it, the rest after it", "widgets settings: island widget order hint")
                }

                SettingsRow {
                    iconName: "info"
                    iconColor: Theme.surfaceVariantText
                    visible: widgetsTab.islandSatellitesHidden
                    title: I18n.tr("Satellites", "island settings: satellite widgets card title")
                    subtitle: I18n.tr("Not shown on this bar, so its section widgets stay hidden", "widgets settings: island satellites are not rendered on this bar")
                }
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingL

            SettingsDeferred {
                WidgetsTabSection {
                    width: parent.width
                    title: selectedBarIsVertical ? I18n.tr("Top section") : I18n.tr("Left section")
                    sectionId: "left"
                    barId: widgetsTab.selectedBarId
                    allWidgets: widgetsTab.baseWidgetDefinitions
                    items: widgetsTab.getItemsForSection("left")
                    onItemEnabledChanged: (sectionId, index, enabled) => {
                        widgetsTab.handleItemEnabledChanged(sectionId, index, enabled);
                    }
                    highlightedIndex: widgetsTab.highlightedIndex
                    highlightedSection: widgetsTab.highlightedSection
                    onItemOrderChanged: (sectionId, indices) => {
                        const items = widgetsTab.getWidgetsForSection(sectionId);
                        widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                    }
                    reorderGroup: dragGroup
                    onDragStarted: {
                        widgetsTab.highlightedSection = "";
                        widgetsTab.highlightedIndex = -1;
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

            SettingsDeferred {
                when: widgetsTab.dankIslandOwnsSelectedBarCenter

                WidgetsTabSection {
                    id: islandSection
                    width: parent.width
                    title: I18n.tr("Island widgets", "bar widget settings: widgets in the collapsed island")
                    sectionId: "island"
                    overflowAvailable: false
                    barId: widgetsTab.selectedBarId
                    allWidgets: widgetsTab.baseWidgetDefinitions
                    items: widgetsTab.dankIslandOwnsSelectedBarCenter ? widgetsTab.getItemsForSection("island") : []
                    highlightedIndex: widgetsTab.highlightedIndex
                    highlightedSection: widgetsTab.highlightedSection
                    onItemEnabledChanged: (sectionId, index, enabled) => widgetsTab.handleItemEnabledChanged(sectionId, index, enabled)
                    onItemOrderChanged: (sectionId, indices) => {
                        const items = widgetsTab.getWidgetsForSection(sectionId);
                        widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                    }
                    onDragStarted: {
                        widgetsTab.highlightedSection = "";
                        widgetsTab.highlightedIndex = -1;
                    }
                    onAddWidget: sectionId => widgetsTab.showWidgetSelectionPopup(sectionId)
                    onRemoveWidget: (sectionId, index) => widgetsTab.removeWidgetFromSection(sectionId, index)
                    onSpacerSizeChanged: (sectionId, index, size) => widgetsTab.handleSpacerSizeChanged(sectionId, index, size)
                    onConfigureWidget: (sectionId, index) => widgetsTab.configureWidget(sectionId, index)

                    SettingsSearchRegistration {
                        target: islandSection
                        settingKey: "islandHomeLayout"
                    }
                }
            }

            SettingsDeferred {
                when: !widgetsTab.dankIslandOwnsSelectedBarCenter

                WidgetsTabSection {
                    width: parent.width
                    title: selectedBarIsVertical ? I18n.tr("Middle section") : I18n.tr("Center section")
                    sectionId: "center"
                    barId: widgetsTab.selectedBarId
                    allWidgets: widgetsTab.baseWidgetDefinitions
                    items: widgetsTab.getItemsForSection("center")
                    onItemEnabledChanged: (sectionId, index, enabled) => {
                        widgetsTab.handleItemEnabledChanged(sectionId, index, enabled);
                    }
                    highlightedIndex: widgetsTab.highlightedIndex
                    highlightedSection: widgetsTab.highlightedSection
                    onItemOrderChanged: (sectionId, indices) => {
                        const items = widgetsTab.getWidgetsForSection(sectionId);
                        widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                    }
                    reorderGroup: dragGroup
                    onDragStarted: {
                        widgetsTab.highlightedSection = "";
                        widgetsTab.highlightedIndex = -1;
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

            SettingsDeferred {
                WidgetsTabSection {
                    width: parent.width
                    title: selectedBarIsVertical ? I18n.tr("Bottom section") : I18n.tr("Right section")
                    sectionId: "right"
                    barId: widgetsTab.selectedBarId
                    allWidgets: widgetsTab.baseWidgetDefinitions
                    items: widgetsTab.getItemsForSection("right")
                    onItemEnabledChanged: (sectionId, index, enabled) => {
                        widgetsTab.handleItemEnabledChanged(sectionId, index, enabled);
                    }
                    highlightedIndex: widgetsTab.highlightedIndex
                    highlightedSection: widgetsTab.highlightedSection
                    onItemOrderChanged: (sectionId, indices) => {
                        const items = widgetsTab.getWidgetsForSection(sectionId);
                        widgetsTab.setWidgetsForSection(sectionId, indices.map(i => items[i]));
                    }
                    reorderGroup: dragGroup
                    onDragStarted: {
                        widgetsTab.highlightedSection = "";
                        widgetsTab.highlightedIndex = -1;
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
    }

    SettingsReorderPreview {
        group: dragGroup
    }
}
