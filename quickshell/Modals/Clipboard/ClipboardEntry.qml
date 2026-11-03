import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DListItem {
    id: root

    required property var entry
    required property int itemIndex
    required property var modal

    signal copyRequested
    signal pasteRequested
    signal deleteRequested
    signal pinRequested(var targetEntry)
    signal unpinRequested(var targetEntry)
    signal editRequested
    signal previewRequested

    readonly property string entryType: modal ? modal.getEntryType(entry) : "text"
    readonly property string entryPreview: modal ? modal.getEntryPreview(entry) : ""
    readonly property var pinnedDuplicateEntry: !entry.pinned ? ClipboardService.getPinnedEntryByHash(entry.hash) : null
    readonly property bool hasPinnedDuplicate: pinnedDuplicateEntry !== null
    readonly property bool effectivePinned: entry.pinned || hasPinnedDuplicate
    readonly property var visibleEntryActions: SettingsData.clipboardVisibleEntryActions || ["pin", "edit", "delete"]
    readonly property bool showCopyAction: visibleEntryActions.includes("copy")
    readonly property bool showPasteAction: visibleEntryActions.includes("paste")
    readonly property bool showPinAction: visibleEntryActions.includes("pin")
    readonly property bool showEditAction: visibleEntryActions.includes("edit")
    readonly property bool showDeleteAction: visibleEntryActions.includes("delete")
    readonly property bool showPreviewAction: ClipboardService.canPreviewEntry(entry)
    readonly property bool showPinnedIndicator: effectivePinned && !showPinAction
    readonly property bool showAnyAction: showCopyAction || showPasteAction || showPinAction || showEditAction || showDeleteAction || showPinnedIndicator || showPreviewAction

    keyForwardTargets: [modal.modalFocusScope]
    firstInGroup: itemIndex === 0
    lastInGroup: itemIndex === listView.count - 1
    Accessible.name: entryPreview
    Accessible.description: entryType === "image" ? I18n.tr("Image") : I18n.tr("Text")
    onClicked: {
        if (SettingsData.clipboardClickToPaste) {
            pasteRequested();
            return;
        }
        copyRequested();
    }

    Row {
        id: actionButtons
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
        visible: root.showAnyAction

        DActionButton {
            Keys.forwardTo: [root.modal.modalFocusScope]
            objectName: "previewEntry"
            iconName: "preview"
            tooltipText: I18n.tr("Preview", "verb, clipboard entry action button tooltip", true)
            iconSize: Theme.iconSizeSmall
            iconColor: root.contentColor
            visible: root.showPreviewAction
            onClicked: root.previewRequested()
        }

        Item {
            width: Theme.iconButtonSize
            height: Theme.iconButtonSize
            visible: root.showPinnedIndicator

            DIcon {
                anchors.centerIn: parent
                name: "push_pin"
                size: Theme.iconSizeSmall
                color: root.colorForRole(Theme.primary)
            }
        }

        DActionButton {
            Keys.forwardTo: [root.modal.modalFocusScope]
            iconName: "content_copy"
            Accessible.name: I18n.tr("Copy")
            iconSize: Theme.iconSizeSmall
            iconColor: root.contentColor
            visible: root.showCopyAction
            onClicked: copyRequested()
        }

        DActionButton {
            Keys.forwardTo: [root.modal.modalFocusScope]
            iconName: "content_paste"
            Accessible.name: I18n.tr("Paste")
            iconSize: Theme.iconSizeSmall
            iconColor: root.contentColor
            visible: root.showPasteAction
            onClicked: pasteRequested()
        }

        DActionButton {
            Keys.forwardTo: [root.modal.modalFocusScope]
            iconName: "push_pin"
            Accessible.name: root.effectivePinned ? I18n.tr("Unpin") : I18n.tr("Pin", "verb, keep an item pinned in place")
            iconSize: Theme.iconSizeSmall
            iconFilled: root.effectivePinned
            iconColor: root.effectivePinned ? root.colorForRole(Theme.primary) : root.contentColor
            visible: root.showPinAction
            onClicked: {
                if (entry.pinned) {
                    unpinRequested(entry);
                    return;
                }
                if (pinnedDuplicateEntry) {
                    unpinRequested(pinnedDuplicateEntry);
                    return;
                }
                pinRequested(entry);
            }
        }

        DActionButton {
            Keys.forwardTo: [root.modal.modalFocusScope]
            iconName: "edit"
            Accessible.name: I18n.tr("Edit")
            iconSize: Theme.iconSizeSmall
            iconColor: root.contentColor
            visible: root.showEditAction
            enabled: root.entryType !== "image"

            onClicked: {
                if (entryType === "image") {
                    return;
                }
                editRequested();
            }
        }

        DActionButton {
            Keys.forwardTo: [root.modal.modalFocusScope]
            iconName: "close"
            Accessible.name: I18n.tr("Delete")
            iconSize: Theme.iconSizeSmall
            iconColor: root.contentColor
            visible: root.showDeleteAction
            onClicked: deleteRequested()
        }
    }

    Item {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.right: root.showAnyAction ? actionButtons.left : parent.right
        anchors.rightMargin: root.showAnyAction ? Theme.spacingM : Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        height: ClipboardConstants.itemHeight
        clip: true

        ClipboardThumbnail {
            id: thumbnail
            iconColor: root.colorForRole(Theme.primary)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: entryType === "image" ? ClipboardConstants.thumbnailSize : Theme.iconSize
            height: entryType === "image" ? ClipboardConstants.itemHeight - Theme.spacingXS : Theme.iconSize
            entry: root.entry
            entryType: root.entryType
            modal: root.modal
            listView: root.listView
            itemIndex: root.itemIndex
        }

        Column {
            id: contentColumn
            anchors.left: thumbnail.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            StyledText {
                text: {
                    switch (entryType) {
                    case "image":
                        return I18n.tr("Image") + " • " + entryPreview;
                    case "long_text":
                        return I18n.tr("Long Text");
                    default:
                        return I18n.tr("Text");
                    }
                }
                font.pixelSize: Theme.fontSizeSmall
                color: root.colorForRole(Theme.primary)
                font.weight: Theme.fontWeightMedium
                width: parent.width
                elide: Text.ElideRight
            }

            StyledText {
                text: entryPreview
                font.pixelSize: Theme.fontSizeMedium
                color: root.contentColor
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: entryType === "long_text" ? 3 + Math.min(0, Theme.densityLevel) : 1
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }
    }
}
