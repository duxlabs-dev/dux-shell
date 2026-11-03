import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DContextMenu {
    id: root

    property var entry: null
    property var modal: null
    property var parentHandler: null

    readonly property bool hasPinnedDuplicate: !!entry && !entry.pinned && ClipboardService.getPinnedEntryByHash(entry.hash) !== null
    readonly property bool canEditEntry: ClipboardService.canEditEntry(entry)
    readonly property bool hasTextAlternative: !!entry && (entry.altMimeType ?? "") !== ""
    readonly property bool pinned: entry?.pinned || hasPinnedDuplicate

    layerNamespace: "dms:clipboard-context-menu"

    menuItems: {
        const items = [
            {
                type: "item",
                icon: "content_copy",
                text: I18n.tr("Copy"),
                action: copyEntry
            }
        ];
        if (hasTextAlternative)
            items.push({
                type: "item",
                icon: "text_fields",
                text: I18n.tr("Copy Text"),
                action: copyEntryAsText
            });
        items.push({
            type: "item",
            icon: pinned ? "keep_off" : "push_pin",
            text: pinned ? I18n.tr("Unpin", "verb, unpin a clipboard entry or wifi network") : I18n.tr("Pin", "verb, keep an item pinned in place"),
            action: togglePin
        });
        if (canEditEntry)
            items.push({
                type: "item",
                icon: "edit",
                text: I18n.tr("Edit"),
                action: editEntry
            });
        items.push({
            type: "item",
            icon: "delete",
            text: I18n.tr("Delete", "verb, delete button and confirm action"),
            action: deleteEntry
        }, {
            type: "separator"
        }, {
            type: "item",
            icon: "content_paste",
            text: I18n.tr("Paste", "verb, clipboard entry action"),
            action: pasteEntry
        });
        return items;
    }

    onBackdropRightClicked: (x, y) => showFromWindowPoint(x, y)

    function show(x, y, targetEntry) {
        if (!targetEntry)
            return;
        entry = targetEntry;

        const host = modal?.surfaceHost ?? null;
        const modalWindow = modal?.Window?.window ?? null;
        const screenRef = host?.effectiveScreen ?? host?.screen ?? modalWindow?.screen ?? parentHandler?.Window?.window?.screen ?? null;
        const screenX = screenRef?.x || 0;
        const screenY = screenRef?.y || 0;
        const hostX = host?.alignedX;
        const hostY = host?.renderedAlignedY ?? host?.alignedY;
        const globalPos = (!isNaN(hostX) && !isNaN(hostY)) ? ({
                x: screenX + hostX + x,
                y: screenY + hostY + y
            }) : (parentHandler ? parentHandler.mapToGlobal(x, y) : ({
                    x: screenX + x,
                    y: screenY + y
                }));
        open(screenRef, globalPos.x - screenX + Theme.spacingXS, globalPos.y - screenY + Theme.spacingXS, false);
    }

    function showFromWindowPoint(x, y) {
        const hit = typeof parentHandler?.contextEntryAtScreen === "function" ? parentHandler.contextEntryAtScreen(x, y) : null;
        if (!hit?.entry) {
            hide();
            return;
        }
        show(hit.x, hit.y, hit.entry);
    }

    function copyEntry() {
        if (!entry)
            return;
        modal?.copyEntry(entry);
        hide();
    }

    function copyEntryAsText() {
        if (!entry || !hasTextAlternative)
            return;
        modal?.copyEntryAsText(entry);
        hide();
    }

    function togglePin() {
        if (!entry)
            return;
        if (entry.pinned) {
            modal?.unpinEntry(entry);
        } else {
            const duplicate = ClipboardService.getPinnedEntryByHash(entry.hash);
            if (duplicate)
                modal?.unpinEntry(duplicate);
            else
                modal?.pinEntry(entry);
        }
        hide();
    }

    function editEntry() {
        if (!entry || !canEditEntry)
            return;
        modal?.editEntry(entry);
        hide();
    }

    function deleteEntry() {
        if (!entry)
            return;
        if (entry.pinned)
            modal?.deletePinnedEntry(entry);
        else
            modal?.deleteEntry(entry);
        hide();
    }

    function pasteEntry() {
        if (!entry)
            return;
        modal?.pasteEntry(entry);
        hide();
    }
}
