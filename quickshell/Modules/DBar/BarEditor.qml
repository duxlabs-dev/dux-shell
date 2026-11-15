pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Dock
import qs.Modules.Settings

Item {
    id: root

    required property var body
    required property var content

    readonly property var barConfig: body.barConfig
    readonly property string barId: body._barId
    readonly property bool vertical: body.isVertical
    readonly property var sectionNames: ["left", "center", "right"]
    readonly property var entries: {
        const list = [];
        for (let position = 0; position < sectionNames.length; position++) {
            const section = content.overflowSections[position];
            section.entryRevision;
            const repeater = section.entryRepeater;
            for (let index = 0; index < (repeater?.count ?? 0); index++) {
                const wrapper = repeater.itemAt(index);
                if (wrapper?.participates)
                    list.push({
                        section: sectionNames[position],
                        index,
                        wrapper,
                        hidden: wrapper.itemData.enabled === false
                    });
            }
        }
        return list;
    }
    readonly property bool pickerOpen: pickerLoader.item?.visible ?? false
    property string sessionBarId: ""
    property string sessionScreenName: ""
    property Item hoveredWrapper: null
    property var dragEntry: null
    property real dragOffset: 0
    property var dropSlot: null
    property int addIndex: -1

    onEntriesChanged: cancelDrag()
    Component.onCompleted: {
        sessionBarId = BarWidgetService.editingBarId;
        sessionScreenName = BarWidgetService.editingScreenName;
    }
    Component.onDestruction: {
        cancelDrag();
        if (BarWidgetService.editingBarId === sessionBarId && BarWidgetService.editingScreenName === sessionScreenName)
            BarWidgetService.stopBarEdit();
    }

    function along(point) {
        return vertical ? point.y : point.x;
    }

    function bandStart(section) {
        const rect = mapFromItem(section, 0, 0, section.width, section.height);
        return (vertical ? rect.x + rect.width / 2 : rect.y + rect.height / 2) - body.widgetThickness / 2;
    }

    function slotRect(wrapper) {
        // mapFromItem is not reactive: reading every ancestor's position makes a calling binding follow the bar when it re-fits.
        for (let item = wrapper; item; item = item.parent)
            item.x + item.y;
        const rect = mapFromItem(wrapper, 0, 0, wrapper.width, wrapper.height);
        const band = bandStart(wrapper.sectionContext);
        if (vertical)
            return Qt.rect(band, rect.y, body.widgetThickness, rect.height);
        return Qt.rect(rect.x, band, rect.width, body.widgetThickness);
    }

    function entryAt(x, y) {
        const position = along(Qt.point(x, y));
        for (const entry of entries) {
            const rect = slotRect(entry.wrapper);
            const reach = entry.wrapper.sectionContext.widgetSpacing / 2;
            const start = along(rect) - reach;
            if (position >= start && position < start + (vertical ? rect.height : rect.width) + reach * 2)
                return entry;
        }
        return null;
    }

    function dropSlots() {
        const slots = [];
        for (let position = 0; position < sectionNames.length; position++) {
            const name = sectionNames[position];
            const section = content.overflowSections[position];
            const band = bandStart(section);
            const inline = entries.filter(entry => entry.section === name);
            if (inline.length === 0) {
                const rect = mapFromItem(section, 0, 0, section.width, section.height);
                slots.push({
                    section: name,
                    index: section.entryRepeater?.count ?? 0,
                    position: along(rect) + (vertical ? rect.height : rect.width) / 2,
                    band
                });
                continue;
            }
            const reach = section.widgetSpacing / 2;
            let end = 0;
            for (const entry of inline) {
                const rect = slotRect(entry.wrapper);
                end = along(rect) + (vertical ? rect.height : rect.width);
                slots.push({
                    section: name,
                    index: entry.index,
                    position: along(rect) - reach,
                    band
                });
            }
            slots.push({
                section: name,
                index: inline[inline.length - 1].index + 1,
                position: end + reach,
                band
            });
        }
        return slots;
    }

    function slotNear(position) {
        let nearest = null;
        for (const slot of dropSlots()) {
            if (!nearest || Math.abs(slot.position - position) < Math.abs(nearest.position - position))
                nearest = slot;
        }
        return nearest;
    }

    function movesWidget(slot) {
        if (!slot || !dragEntry)
            return false;
        return slot.section !== dragEntry.section || (slot.index !== dragEntry.index && slot.index !== dragEntry.index + 1);
    }

    function beginDrag(entry) {
        dragEntry = entry;
        entry.wrapper.slot.opacity = BarMetrics.hiddenWidgetOpacity;
    }

    function cancelDrag() {
        const wrapper = dragEntry?.wrapper;
        if (wrapper)
            wrapper.slot.opacity = 1;
        dragEntry = null;
        dropSlot = null;
        dragOffset = 0;
    }

    function finishDrag() {
        const entry = dragEntry;
        const slot = movesWidget(dropSlot) ? dropSlot : null;
        cancelDrag();
        if (slot)
            SettingsData.moveBarWidget(barId, entry.section, entry.index, slot.section, slot.index);
    }

    function dismiss() {
        if (menu.renderActive) {
            menu.hide();
            return;
        }
        BarWidgetService.stopBarEdit();
    }

    function pickWidget(section, index) {
        addIndex = index;
        pickerLoader.active = true;
        const picker = pickerLoader.item;
        picker.targetSection = section;
        picker.widgets = BarWidgetCatalog.addable(barConfig);
        picker.show();
    }

    function openBarSettings() {
        BarWidgetService.stopBarEdit();
        SettingsUiState.selectedBarId = barId;
        PopoutService.openSettingsWithTab("dankbar_widgets");
    }

    function openWidgetSettings(section, index, definition) {
        BarWidgetService.stopBarEdit();
        if (definition.pluginId) {
            PopoutService.openSettingsWithTab(SettingsTabs.pluginPrefix + definition.pluginId);
            return;
        }
        SettingsUiState.selectedDockId = "";
        SettingsUiState.selectedBarId = barId;
        SettingsUiState.selectedWidgetSection = section;
        SettingsUiState.selectedWidgetIndex = index;
        SettingsUiState.selectedWidgetTitle = definition.text ?? "";
        SettingsUiState.selectedWidgetDescription = definition.description ?? "";
        SettingsUiState.selectedWidgetIcon = definition.icon ?? "";
        PopoutService.openSettingsWithTab("bar_widget");
    }

    function widgetRows(entry, definitions) {
        const widgetId = entry.wrapper.itemData.widgetId;
        const definition = definitions.find(widget => widget.id === widgetId) ?? {
            id: widgetId
        };
        const section = entry.section;
        const index = entry.index;
        const rows = [];
        if (BarWidgetCatalog.configurable(definition))
            rows.push({
                type: "item",
                icon: "tune",
                text: I18n.tr("Widget settings"),
                action: () => root.openWidgetSettings(section, index, definition)
            });
        rows.push({
            type: "item",
            icon: entry.hidden ? "visibility" : "visibility_off",
            text: entry.hidden ? I18n.tr("Show") : I18n.tr("Hide"),
            action: () => SettingsData.updateBarWidget(root.barId, section, index, {
                    enabled: entry.hidden
                })
        }, {
            type: "item",
            icon: "delete",
            text: I18n.tr("Remove"),
            isDestructive: true,
            action: () => SettingsData.removeBarWidget(root.barId, section, index)
        }, {
            type: "separator"
        });
        return rows;
    }

    function openMenu(entry, x, y) {
        const slot = entry ? {
            section: entry.section,
            index: entry.index + 1
        } : slotNear(along(Qt.point(x, y)));
        menu.menuItems = (entry ? widgetRows(entry, BarWidgetCatalog.definitions()) : []).concat([
            {
                type: "item",
                icon: "add",
                text: I18n.tr("Add widget"),
                action: () => root.pickWidget(slot.section, slot.index)
            },
            {
                type: "separator"
            },
            {
                type: "item",
                icon: "check",
                text: I18n.tr("Finish"),
                action: () => BarWidgetService.stopBarEdit()
            }
        ]);
        menu.openFromBar(menuAnchor(x, y));
    }

    function menuInset(position) {
        const spacing = barConfig?.spacing ?? 4;
        const extent = vertical ? body.screen.height : body.screen.width;
        const menuLength = vertical ? menu.effectiveMenuHeight : menu.effectiveMenuWidth;
        const toolbarLength = vertical ? toolbar.height : toolbar.width;
        const menuStart = Math.max(menu.menuMargin, Math.min(extent - menuLength - menu.menuMargin, position - menuLength / 2));
        const toolbarStart = (extent - toolbarLength) / 2;
        if (menuStart + menuLength <= toolbarStart || menuStart >= toolbarStart + toolbarLength)
            return body.effectiveBarThickness + spacing + Math.max(Theme.spacingXS, spacing);
        return toolbar.inset + (vertical ? toolbar.width : toolbar.height) + Theme.spacingXS;
    }

    function menuAnchor(x, y) {
        const screen = body.screen;
        const edge = body.axis.edge;
        const point = content.surfaceContext.screenPoint(root, x, y);
        const inset = menuInset(along(point));
        if (vertical)
            return {
                x: edge === "left" ? inset : screen.width - inset,
                y: point.y,
                isVertical: true,
                edge,
                screen
            };
        return {
            x: point.x,
            y: edge === "bottom" ? screen.height - inset : inset,
            isVertical: false,
            edge,
            screen
        };
    }

    MouseArea {
        id: pointer

        property var pressedEntry: null
        property real pressPosition: 0

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.AllButtons
        cursorShape: root.dragEntry ? Qt.ClosedHandCursor : root.hoveredWrapper ? Qt.OpenHandCursor : Qt.ArrowCursor
        onPressed: mouse => {
            pressedEntry = mouse.button === Qt.LeftButton ? root.entryAt(mouse.x, mouse.y) : null;
            pressPosition = root.along(mouse);
        }
        onPositionChanged: mouse => {
            if (!pressed) {
                root.hoveredWrapper = root.entryAt(mouse.x, mouse.y)?.wrapper ?? null;
                return;
            }
            if (!pressedEntry)
                return;
            const offset = root.along(mouse) - pressPosition;
            if (!root.dragEntry) {
                if (Math.abs(offset) < Qt.styleHints.startDragDistance)
                    return;
                root.beginDrag(pressedEntry);
            }
            root.dragOffset = offset;
            root.dropSlot = root.slotNear(root.along(mouse));
        }
        onReleased: mouse => {
            pressedEntry = null;
            if (root.dragEntry) {
                root.finishDrag();
                return;
            }
            root.openMenu(root.entryAt(mouse.x, mouse.y), mouse.x, mouse.y);
        }
        onCanceled: {
            pressedEntry = null;
            root.cancelDrag();
        }
        onExited: root.hoveredWrapper = null
        onWheel: wheel => wheel.accepted = true
    }

    Repeater {
        model: root.entries

        Rectangle {
            required property var modelData
            readonly property Item wrapper: modelData.wrapper
            readonly property rect bounds: root.slotRect(wrapper)
            readonly property bool active: root.hoveredWrapper === wrapper || root.dragEntry?.wrapper === wrapper

            x: bounds.x
            y: bounds.y
            width: bounds.width
            height: bounds.height
            color: "transparent"
            radius: Theme.cornerRadiusS
            border.width: active ? Theme.outlineWidthFocused : Theme.outlineWidth
            border.color: active ? Theme.primary : Theme.outline
        }
    }

    ShaderEffectSource {
        readonly property Item wrapper: root.dragEntry?.wrapper ?? null
        readonly property rect bounds: wrapper ? root.mapFromItem(wrapper, 0, 0, wrapper.width, wrapper.height) : Qt.rect(0, 0, 0, 0)

        visible: wrapper !== null
        sourceItem: wrapper
        x: Theme.snap(bounds.x + (root.vertical ? 0 : root.dragOffset), root.body._dpr)
        y: Theme.snap(bounds.y + (root.vertical ? root.dragOffset : 0), root.body._dpr)
        width: bounds.width
        height: bounds.height
        textureSize: Qt.size(Math.round(width * root.body._dpr), Math.round(height * root.body._dpr))
    }

    Rectangle {
        readonly property var slot: root.movesWidget(root.dropSlot) ? root.dropSlot : null

        visible: slot !== null
        x: root.vertical ? (slot?.band ?? 0) : (slot?.position ?? 0) - width / 2
        y: root.vertical ? (slot?.position ?? 0) - height / 2 : (slot?.band ?? 0)
        width: root.vertical ? root.body.widgetThickness : Theme.outlineWidthFocused
        height: root.vertical ? Theme.outlineWidthFocused : root.body.widgetThickness
        radius: Theme.outlineWidthFocused / 2
        color: Theme.primary
    }

    DContextMenu {
        id: menu
    }

    LazyLoader {
        id: pickerLoader
        active: false

        WidgetSelectionPopup {
            onWidgetSelected: (widgetId, targetSection) => SettingsData.addBarWidget(root.barId, targetSection, widgetId, root.addIndex)
        }
    }

    PanelWindow {
        id: toolbar

        readonly property string edge: root.body.axis.edge
        readonly property real inset: Theme.px(root.body.effectiveBarThickness + root.body.surfaceSpacing, root.body._dpr) + Theme.spacingL

        screen: root.body.screen
        visible: !root.pickerOpen
        color: "transparent"
        implicitWidth: chrome.implicitWidth
        implicitHeight: chrome.implicitHeight

        anchors {
            top: edge === "top"
            bottom: edge === "bottom"
            left: edge === "left"
            right: edge === "right"
        }
        margins {
            top: edge === "top" ? inset : 0
            bottom: edge === "bottom" ? inset : 0
            left: edge === "left" ? inset : 0
            right: edge === "right" ? inset : 0
        }

        WlrLayershell.namespace: "dms:bar-editor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: PopoutManager.screenshotActive ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        FocusScope {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.dismiss()

            DockEditChrome {
                id: chrome
                title: root.barConfig?.name || I18n.tr("Bar widgets")
                onAddRequested: root.pickWidget("right", -1)
                onSettingsRequested: root.openBarSettings()
                onFinished: BarWidgetService.stopBarEdit()
            }
        }
    }
}
