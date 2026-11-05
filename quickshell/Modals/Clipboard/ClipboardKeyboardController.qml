import QtQuick
import qs.Common
import qs.Services

QtObject {
    id: keyboardController

    required property var modal

    function reset() {
        ClipboardService.selectedIndex = 0;
        ClipboardService.keyboardNavigationActive = true;
        modal.showKeyboardHints = false;
    }

    function selectNext() {
        const entries = modal.activeTab === "saved" ? ClipboardService.pinnedEntries : ClipboardService.unpinnedEntries;
        if (!entries || entries.length === 0) {
            return;
        }
        ClipboardService.keyboardNavigationActive = true;
        ClipboardService.selectedIndex = Math.min(ClipboardService.selectedIndex + 1, entries.length - 1);
        if (ClipboardService.selectedIndex >= entries.length - ClipboardService.pageSize / 2)
            modal.loadMore();
    }

    function selectPrevious() {
        const entries = modal.activeTab === "saved" ? ClipboardService.pinnedEntries : ClipboardService.unpinnedEntries;
        if (!entries || entries.length === 0) {
            return;
        }
        ClipboardService.keyboardNavigationActive = true;
        ClipboardService.selectedIndex = Math.max(ClipboardService.selectedIndex - 1, 0);
    }

    function copySelected() {
        const entries = modal.activeTab === "saved" ? ClipboardService.pinnedEntries : ClipboardService.unpinnedEntries;
        if (!entries || entries.length === 0 || ClipboardService.selectedIndex < 0 || ClipboardService.selectedIndex >= entries.length) {
            return;
        }
        const selectedEntry = entries[ClipboardService.selectedIndex];
        modal.copyEntry(selectedEntry);
    }

    function deleteSelected() {
        const entries = modal.activeTab === "saved" ? ClipboardService.pinnedEntries : ClipboardService.unpinnedEntries;
        if (!entries || entries.length === 0 || ClipboardService.selectedIndex < 0 || ClipboardService.selectedIndex >= entries.length) {
            return;
        }
        const selectedEntry = entries[ClipboardService.selectedIndex];
        if (modal.activeTab === "saved") {
            modal.deletePinnedEntry(selectedEntry);
        } else {
            modal.deleteEntry(selectedEntry);
        }
    }

    function togglePinSelected() {
        const entries = modal.activeTab === "saved" ? ClipboardService.pinnedEntries : ClipboardService.unpinnedEntries;
        if (!entries || entries.length === 0 || ClipboardService.selectedIndex < 0 || ClipboardService.selectedIndex >= entries.length) {
            return;
        }
        const selectedEntry = entries[ClipboardService.selectedIndex];
        if (selectedEntry.pinned) {
            modal.unpinEntry(selectedEntry);
            return;
        }
        const pinnedDuplicate = ClipboardService.getPinnedEntryByHash(selectedEntry.hash);
        if (pinnedDuplicate) {
            modal.unpinEntry(pinnedDuplicate);
        } else {
            modal.pinEntry(selectedEntry);
        }
    }

    function editSelected() {
        const entries = modal.activeTab === "saved" ? ClipboardService.pinnedEntries : ClipboardService.unpinnedEntries;
        if (!entries || entries.length === 0) {
            return;
        }
        const index = ClipboardService.selectedIndex >= 0 && ClipboardService.selectedIndex < entries.length ? ClipboardService.selectedIndex : 0;
        modal.editEntry(entries[index]);
    }

    function handlePreviewKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Escape:
            modal.closePreview();
            break;
        case Qt.Key_Space:
            if (ctrl) {
                modal.closePreview();
            }
            break;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            selectNext();
            break;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            selectPrevious();
            break;
        case Qt.Key_N:
        case Qt.Key_J:
            if (ctrl) {
                selectNext();
            }
            break;
        case Qt.Key_P:
        case Qt.Key_K:
            if (ctrl) {
                selectPrevious();
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            {
                const shifted = (event.modifiers & Qt.ShiftModifier) !== 0;
                const paste = shifted ? !SettingsData.clipboardEnterToPaste : SettingsData.clipboardEnterToPaste;
                if (paste) {
                    modal.pasteSelected();
                } else {
                    copySelected();
                }
            }
            break;
        }
        event.accepted = true;
    }

    function handleKey(event) {
        if (modal.mode === "preview") {
            handlePreviewKey(event);
            return;
        }

        if (modal.mode === "editor") {
            if (event.key === Qt.Key_Escape) {
                modal.mode = "history";
                event.accepted = true;
            }
            return;
        }

        if (modal.contextMenuActive) {
            if (event.key === Qt.Key_Escape)
                modal.closeContextMenu();
            event.accepted = true;
            return;
        }

        switch (event.key) {
        case Qt.Key_Escape:
            modal.hide();
            event.accepted = true;
            return;
        case Qt.Key_Down:
        case Qt.Key_Tab:
            if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                modal.activeTab = modal.activeTab === "saved" ? "recents" : "saved";
                ClipboardService.selectedIndex = 0;
                event.accepted = true;
                return;
            }
            if (!ClipboardService.keyboardNavigationActive) {
                ClipboardService.keyboardNavigationActive = true;
                ClipboardService.selectedIndex = 0;
            } else {
                selectNext();
            }
            event.accepted = true;
            return;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            if (event.key === Qt.Key_Backtab && (event.modifiers & Qt.ControlModifier)) {
                modal.activeTab = modal.activeTab === "saved" ? "recents" : "saved";
                ClipboardService.selectedIndex = 0;
                event.accepted = true;
                return;
            }
            if (!ClipboardService.keyboardNavigationActive) {
                ClipboardService.keyboardNavigationActive = true;
                ClipboardService.selectedIndex = 0;
            } else {
                selectPrevious();
            }
            event.accepted = true;
            return;
        case Qt.Key_F10:
            modal.showKeyboardHints = !modal.showKeyboardHints;
            event.accepted = true;
            return;
        }

        if (event.modifiers & Qt.ControlModifier) {
            switch (event.key) {
            case Qt.Key_N:
            case Qt.Key_J:
                if (!ClipboardService.keyboardNavigationActive) {
                    ClipboardService.keyboardNavigationActive = true;
                    ClipboardService.selectedIndex = 0;
                } else {
                    selectNext();
                }
                event.accepted = true;
                return;
            case Qt.Key_P:
            case Qt.Key_K:
                if (!ClipboardService.keyboardNavigationActive) {
                    ClipboardService.keyboardNavigationActive = true;
                    ClipboardService.selectedIndex = 0;
                } else {
                    selectPrevious();
                }
                event.accepted = true;
                return;
            case Qt.Key_C:
                if (ClipboardService.keyboardNavigationActive) {
                    copySelected();
                    event.accepted = true;
                }
                return;
            case Qt.Key_S:
                if (ClipboardService.keyboardNavigationActive) {
                    togglePinSelected();
                    event.accepted = true;
                }
                return;
            case Qt.Key_E:
                editSelected();
                event.accepted = true;
                return;
            case Qt.Key_Space:
                if (ClipboardService.keyboardNavigationActive) {
                    modal.openPreview();
                    event.accepted = true;
                }
                return;
            }
        }

        if (event.modifiers & Qt.ShiftModifier) {
            switch (event.key) {
            case Qt.Key_Delete:
                modal.confirmClearAll();
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (ClipboardService.keyboardNavigationActive) {
                    if (SettingsData.clipboardEnterToPaste) {
                        copySelected();
                    } else {
                        modal.pasteSelected();
                    }
                    event.accepted = true;
                }
                return;
            }
        }

        if (ClipboardService.keyboardNavigationActive) {
            switch (event.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:
                if (SettingsData.clipboardEnterToPaste) {
                    modal.pasteSelected();
                } else {
                    copySelected();
                }
                event.accepted = true;
                return;
            case Qt.Key_Delete:
                deleteSelected();
                event.accepted = true;
                return;
            }
        }
    }
}
