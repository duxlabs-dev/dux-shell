pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../Common/KeyUtils.js" as KeyUtils

Item {
    id: keybindsTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null
    property string selectedCategory: ""
    property string searchQuery: ""
    property string requestedSearchQuery: ""
    property bool searchFocused: false

    property int _lastDataVersion: -1
    property var _cachedCategories: []
    property var _filteredBinds: []
    property string _revealAction: ""
    property string _savingAction: ""

    property bool editorOpen: false
    property bool editorMounted: false
    property var editorBind: null
    property int editorKeyIndex: -1
    property bool editorIsNew: false
    property Item _editorReturnFocus: null

    readonly property bool initialLoading: KeybindsService.loading && _filteredBinds.length === 0
    readonly property Item windowFocusItem: keybindsTab.Window.window?.activeFocusItem ?? null

    onWindowFocusItemChanged: {
        if (editorOpen && !removeBindConfirm.visible)
            focusTrapTimer.restart();
    }

    Keys.onPressed: event => {
        if (!searchFocused)
            return;
        const chord = KeyUtils.shortcutFromSearchKey(event, KeybindsService.modKey, KeybindsService.modSymbol);
        if (!chord)
            return;
        event.accepted = true;
        flickable.headerItem.searchField.text = chord;
    }

    ShortcutInhibitor {
        id: searchInhibitor
        window: keybindsTab.QsWindow.window
        enabled: keybindsTab.searchFocused
    }

    readonly property var categoryChips: [
        {
            "label": I18n.tr("All"),
            "value": ""
        }
    ].concat(_cachedCategories.map(category => ({
                "label": getCategoryLabel(category),
                "value": category
            })))
    readonly property int categoryIndex: Math.max(0, categoryChips.findIndex(chip => chip.value === selectedCategory))

    readonly property string editorHint: {
        if (KeybindsService.readOnly)
            return I18n.tr("Hyprland conf mode is read-only in Settings");
        return I18n.tr("Changes save to %1", "hint under the keybind and window rule editors, %1 is the config file the changes are written to").arg(bindsFileLabel());
    }

    function bindsFileLabel() {
        switch (KeybindsService.currentProvider) {
        case "niri":
            return "dms/binds.kdl";
        case "hyprland":
            return "dms/binds-user.lua";
        default:
            return "dms/binds.conf";
        }
    }

    Component.onDestruction: KeybindsService.removeRef()

    function _finishSave(action) {
        if (editorOpen && editorIsNew)
            selectedCategory = "";
        _revealAction = action;
        closeEditor();
    }

    function openEditor(bind, keyIndex) {
        if (editorOpen)
            return;
        editorBind = bind;
        editorKeyIndex = keyIndex;
        editorIsNew = false;
        _showEditor();
    }

    function openNewEditor() {
        if (editorOpen)
            return;
        if (KeybindsService.readOnly) {
            KeybindsService.showHyprlandReadOnlyWarning();
            return;
        }
        editorBind = {
            "keys": [],
            "action": "",
            "desc": ""
        };
        editorKeyIndex = -1;
        editorIsNew = true;
        _showEditor();
    }

    function _showEditor() {
        const reuse = editorLoader.item !== null;
        _editorReturnFocus = keybindsTab.Window.window?.activeFocusItem ?? null;
        editorOpen = true;
        editorMounted = true;
        if (reuse)
            _presentLoadedEditor();
    }

    function _presentLoadedEditor() {
        editorLoader.item.present(editorBind, editorKeyIndex, editorIsNew);
    }

    function _trapEditorFocus() {
        const dialog = editorLoader.item;
        if (!editorOpen || !dialog || dialog.activeFocus || removeBindConfirm.visible)
            return;
        const first = dialog.nextItemInFocusChain(true);
        if (first && _isInside(first, dialog)) {
            first.forceActiveFocus(Qt.TabFocusReason);
            return;
        }
        dialog.forceActiveFocus();
    }

    function _isInside(item, ancestor) {
        for (let node = item; node; node = node.parent) {
            if (node === ancestor)
                return true;
        }
        return false;
    }

    function closeEditor() {
        if (!editorOpen)
            return;
        editorOpen = false;
        _savingAction = "";
        if (editorLoader.item)
            editorLoader.item.opened = false;
        const focusItem = _editorReturnFocus;
        _editorReturnFocus = null;
        if (focusItem?.visible && focusItem.enabled)
            focusItem.forceActiveFocus(Qt.OtherFocusReason);
    }

    function saveBind(originalKey, bindData) {
        _savingAction = bindData.action;
        KeybindsService.saveBind(originalKey, bindData);
    }

    function confirmRemoveBind(key) {
        removeBindConfirm.showWithOptions({
            "title": I18n.tr("Remove Shortcut?"),
            "message": KeybindsService.currentProvider === "hyprland" ? I18n.tr("Remove the shortcut %1? An unbind entry will be saved to %2 so it stays removed across DMS updates.", "hyprland remove shortcut confirmation, %1 is the key combination, %2 the override file").arg(key).arg("dms/binds-user.lua") : I18n.tr("Remove the shortcut %1?", "remove shortcut confirmation, %1 is the key combination").arg(key),
            "confirmText": I18n.tr("Remove"),
            "onConfirm": () => KeybindsService.removeBind(key)
        });
    }

    function confirmResetBind(key) {
        removeBindConfirm.showWithOptions({
            "title": I18n.tr("Reset to default"),
            "message": I18n.tr("Drop your override for %1 so the DMS default action re-applies?", "reset shortcut confirmation, %1 is the key combination").arg(key),
            "confirmText": I18n.tr("Reset"),
            "onConfirm": () => {
                KeybindsService.resetBind(key);
                keybindsTab.closeEditor();
            }
        });
    }

    function _updateFiltered() {
        const allBinds = KeybindsService.getFlatBinds();
        if (!searchQuery && !selectedCategory) {
            _filteredBinds = allBinds;
            return;
        }
        const query = searchQuery.toLowerCase();
        _filteredBinds = allBinds.filter(group => _matchesSearch(group, query) && _matchesCategory(group));
    }

    function _matchesSearch(group, query) {
        if (!query)
            return true;
        const combo = KeyUtils.normalizeKeyCombo(query, KeybindsService.modKey, KeybindsService.modSymbol);
        if (group.keys.some(entry => KeyUtils.normalizeKeyCombo(entry.key, KeybindsService.modKey, KeybindsService.modSymbol).includes(combo)))
            return true;
        return group.desc.toLowerCase().includes(query) || group.action.toLowerCase().includes(query);
    }

    function _matchesCategory(group) {
        if (!selectedCategory)
            return true;
        if (selectedCategory === "__overrides__")
            return group.keys.some(entry => entry.isOverride);
        return group.category === selectedCategory;
    }

    function _updateCategories() {
        _cachedCategories = ["__overrides__"].concat(KeybindsService.getCategories());
        if (selectedCategory && !_cachedCategories.includes(selectedCategory))
            selectedCategory = "";
    }

    function getCategoryLabel(cat) {
        if (cat === "__overrides__")
            return I18n.tr("Overrides", "noun plural, keybind category of user overridden shortcuts");
        return cat;
    }

    function scrollToTop() {
        flickable.positionViewAtBeginning();
    }

    function _revealPendingRow() {
        const action = _revealAction;
        _revealAction = "";
        const index = _filteredBinds.findIndex(bind => bind.action === action);
        if (!action || index < 0)
            return;
        flickable.revealIndex(index);
    }

    function _ensureCurrentProvider() {
        if (!KeybindsService.available)
            return;
        const cachedProvider = KeybindsService.keybinds?.provider;
        const targetProvider = KeybindsService.currentProvider;
        if (cachedProvider !== targetProvider || KeybindsService._dataVersion === 0) {
            KeybindsService.loadBinds();
            return;
        }
        if (_lastDataVersion !== KeybindsService._dataVersion) {
            _lastDataVersion = KeybindsService._dataVersion;
            _updateCategories();
            _updateFiltered();
        }
    }

    function _applyRequestedSearch() {
        if (!requestedSearchQuery)
            return;
        const query = requestedSearchQuery;
        selectedCategory = "";
        if (flickable.headerItem)
            flickable.headerItem.searchField.text = query;
        searchQuery = query;
        _updateFiltered();
        if (parentModal?.keybindSearchQuery === query)
            parentModal.keybindSearchQuery = "";
        Qt.callLater(scrollToTop);
    }

    Component.onCompleted: {
        KeybindsService.addRef();
        _ensureCurrentProvider();
        Qt.callLater(_applyRequestedSearch);
    }

    onRequestedSearchQueryChanged: Qt.callLater(_applyRequestedSearch)

    onVisibleChanged: {
        if (!visible)
            return;
        _ensureCurrentProvider();
        Qt.callLater(() => {
            _applyRequestedSearch();
            scrollToTop();
        });
    }

    Timer {
        id: searchDebounce
        interval: 150
        onTriggered: keybindsTab._updateFiltered()
    }

    Timer {
        id: focusTrapTimer
        interval: 0
        onTriggered: keybindsTab._trapEditorFocus()
    }

    Timer {
        id: revealTimer
        interval: 0
        onTriggered: keybindsTab._revealPendingRow()
    }

    Connections {
        target: KeybindsService

        function onBindsLoaded() {
            keybindsTab._lastDataVersion = KeybindsService._dataVersion;
            keybindsTab._updateCategories();
            keybindsTab._updateFiltered();
            if (keybindsTab._revealAction)
                revealTimer.restart();
        }

        function onBindSaveCompleted(success) {
            const action = keybindsTab._savingAction;
            keybindsTab._savingAction = "";
            if (!success || !action)
                return;
            keybindsTab._finishSave(action);
        }
    }

    DListView {
        id: flickable
        keyNavigationEnabled: false
        // ListView hands focus to every new current row; cleared, filtering can't steal it from the header search
        currentIndex: -1

        readonly property real columnWidth: Math.min(SettingsMetrics.contentMaxWidth, width - Theme.spacingL * 2)
        property Item fabBar: null
        property bool pinnedTop: false
        property bool pinning: false

        function pinToTop() {
            pinning = true;
            positionViewAtBeginning();
            pinning = false;
        }

        anchors.fill: parent
        clip: true
        spacing: Theme.groupedListGap
        Component.onCompleted: {
            pinnedTop = true;
            pinToTop();
        }
        onContentYChanged: {
            if (pinnedTop && !pinning && contentY > originY)
                pinnedTop = false;
        }
        // ListView grows the header upward, so a header that fills in after data loads would open scrolled past its top
        onOriginYChanged: {
            if (pinnedTop)
                pinToTop();
        }
        model: ScriptModel {
            values: keybindsTab._filteredBinds
            objectProp: "action"
        }

        header: Item {
            readonly property alias searchField: searchInput

            width: flickable.width
            height: headerColumn.height

            Binding {
                target: categoryFilter
                property: "currentIndex"
                value: keybindsTab.categoryIndex
            }

            Column {
                id: headerColumn
                width: flickable.columnWidth
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: Theme.spacingXS
                spacing: Theme.spacingL

                DSearchField {
                    id: searchInput
                    width: parent.width
                    placeholderText: searchInhibitor.active ? I18n.tr("Search or press a shortcut...") : I18n.tr("Search shortcuts...")
                    keyForwardTargets: [keybindsTab]
                    onFocusStateChanged: hasFocus => keybindsTab.searchFocused = hasFocus
                    onTextChanged: {
                        keybindsTab.searchQuery = text;
                        searchDebounce.restart();
                    }
                }

                DFilterChips {
                    id: categoryFilter
                    width: parent.width
                    showCounts: false
                    model: keybindsTab.categoryChips
                    onSelectionChanged: index => {
                        keybindsTab.selectedCategory = keybindsTab.categoryChips[index].value;
                        keybindsTab._updateFiltered();
                    }
                }

                StyledRect {
                    id: warningBox

                    readonly property var status: KeybindsService.dmsStatus
                    readonly property bool showLegacy: KeybindsService.readOnly
                    readonly property bool showWarning: !showLegacy && status.included && status.overriddenBy > 0
                    readonly property bool showSetup: !showLegacy && !status.included

                    width: parent.width
                    height: warningSection.implicitHeight + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.primary, 0.15)
                    border.color: Theme.withAlpha(Theme.primary, 0.3)
                    border.width: Theme.outlineWidth
                    visible: (showLegacy || showWarning || showSetup) && !KeybindsService.loading

                    Row {
                        id: warningSection
                        anchors.fill: parent
                        anchors.margins: Theme.spacingL
                        spacing: Theme.spacingM

                        DIcon {
                            name: warningBox.showWarning ? "info" : "warning"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: parent.width - Theme.iconSize - (fixButton.visible ? fixButton.width + Theme.spacingM : 0) - Theme.spacingM
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: {
                                    if (warningBox.showLegacy)
                                        return I18n.tr("%1 not found").arg("hyprland.lua");
                                    if (warningBox.showSetup)
                                        return I18n.tr("First Time Setup");
                                    if (warningBox.showWarning)
                                        return I18n.tr("Possible override conflicts");
                                    return "";
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: Theme.primary
                                width: parent.width
                                horizontalAlignment: Text.AlignLeft
                            }

                            StyledText {
                                text: {
                                    if (warningBox.showLegacy)
                                        return I18n.tr("Run %1 to create it before changing these settings.", "hyprland.lua missing warning, %1 is a command").arg("dms setup");
                                    if (warningBox.showSetup)
                                        return I18n.tr("Click 'Setup' to create %1 and add include to your compositor config.", "include setup banner, %1 is the dms config file name").arg("dms/binds");
                                    if (warningBox.showWarning) {
                                        const count = warningBox.status.overriddenBy;
                                        return (count === 1 ? I18n.tr("%1 DMS bind may be overridden by config binds that come after the include.", "singular, keybinds warning, %1 is 1") : I18n.tr("%1 DMS binds may be overridden by config binds that come after the include.", "plural, keybinds warning, %1 is a count")).arg(count);
                                    }
                                    return "";
                                }
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                wrapMode: Text.WordWrap
                                width: parent.width
                                horizontalAlignment: Text.AlignLeft
                            }
                        }

                        DButton {
                            id: fixButton
                            visible: warningBox.showSetup
                            text: KeybindsService.fixing ? I18n.tr("Setting up...") : I18n.tr("Setup", "verb, button that creates the dms include config file")
                            enabled: !KeybindsService.fixing
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: KeybindsService.fixDmsBindsInclude()
                        }
                    }
                }

                Column {
                    width: parent.width

                    SettingsSectionLabel {
                        text: {
                            if (keybindsTab.initialLoading)
                                return I18n.tr("Shortcuts");
                            const count = keybindsTab._filteredBinds.length;
                            return count === 1 ? I18n.tr("Shortcut (%1)", "singular, keybind list heading, %1 is 1").arg(count) : I18n.tr("Shortcuts (%1)", "plural, keybind list heading, %1 is a count").arg(count);
                        }
                    }

                    SettingsGroup {
                        SettingsRow {
                            visible: keybindsTab.initialLoading
                            subtitle: I18n.tr("Loading keybinds...")

                            leading: Loader {
                                active: keybindsTab.initialLoading
                                sourceComponent: DSpinner {
                                    size: Theme.iconSize
                                }
                            }
                        }

                        SettingsRow {
                            visible: !keybindsTab.initialLoading && keybindsTab._filteredBinds.length === 0
                            subtitle: I18n.tr("No keybinds found")
                        }
                    }
                }

                SettingsFabBar {
                    shown: !KeybindsService.readOnly || KeybindsService.cheatsheetAvailable

                    DFab {
                        text: I18n.tr("Cheatsheet", "button opening the keybinds cheatsheet overlay")
                        iconName: "keyboard"
                        colorRole: "secondaryContainer"
                        visible: KeybindsService.cheatsheetAvailable
                        onClicked: PopoutService.showKeybindsModal()
                    }

                    DFab {
                        text: I18n.tr("Add shortcut", "keybind editor dialog title and button")
                        iconName: "add"
                        visible: !KeybindsService.readOnly
                        onClicked: keybindsTab.openNewEditor()
                    }
                }
            }
        }

        delegate: Item {
            id: bindDelegate

            required property var modelData
            required property int index

            width: flickable.width
            height: bindRow.height

            KeybindRow {
                id: bindRow
                width: flickable.columnWidth
                anchors.horizontalCenter: parent.horizontalCenter
                bindData: bindDelegate.modelData
                firstInGroup: bindDelegate.index === 0
                lastInGroup: bindDelegate.index === flickable.count - 1
                readOnly: KeybindsService.readOnly
                onEditRequested: keyIndex => keybindsTab.openEditor(bindDelegate.modelData, keyIndex)
                onRemoveRequested: key => keybindsTab.confirmRemoveBind(key)
            }
        }

        footer: Item {
            width: flickable.width
            height: SettingsMetrics.pagePaddingV + (flickable.fabBar?.reservedHeight ?? 0)
        }
    }

    Loader {
        id: editorLoader
        parent: keybindsTab.parentModal?.modalFocusScope ?? keybindsTab
        anchors.fill: parent
        z: 100
        active: keybindsTab.editorMounted
        onLoaded: keybindsTab._presentLoadedEditor()

        sourceComponent: KeybindEditorDialog {
            id: editorDialog

            panelWindow: keybindsTab.parentModal
            supportingText: keybindsTab.editorHint
            readOnly: KeybindsService.readOnly
            busy: KeybindsService.saving
            onSaveRequested: (originalKey, data) => keybindsTab.saveBind(originalKey, data)
            onResetRequested: key => keybindsTab.confirmResetBind(key)
            onRejected: keybindsTab.closeEditor()
            onActiveChanged: {
                if (!active && !keybindsTab.editorOpen)
                    keybindsTab.editorMounted = false;
            }
        }
    }

    ConfirmDialogOverlay {
        id: removeBindConfirm
        parent: keybindsTab.parentModal?.modalFocusScope ?? keybindsTab
        z: 101
    }
}
