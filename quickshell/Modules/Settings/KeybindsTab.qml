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
    property var editorRetained: null
    property Item _editorReturnFocus: null

    property var editDraft: null
    property var reviewSnapshot: null
    property bool reviewingEdit: false
    property bool editBusy: false
    property string editError: ""
    property int _editRequest: 0
    property bool _editAlive: true
    readonly property bool hasEditDraft: editDraft !== null
    readonly property bool editInvalidated: hasEditDraft && (editDraft.provider !== KeybindsService.currentProvider || !KeybindsService.bindEditSession || editDraft.session !== KeybindsService.bindEditSession)
    readonly property bool showReview: hasEditDraft && (reviewingEdit || editError !== "" || editDraft.operation !== "set")
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
        if (KeybindsService.requiresBindReview)
            return "";
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

    onEditInvalidatedChanged: {
        if (!editInvalidated)
            return;
        _editRequest++;
        editBusy = false;
        reviewingEdit = true;
        reviewSnapshot = null;
        editError = KeybindsService.bindEditError("invalidated");
    }

    Component.onDestruction: {
        _editAlive = false;
        _editRequest++;
        KeybindsService.removeRef();
    }

    function beginEdit(binding, key) {
        if (hasEditDraft || editBusy || KeybindsService.bindMutationBusy) {
            ToastService.showInfo(I18n.tr("Save or discard the current edit before editing another shortcut.", "Aqueous keyboard shortcut editor, retaining an unsaved edit while reviewing current bindings"));
            return false;
        }
        try {
            editDraft = KeybindsService.captureBindEdit(binding, key);
            editError = "";
            reviewSnapshot = null;
            reviewingEdit = false;
            return true;
        } catch (e) {
            ToastService.showError(I18n.tr("Failed to load keybinds", "Aqueous shortcut editor could not load the current bindings"), AqueousService.errorMessage(String(e)), String(e));
            return false;
        }
    }

    function updateEditDraft(originalKey, data) {
        if (!editDraft || editDraft.operation !== "set" || editBusy || editInvalidated)
            return;
        editDraft = KeybindsService.updateBindEdit(editDraft, originalKey, data);
    }

    function submitEdit() {
        if (!editDraft || editBusy || reviewingEdit || editInvalidated || KeybindsService.bindMutationBusy)
            return;
        editBusy = true;
        editError = "";
        const token = ++_editRequest;
        const complete = result => {
            if (!keybindsTab._editAlive || token !== keybindsTab._editRequest)
                return;
            keybindsTab.editBusy = false;
            if (result.success) {
                const action = keybindsTab.editDraft.data.action;
                keybindsTab._dropDraft();
                keybindsTab._finishSave(action);
                return;
            }
            keybindsTab.reviewSnapshot = result.snapshot || null;
            keybindsTab.reviewingEdit = result.code !== "load_failed" && result.code !== "busy";
            keybindsTab.editError = KeybindsService.bindEditError(result.code);
        };
        switch (editDraft.operation) {
        case "set":
            KeybindsService.saveBind(editDraft.originalKey, editDraft.data, editDraft, complete);
            return;
        case "remove":
            KeybindsService.removeBind(editDraft.originalKey, editDraft, complete);
            return;
        case "reset":
            KeybindsService.resetBind(editDraft.originalKey, editDraft, complete);
            return;
        }
    }

    function reloadEdit() {
        if (!editDraft || editBusy || editInvalidated)
            return;
        editBusy = true;
        reviewingEdit = true;
        const token = ++_editRequest;
        KeybindsService.loadBindReview((snapshot, message) => {
            if (!keybindsTab._editAlive || token !== keybindsTab._editRequest)
                return;
            keybindsTab.editBusy = false;
            keybindsTab.reviewSnapshot = snapshot;
            keybindsTab.editError = message;
        });
    }

    function acceptReview() {
        if (!editDraft || !reviewSnapshot || editBusy || editInvalidated)
            return;
        const result = KeybindsService.reconcileBindEdit(editDraft, reviewSnapshot);
        if (!result.draft) {
            editError = KeybindsService.bindEditError(result.code);
            return;
        }
        editDraft = result.draft;
        reviewingEdit = false;
        editError = "";
        if (editDraft.operation !== "set")
            confirmEditRemoval();
    }

    function confirmEditRemoval() {
        if (!editDraft)
            return;
        if (editDraft.operation === "reset") {
            confirmResetBind(editDraft.originalKey);
            return;
        }
        confirmRemoveBind(editDraft.originalKey);
    }

    function _dropDraft() {
        editDraft = null;
        reviewSnapshot = null;
        reviewingEdit = false;
        editError = "";
    }

    function _finishSave(action) {
        if (editorOpen && editorIsNew)
            selectedCategory = "";
        _revealAction = action;
        closeEditor();
    }

    function discardEdit() {
        if (editBusy || KeybindsService.bindMutationBusy)
            return;
        _editRequest++;
        _dropDraft();
        closeEditor();
        KeybindsService.loadBinds(false);
    }

    function openEditor(bind, keyIndex) {
        if (editorOpen)
            return;
        const retained = hasEditDraft && editDraft.action === bind.action ? editDraft : null;
        if (KeybindsService.requiresBindReview && !retained && !beginEdit(bind, bind.keys[keyIndex]?.key || ""))
            return;
        editorBind = bind;
        editorKeyIndex = keyIndex;
        editorIsNew = false;
        editorRetained = retained;
        _showEditor();
    }

    function openNewEditor() {
        if (editorOpen)
            return;
        if (KeybindsService.readOnly) {
            KeybindsService.showHyprlandReadOnlyWarning();
            return;
        }
        if (KeybindsService.requiresBindReview && !beginEdit({
            "action": "",
            "desc": ""
        }, ""))
            return;
        editorBind = {
            "keys": [],
            "action": "",
            "desc": ""
        };
        editorKeyIndex = -1;
        editorIsNew = true;
        editorRetained = null;
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
        editorLoader.item.present(editorBind, editorKeyIndex, editorIsNew, editorRetained);
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

    function cancelEditor() {
        if (hasEditDraft) {
            discardEdit();
            return;
        }
        closeEditor();
    }

    function saveBind(originalKey, bindData) {
        if (KeybindsService.requiresBindReview) {
            updateEditDraft(originalKey, bindData);
            submitEdit();
            return;
        }
        _savingAction = bindData.action;
        KeybindsService.saveBind(originalKey, bindData);
    }

    function confirmRemoveBind(key) {
        const createsDraft = KeybindsService.requiresBindReview && !hasEditDraft;
        const draft = KeybindsService.requiresBindReview ? prepareRemoval(key, "remove") : null;
        if (KeybindsService.requiresBindReview && !draft)
            return;
        const baselineDraft = editDraft;
        removeBindConfirm.showWithOptions({
            "title": I18n.tr("Remove Shortcut?"),
            "message": KeybindsService.currentProvider === "hyprland" ? I18n.tr("Remove the shortcut %1? An unbind entry will be saved to %2 so it stays removed across DMS updates.", "hyprland remove shortcut confirmation, %1 is the key combination, %2 the override file").arg(key).arg("dms/binds-user.lua") : I18n.tr("Remove the shortcut %1?", "remove shortcut confirmation, %1 is the key combination").arg(key),
            "confirmText": I18n.tr("Remove"),
            "confirmColor": Theme.primary,
            "onConfirm": () => {
                if (draft) {
                    if (keybindsTab.editDraft !== baselineDraft)
                        return;
                    keybindsTab.editDraft = draft;
                    keybindsTab.submitEdit();
                    return;
                }
                KeybindsService.removeBind(key);
            },
            "onCancel": () => {
                if (createsDraft && keybindsTab.editDraft === baselineDraft)
                    keybindsTab._dropDraft();
            }
        });
    }

    function confirmResetBind(key) {
        const draft = KeybindsService.requiresBindReview ? prepareRemoval(key, "reset") : null;
        if (KeybindsService.requiresBindReview && !draft)
            return;
        const baselineDraft = editDraft;
        removeBindConfirm.showWithOptions({
            "title": I18n.tr("Reset to default"),
            "message": I18n.tr("Drop your override for %1 so the DMS default action re-applies?", "reset shortcut confirmation, %1 is the key combination").arg(key),
            "confirmText": I18n.tr("Reset"),
            "confirmColor": Theme.primary,
            "onConfirm": () => {
                if (draft) {
                    if (keybindsTab.editDraft !== baselineDraft)
                        return;
                    keybindsTab.editDraft = draft;
                    keybindsTab.submitEdit();
                    return;
                }
                KeybindsService.resetBind(key);
                keybindsTab.closeEditor();
            }
        });
    }

    function prepareRemoval(key, operation) {
        const binding = KeybindsService.getFlatBinds().find(bind => bind.keys.some(entry => entry.key === key));
        if (!binding)
            return null;
        if (hasEditDraft && editDraft.action !== binding.action) {
            ToastService.showInfo(I18n.tr("Save or discard the current edit before editing another shortcut.", "Aqueous keyboard shortcut editor, retaining an unsaved edit while reviewing current bindings"));
            return null;
        }
        if (!hasEditDraft && !beginEdit(binding, key))
            return null;
        if (editBusy || reviewingEdit || editInvalidated)
            return null;
        return KeybindsService.updateBindEdit(editDraft, key, null, operation);
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
        if (KeybindsService.requiresBindReview) {
            if (!keybindsTab.hasEditDraft && !KeybindsService.bindMutationBusy)
                KeybindsService.loadBinds(false);
            return;
        }
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

    component ReviewPanel: SettingsGroup {
        id: reviewPanel

        property var host: null

        SettingsRow {
            visible: reviewPanel.host.reviewingEdit || reviewPanel.host.editError !== ""
            iconName: "error"
            iconColor: Theme.error
            subtitle: reviewPanel.host.editError || I18n.tr("Review the current bindings before saving this edit.", "Aqueous keyboard shortcut editor, retaining an unsaved edit while reviewing current bindings")
            subtitleColor: Theme.error
        }

        SettingsRow {
            visible: reviewPanel.host.reviewingEdit && !!reviewPanel.host.reviewSnapshot
            subtitle: KeybindsService.describeBindReview(reviewPanel.host.editDraft, reviewPanel.host.reviewSnapshot)
            subtitleColor: Theme.surfaceText
        }

        SettingsRow {
            body: Row {
                LayoutMirroring.enabled: false
                width: parent.width
                spacing: Theme.spacingS
                layoutDirection: Qt.RightToLeft

                DButton {
                    text: I18n.tr("Accept reviewed changes", "Aqueous keyboard shortcut editor, retaining an unsaved edit while reviewing current bindings")
                    iconName: "check"
                    visible: reviewPanel.host.reviewingEdit && !!reviewPanel.host.reviewSnapshot
                    enabled: !reviewPanel.host.editBusy && !reviewPanel.host.editInvalidated
                    onClicked: reviewPanel.host.acceptReview()
                }

                DButton {
                    text: I18n.tr("Remove", "verb, button that removes an item from a list")
                    iconName: "delete"
                    visible: reviewPanel.host.hasEditDraft && reviewPanel.host.editDraft.operation !== "set"
                    enabled: !reviewPanel.host.editBusy && !reviewPanel.host.reviewingEdit && !reviewPanel.host.editInvalidated
                    onClicked: reviewPanel.host.confirmEditRemoval()
                }

                DButton {
                    text: I18n.tr("Discard")
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceText
                    enabled: !reviewPanel.host.editBusy && !KeybindsService.bindMutationBusy
                    onClicked: reviewPanel.host.discardEdit()
                }

                DActionButton {
                    iconName: "refresh"
                    iconColor: Theme.surfaceVariantText
                    Accessible.name: I18n.tr("Refresh")
                    enabled: !reviewPanel.host.editBusy && !reviewPanel.host.editInvalidated
                    onClicked: reviewPanel.host.reloadEdit()
                }
            }
        }
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
                            backgroundColor: Theme.primary
                            textColor: Theme.primaryText
                            enabled: !KeybindsService.fixing
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: KeybindsService.fixDmsBindsInclude()
                        }
                    }
                }

                ReviewPanel {
                    host: keybindsTab
                    visible: keybindsTab.showReview && !keybindsTab.editorOpen
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
            busy: keybindsTab.editBusy || KeybindsService.saving
            locked: keybindsTab.hasEditDraft && (keybindsTab.editBusy || keybindsTab.editInvalidated || KeybindsService.bindMutationBusy)
            saveBlocked: keybindsTab.hasEditDraft && (keybindsTab.reviewingEdit || keybindsTab.editDraft.operation !== "set")
            topContent: [
                ReviewPanel {
                    host: keybindsTab
                    visible: keybindsTab.showReview
                }
            ]
            onSaveRequested: (originalKey, data) => keybindsTab.saveBind(originalKey, data)
            onResetRequested: key => keybindsTab.confirmResetBind(key)
            onRejected: keybindsTab.cancelEditor()
            onActiveChanged: {
                if (!active && !keybindsTab.editorOpen)
                    keybindsTab.editorMounted = false;
            }
            onEditChanged: {
                if (!keybindsTab.hasEditDraft)
                    return;
                keybindsTab.updateEditDraft(editorDialog.addingNewKey ? "" : editorDialog.originalKey, {
                    "key": editorDialog.editKey,
                    "action": editorDialog.editAction,
                    "desc": editorDialog.editDesc
                });
            }
        }
    }

    ConfirmDialogOverlay {
        id: removeBindConfirm
        parent: keybindsTab.parentModal?.modalFocusScope ?? keybindsTab
        z: 101
    }
}
