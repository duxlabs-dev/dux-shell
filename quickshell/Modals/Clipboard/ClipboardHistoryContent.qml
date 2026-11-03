pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services

FocusScope {
    id: root

    property var clearConfirmDialog: null
    property var surfaceHost: null
    property var transientSurfaceTracker: null
    property bool popout: false

    property string activeTab: "recents"
    property bool showKeyboardHints: false
    property int activeImageLoads: 0
    readonly property int maxConcurrentLoads: 3

    property string mode: "history"
    property string searchText: ClipboardService.searchText
    property string activeFilter: SettingsData.clipboardRememberTypeFilter ? SettingsData.clipboardTypeFilter : "all"

    readonly property bool clipboardAvailable: ClipboardService.clipboardAvailable
    readonly property bool pasteAvailable: ClipboardService.pasteAvailable
    readonly property int totalCount: ClipboardService.totalCount
    readonly property var clipboardEntries: ClipboardService.clipboardEntries
    readonly property var pinnedEntries: ClipboardService.pinnedEntries
    readonly property int pinnedCount: ClipboardService.pinnedCount
    readonly property var unpinnedEntries: ClipboardService.unpinnedEntries
    readonly property int selectedIndex: ClipboardService.selectedIndex
    readonly property bool keyboardNavigationActive: ClipboardService.keyboardNavigationActive
    readonly property bool clearsFilteredOnly: activeTab === "recents" && ClipboardService.filterActive
    readonly property bool canClear: clearsFilteredOnly ? unpinnedEntries.length > 0 : ClipboardService.internalEntries.length > pinnedCount
    readonly property var currentEntry: selectedEntry()

    readonly property var modalFocusScope: root
    property alias searchField: historyContent.searchField
    property alias editorView: editorView
    property alias keyboardController: keyboardController
    readonly property alias contextMenuActive: historyContent.contextMenuActive

    function closeContextMenu() {
        historyContent.closeContextMenu();
    }

    signal closeRequested
    signal instantCloseRequested

    onActiveTabChanged: {
        if (activeTab === "saved" && pinnedCount === 0) {
            activeTab = "recents";
            return;
        }
        ClipboardService.selectedIndex = 0;
        ClipboardService.keyboardNavigationActive = true;
    }
    onPinnedCountChanged: {
        if (activeTab === "saved" && pinnedCount === 0) {
            activeTab = "recents";
        }
    }
    onSearchTextChanged: ClipboardService.searchText = searchText
    onCurrentEntryChanged: {
        if (mode === "preview" && !ClipboardService.canPreviewEntry(currentEntry)) {
            closePreview();
        }
    }

    onActiveFilterChanged: {
        ClipboardService.activeFilter = activeFilter;
        ClipboardService.selectedIndex = 0;
        ClipboardService.keyboardNavigationActive = true;
        ClipboardService.updateFilteredModel();
        if (SettingsData.clipboardRememberTypeFilter) {
            SettingsData.set("clipboardTypeFilter", activeFilter);
        }
    }

    function releaseTextInputFocus() {
        // Drop text-input focus before hiding the Wayland surface.
        if (searchField) {
            searchField.setFocus(false);
        }
        if (editorView) {
            editorView.releaseTextInputFocus();
        }
        root.forceActiveFocus();
    }

    function requestClose(instant) {
        releaseTextInputFocus();
        if (instant) {
            root.instantCloseRequested();
        } else {
            root.closeRequested();
        }
    }

    function hide() {
        requestClose(false);
    }

    function openSettings() {
        const host = surfaceHost;
        requestClose(false);
        PopoutService.openSettingsWithTab("clipboard", host, () => host?.show());
    }

    function pasteSelected() {
        const entry = selectedEntry();
        if (!entry)
            return;
        ClipboardService.pasteEntry(entry, () => root.requestClose(true));
    }

    function pasteEntry(entry) {
        ClipboardService.pasteEntry(entry, () => root.requestClose(true));
    }

    function copyEntry(entry) {
        ClipboardService.copyEntry(entry, () => root.requestClose(false));
    }

    function copyEntryAsText(entry) {
        ClipboardService.copyEntry(entry, () => root.requestClose(false), true);
    }

    function openPreview(index = selectedIndex) {
        const entries = activeTab === "saved" ? pinnedEntries : unpinnedEntries;
        if (!ClipboardService.canPreviewEntry(entries[index])) {
            return;
        }
        ClipboardService.selectedIndex = index;
        ClipboardService.keyboardNavigationActive = true;
        mode = "preview";
    }

    function closePreview() {
        if (mode !== "preview") {
            return;
        }
        mode = "history";
        searchField?.forceActiveFocus();
    }

    function selectedEntry() {
        const entries = activeTab === "saved" ? pinnedEntries : unpinnedEntries;
        if (!entries || entries.length === 0 || selectedIndex < 0 || selectedIndex >= entries.length)
            return null;
        return entries[selectedIndex];
    }

    function deleteEntry(entry) {
        ClipboardService.deleteEntry(entry);
    }

    function deletePinnedEntry(entry) {
        ClipboardService.deletePinnedEntry(entry, clearConfirmDialog);
    }

    function pinEntry(entry) {
        ClipboardService.pinEntry(entry);
    }

    function unpinEntry(entry) {
        ClipboardService.unpinEntry(entry);
    }

    function clearAll() {
        ClipboardService.clearAll();
    }

    function clearFiltered() {
        ClipboardService.clearFiltered();
    }

    function confirmClearAll() {
        if (clearsFilteredOnly) {
            // The list is filtered, so clear what it shows and leave the modal
            // open on the filter the user is working through. A filter that
            // matches nothing must never fall back to clearing everything.
            if (unpinnedEntries.length === 0) {
                return;
            }
            clearConfirmDialog.show(I18n.tr("Clear History?"), I18n.tr("This will delete the %1 entries matching the current filter. Pinned entries are kept.", "clipboard modal: clear confirmation while a search filter is active, %1 is the number of matching entries").arg(unpinnedEntries.length), function () {
                clearFiltered();
            }, function () {});
            return;
        }
        if (!canClear)
            return;
        const hasPinned = pinnedCount > 0;
        const message = hasPinned ? I18n.tr("This will delete all unpinned entries. %1 pinned entries will be kept.", "clear clipboard history confirmation, %1 is a count").arg(pinnedCount) : I18n.tr("This will permanently delete all clipboard history.");
        clearConfirmDialog.show(I18n.tr("Clear History?"), message, function () {
            clearAll();
            hide();
        }, function () {});
    }

    function getEntryPreview(entry) {
        return ClipboardService.getEntryPreview(entry);
    }

    function getEntryType(entry) {
        return ClipboardService.getEntryType(entry);
    }

    function updateFilteredModel() {
        ClipboardService.updateFilteredModel();
    }

    function refreshClipboard() {
        ClipboardService.refresh();
    }

    function editEntry(entry) {
        if (!ClipboardService.canEditEntry(entry)) {
            return;
        }

        const requestedId = entry.id;
        if (!requestedId) {
            editorView.setEntry(entry);
            mode = "editor";
            return;
        }

        DMSService.sendRequest("clipboard.getEntry", {
            "id": requestedId
        }, function (response) {
            if (response.error || !response.result) {
                ToastService.showError(I18n.tr("Failed to load clipboard entry", "clipboard editor: fetching the entry's full text failed"));
                if (!response.result) {
                    ClipboardService.refresh();
                }
                return;
            }
            const result = response.result;
            let fullText = "";
            if (result?.data) {
                fullText = editorView.decodeEntryData(result.data);
            } else {
                fullText = result?.preview ?? "";
            }

            if (!fullText && (entry.preview ?? "").length > 0) {
                ToastService.showError(I18n.tr("Failed to load clipboard entry", "clipboard editor: fetching the entry's full text failed"));
                return;
            }

            const entryWithText = Object.assign({}, entry, {
                "text": fullText
            });
            editorView.setEntry(entryWithText);
            mode = "editor";
        });
    }

    function resetState() {
        activeImageLoads = 0;
        mode = "history";
        historyContent.closeContextMenu();
        historyContent.closeFilterMenu();
        activeFilter = SettingsData.clipboardRememberTypeFilter ? SettingsData.clipboardTypeFilter : "all";
        ClipboardService.reset();
        keyboardController.reset();
    }

    focus: true
    Keys.onPressed: function (event) {
        keyboardController.handleKey(event);
    }

    ClipboardKeyboardController {
        id: keyboardController
        modal: root
    }

    Item {
        id: historyView
        anchors.fill: parent
        opacity: 1
        scale: 1
        visible: opacity > 0.01
        enabled: root.mode === "history"

        ClipboardContent {
            id: historyContent
            anchors.fill: parent
            modal: root
            transientSurfaceTracker: root.transientSurfaceTracker
        }
    }

    ClipboardEditor {
        id: editorView
        anchors.fill: parent
        opacity: 0
        scale: 0.98
        visible: opacity > 0.01
        enabled: root.mode === "editor"
        focus: root.mode === "editor"
        modal: root
        keyController: keyboardController
    }

    Loader {
        id: previewLoader

        anchors.fill: parent
        z: 200
        active: root.mode === "preview"
        focus: root.mode === "preview"

        sourceComponent: ClipboardImagePreview {
            entry: root.currentEntry
            focus: true
            onCloseRequested: root.closePreview()
        }
    }

    states: [
        State {
            name: "history"
            when: root.mode === "history"
            PropertyChanges {
                target: historyView
                opacity: 1
                scale: 1
            }
            PropertyChanges {
                target: editorView
                opacity: 0
                scale: 0.98
            }
        },
        State {
            name: "editor"
            when: root.mode === "editor"
            PropertyChanges {
                target: historyView
                opacity: 0
                scale: 0.98
            }
            PropertyChanges {
                target: editorView
                opacity: 1
                scale: 1
            }
        }
    ]

    transitions: [
        Transition {
            from: "history"
            to: "editor"
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
                NumberAnimation {
                    property: "scale"
                    duration: Theme.shortDuration
                    easing.type: Theme.emphasizedEasing
                }
            }
        },
        Transition {
            from: "editor"
            to: "history"
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
                NumberAnimation {
                    property: "scale"
                    duration: Theme.shortDuration
                    easing.type: Theme.emphasizedEasing
                }
            }
        }
    ]
}
