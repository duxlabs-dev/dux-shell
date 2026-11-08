pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property string currentPage: ""
    property string activeCategoryId: ""
    property var parentModal: null

    signal pageRequested(string pageId)

    property bool searchActive: searchField.text.length > 0
    property bool searchFocused: false
    property int searchSelectedIndex: 0
    property string keyboardHighlightId: ""
    readonly property var categoryStructure: SettingsTabs.structure
    readonly property var navGroups: {
        const groups = [];
        let current = [];
        for (const entry of categoryStructure) {
            if (entry.separator) {
                if (current.length)
                    groups.push(current);
                current = [];
                continue;
            }
            current.push(entry);
        }
        if (current.length)
            groups.push(current);
        return groups;
    }

    function focusSearch() {
        searchField.forceActiveFocus();
    }

    function focusAfterNavigation(keyboard) {
        if (keyboard || (parentModal?.isCompactMode && !parentModal.menuVisible)) {
            parentModal?.focusCurrentPage(keyboard);
            return;
        }
        parentModal?.focusSidebar();
    }

    function focusNavigation() {
        function findRow(item) {
            if (item.modelData?.id === root.activeCategoryId && item.visible && item.enabled)
                return item;
            for (const child of item.children ?? []) {
                const row = findRow(child);
                if (row)
                    return row;
            }
            return null;
        }
        const row = findRow(sidebarColumn);
        if (row && !searchActive) {
            row.forceActiveFocus(Qt.TabFocusReason);
            ensureRowVisible(row);
        } else {
            focusSearch();
        }
    }

    function moveRowFocus(forward) {
        const start = Window.activeFocusItem;
        if (start === root) {
            parentModal?.focusSidebar();
            return true;
        }
        let item = start;
        do {
            item = item?.nextItemInFocusChain(forward);
            if (!item || item === start)
                return false;
            let ancestor = item;
            while (ancestor && ancestor !== root)
                ancestor = ancestor.parent;
            if (!ancestor)
                return false;
        } while (!item.visible || !item.enabled)
        keyboardHighlightId = "";
        item.forceActiveFocus(forward ? Qt.TabFocusReason : Qt.BacktabFocusReason);
        ensureRowVisible(item);
        return true;
    }

    Keys.onPressed: event => {
        if ((event.modifiers & ~Qt.KeypadModifier) !== Qt.NoModifier)
            return;
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down)
            event.accepted = moveRowFocus(event.key === Qt.Key_Down);
    }

    function navigableIds() {
        const ids = [];
        for (const entry of categoryStructure) {
            if (entry.separator || !SettingsTabs.isVisible(SettingsTabs.page(entry.id)))
                continue;
            ids.push(entry.id);
        }
        return ids;
    }

    function moveHighlight(delta) {
        const ids = navigableIds();
        if (ids.length === 0)
            return;
        let position = ids.indexOf(keyboardHighlightId);
        if (position === -1)
            position = ids.indexOf(SettingsTabs.isPluginPage(currentPage) ? currentPage : activeCategoryId);
        keyboardHighlightId = ids[(position + delta + ids.length) % ids.length];
    }

    function selectHighlighted() {
        if (!keyboardHighlightId)
            return;
        pageRequested(keyboardHighlightId);
        keyboardHighlightId = "";
        root.focusAfterNavigation(true);
    }

    function ensureRowVisible(item) {
        if (!item || sidebarFlickable.height <= 0)
            return;
        const itemY = item.mapToItem(sidebarFlickable.contentItem, 0, 0).y;
        const viewH = sidebarFlickable.height;
        if (itemY >= sidebarFlickable.contentY && itemY + item.height <= sidebarFlickable.contentY + viewH)
            return;
        sidebarFlickable.contentY = Math.max(0, Math.min(itemY - viewH / 4, sidebarFlickable.contentHeight - viewH));
    }

    function openBarWidget(widgetId, addIfMissing) {
        const widget = BarWidgetCatalog.get(widgetId);
        let where = SettingsData.locateBarWidget(widgetId, SettingsUiState.selectedBarId);
        if (!where && addIfMissing) {
            const barId = SettingsData.getBarConfig(SettingsUiState.selectedBarId) ? SettingsUiState.selectedBarId : (SettingsData.barConfigs[0]?.id ?? "default");
            const section = widget?.section ?? "right";
            const index = SettingsData.addBarWidget(barId, section, widgetId);
            if (index >= 0)
                where = {
                    "barId": barId,
                    "section": section,
                    "index": index
                };
        }
        if (!where)
            return;
        SettingsUiState.selectedBarId = where.barId;
        SettingsUiState.selectedWidgetSection = where.section;
        SettingsUiState.selectedWidgetIndex = where.index;
        SettingsUiState.selectedDockId = "";
        SettingsUiState.selectedWidgetTitle = widget?.text ?? widgetId;
        SettingsUiState.selectedWidgetDescription = widget?.description ?? "";
        SettingsUiState.selectedWidgetIcon = widget?.icon ?? "widgets";
        pageRequested("dankbar_widgets");
        if (BarWidgetCatalog.hasOptions(widgetId))
            parentModal?.navigateTo("bar_widget");
    }

    function selectSearchResult(result, keyboard = true) {
        if (!result)
            return;
        if (result.runtimeType === "barWidget" || result.runtimeType === "barWidgetAdd") {
            openBarWidget(result.runtimeId, result.runtimeType === "barWidgetAdd");
            keyboardHighlightId = "";
            root.focusAfterNavigation(keyboard);
            return;
        }
        const islandBar = SettingsSearchService.islandBarFor(result.conditionKey, SettingsUiState.selectedBarId);
        if (islandBar)
            SettingsUiState.selectedBarId = islandBar.id;
        if (result.section)
            SettingsSearchService.navigateToSection(result.section);
        const page = result.page || SettingsTabs.pageForTabIndex(result.tabIndex);
        if (page)
            pageRequested(page);
        keyboardHighlightId = "";
        root.focusAfterNavigation(keyboard);
    }

    function navigateSearchResults(delta) {
        if (SettingsSearchService.results.length === 0)
            return;
        searchSelectedIndex = Math.max(0, Math.min(searchSelectedIndex + delta, SettingsSearchService.results.length - 1));
        Qt.callLater(ensureSearchResultVisible);
    }

    function ensureSearchResultVisible() {
        const result = searchResultsRepeater.itemAt(searchSelectedIndex);
        const contentItem = sidebarFlickable.contentItem;
        if (!result || !contentItem)
            return;

        const top = result.mapToItem(contentItem, 0, 0).y;
        sidebarFlickable.revealRange(top - Theme.spacingS, top + result.height + Theme.spacingS);
    }

    implicitWidth: SettingsMetrics.sidebarWidth
    width: implicitWidth
    height: parent.height

    Component.onCompleted: GreeterService.refresh()

    DSearchField {
        id: searchField

        property real sideInset: root.searchActive ? Theme.spacingS : SettingsMetrics.paneMargin

        Behavior on sideInset {
            enabled: Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
        }

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: sideInset
        anchors.rightMargin: sideInset
        placeholderText: I18n.tr("Search settings", "settings search field placeholder")
        rightAccessoryWidth: avatarButton.visible ? avatarButton.width + Theme.spacingXS : 0
        onFocusStateChanged: hasFocus => {
            root.searchFocused = hasFocus;
            if (!hasFocus)
                root.keyboardHighlightId = "";
        }
        onTextChanged: {
            SettingsSearchService.search(text);
            root.searchSelectedIndex = 0;
            sidebarFlickable.contentY = 0;
            Qt.callLater(root.ensureSearchResultVisible);
        }
        keyForwardTargets: [keyHandler]

        Item {
            id: keyHandler
            function navNext() {
                if (root.searchActive) {
                    root.navigateSearchResults(1);
                    return;
                }
                root.moveHighlight(1);
            }
            function navPrev() {
                if (root.searchActive) {
                    root.navigateSearchResults(-1);
                    return;
                }
                root.moveHighlight(-1);
            }
            function navSelect() {
                if (root.searchActive && SettingsSearchService.results.length > 0) {
                    root.selectSearchResult(SettingsSearchService.results[root.searchSelectedIndex]);
                    return;
                }
                if (!root.searchActive && root.keyboardHighlightId === "") {
                    root.parentModal?.focusCurrentPage();
                    return;
                }
                root.selectHighlighted();
            }
            Keys.onDownPressed: event => {
                navNext();
                event.accepted = true;
            }
            Keys.onUpPressed: event => {
                navPrev();
                event.accepted = true;
            }
            // Specific key handlers accept by default; with nothing to cycle, Tab must reach the focus chain
            Keys.onTabPressed: event => {
                event.accepted = !(event.modifiers & Qt.ControlModifier) && (root.searchActive || root.keyboardHighlightId !== "");
                if (event.accepted)
                    navNext();
            }
            Keys.onBacktabPressed: event => {
                event.accepted = !(event.modifiers & Qt.ControlModifier) && (root.searchActive || root.keyboardHighlightId !== "");
                if (event.accepted)
                    navPrev();
            }
            Keys.onEnterPressed: event => {
                navSelect();
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                navSelect();
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                if (root.searchActive) {
                    searchField.text = "";
                    SettingsSearchService.clear();
                } else {
                    root.keyboardHighlightId = "";
                }
                event.accepted = true;
            }
        }

        DActionButton {
            id: avatarButton

            anchors.right: parent.right
            anchors.rightMargin: (searchField.height - buttonSize) / 2
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.searchActive
            buttonSize: Theme.avatarSize
            radius: Theme.buttonRadius(width, height, buttonSize, false, circular)
            focusPolicy: Qt.TabFocus
            tooltipText: I18n.tr("Users & accounts", "settings sidebar category")
            onClicked: {
                root.pageRequested("user_accounts");
                root.focusAfterNavigation(visualFocus);
            }

            // Below the state layer so hover, press and focus tint the avatar
            DCircularImage {
                z: -1
                anchors.fill: parent
                ringWidth: Theme.avatarRingWidth
                ringColor: Theme.avatarRingColor
                imageSource: PortalService.profileImage
                fallbackIcon: imageSource ? "material:person" : ""
                fallbackText: (UserInfoService.fullName || I18n.tr("User")).charAt(0).toLocaleUpperCase()
            }
        }
    }

    DFlickable {
        id: sidebarFlickable
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: searchField.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: SettingsMetrics.searchBarGap
        clip: true
        contentHeight: sidebarColumn.height
        fadeSideInset: SettingsMetrics.paneMargin

        Column {
            id: sidebarColumn
            width: parent.width
            leftPadding: SettingsMetrics.paneMargin
            rightPadding: SettingsMetrics.paneMargin
            bottomPadding: SettingsMetrics.paneMargin
            spacing: SettingsMetrics.sidebarGroupGap

            Item {
                id: searchResultsFrame
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: searchResultsColumn.height
                visible: root.searchActive

                Column {
                    id: searchResultsColumn
                    width: parent.width
                    spacing: SettingsMetrics.groupGap

                    Repeater {
                        id: searchResultsRepeater
                        model: ScriptModel {
                            values: SettingsSearchService.results
                        }

                        SettingsSidebarItem {
                            id: resultDelegate
                            required property int index
                            required property var modelData

                            onActiveFocusChanged: {
                                if (activeFocus)
                                    root.ensureRowVisible(resultDelegate);
                            }
                            isFirstInGroup: index === 0
                            isLastInGroup: index === SettingsSearchService.results.length - 1
                            iconName: modelData.icon || "settings"
                            title: modelData.label
                            hint: modelData.category
                            accent: SettingsTabs.accentFor(modelData.page || SettingsTabs.pageForTabIndex(modelData.tabIndex))
                            active: root.searchSelectedIndex === index
                            onClicked: keyboard => {
                                root.searchSelectedIndex = index;
                                root.selectSearchResult(modelData, keyboard);
                            }
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: I18n.tr("No matches")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignHCenter
                        visible: searchField.text.length > 0 && SettingsSearchService.results.length === 0
                        topPadding: Theme.spacingM
                    }
                }

                Rectangle {
                    anchors.fill: searchResultsColumn
                    radius: Theme.groupedListOuterRadius
                    color: "transparent"
                    border.width: SettingsMetrics.groupFrameWidth
                    border.color: Theme.outlineMedium
                    visible: border.width > 0
                }
            }

            Column {
                width: parent.width - parent.leftPadding - parent.rightPadding
                spacing: SettingsMetrics.sidebarGroupGap
                visible: !root.searchActive

                Repeater {
                    model: root.navGroups

                    Item {
                        id: groupFrame
                        required property var modelData

                        width: parent.width
                        height: groupColumn.height

                        Column {
                            id: groupColumn
                            width: parent.width
                            spacing: SettingsMetrics.groupGap

                            readonly property var visibleIds: {
                                const ids = [];
                                for (const entry of modelData) {
                                    if (SettingsTabs.isVisible(SettingsTabs.page(entry.id)))
                                        ids.push(entry.id);
                                }
                                return ids;
                            }

                            Repeater {
                                model: groupFrame.modelData

                                SettingsSidebarItem {
                                    id: categoryRow
                                    required property var modelData

                                    onActiveFocusChanged: {
                                        if (activeFocus)
                                            root.ensureRowVisible(categoryRow);
                                    }
                                    readonly property bool isHighlighted: root.keyboardHighlightId === modelData.id
                                    onIsHighlightedChanged: {
                                        if (isHighlighted)
                                            Qt.callLater(root.ensureRowVisible, categoryRow);
                                    }

                                    width: groupColumn.width
                                    visible: SettingsTabs.isVisible(SettingsTabs.page(modelData.id))
                                    isFirstInGroup: groupColumn.visibleIds[0] === modelData.id
                                    isLastInGroup: groupColumn.visibleIds[groupColumn.visibleIds.length - 1] === modelData.id
                                    iconName: modelData.icon || ""
                                    title: modelData.text || ""
                                    hint: SettingsTabs.hubHint(modelData)
                                    accent: SettingsTabs.accentFor(modelData.id)
                                    active: root.activeCategoryId === modelData.id && !SettingsTabs.isPluginPage(root.currentPage)
                                    highlighted: isHighlighted
                                    onClicked: keyboard => {
                                        root.keyboardHighlightId = "";
                                        root.pageRequested(modelData.id);
                                        root.focusAfterNavigation(keyboard);
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: groupColumn
                            radius: Theme.groupedListOuterRadius
                            color: "transparent"
                            border.width: SettingsMetrics.groupFrameWidth
                            border.color: Theme.outlineMedium
                            visible: border.width > 0
                        }
                    }
                }
            }
        }
    }
}
