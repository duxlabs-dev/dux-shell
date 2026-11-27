import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Services
import "ClipboardUtils.js" as ClipboardUtils

Item {
    id: clipboardContent

    required property var modal
    property var transientSurfaceTracker: null

    property alias searchField: searchField
    property alias clipboardListView: clipboardListView
    property bool _dragInProgress: false

    onVisibleChanged: {
        if (!visible) {
            _dragInProgress = false;
            dragLauncher.cancel();
        }
    }
    Component.onDestruction: {
        _dragInProgress = false;
        dragLauncher.cancel();
    }

    readonly property var entries: modal.displayedEntries
    readonly property int pinnedSectionCount: modal.displayedPinnedCount
    readonly property bool hasSplitSections: pinnedSectionCount > 0 && modal.unpinnedEntries.length > 0
    readonly property bool showPinned: modal.showPinned
    onShowPinnedChanged: resetScroll.schedule()

    readonly property var filterOptions: [I18n.tr("All"), I18n.tr("Text"), I18n.tr("Long Text"), I18n.tr("Image", "noun, clipboard entry type and filter option")]
    readonly property var filterValues: ["all", "text", "long_text", "image"]

    function closeFilterMenu() {
        filterMenuLoader.active = false;
        filterMenuLoader.active = true;
    }

    function showContextMenu(entry, sceneX, sceneY) {
        const localPos = mapFromItem(null, sceneX, sceneY);
        contextMenu.show(localPos.x, localPos.y, entry);
    }

    function startEntryDrag(entry) {
        if (_dragInProgress || !entry || entry.id === undefined || entry.id === null)
            return;
        const host = clipboardContent.modal?.surfaceHost ?? null;
        if (host && !host.shouldBeVisible)
            return;
        _dragInProgress = true;
        const entryType = clipboardContent.modal.getEntryType(entry);
        const isFileOrImage = entryType === "image" || (entry.mimeType ?? "").toLowerCase().startsWith("text/uri-list");

        function finishDrag(action) {
            clipboardContent._dragInProgress = false;
            dragGhost.imageSource = "";
            dragGhost.previewText = "";
            clipboardContent.modal?.releaseTextInputFocus?.();
            if (host && typeof host.instantClose === "function") {
                host.instantClose();
                return true;
            }
            if (clipboardContent.modal) {
                clipboardContent.modal.hide();
                return true;
            }
            return false;
        }

        if (isFileOrImage) {
            DMSService.sendRequest("clipboard.exportEntryFile", {
                "id": entry.id
            }, function (response) {
                const res = response?.result;
                const uriList = res?.uriList || (res?.fileUrl ? res.fileUrl + "\r\n" : "");
                if ((host && !host.shouldBeVisible) || response?.error || !uriList) {
                    clipboardContent._dragInProgress = false;
                    return;
                }
                const fileUrl = res.fileUrl || "";
                const gnomeCopy = uriList.trim().split(/\r?\n/).filter(Boolean).join("\n");
                dragGhost.isImage = entryType === "image";
                dragGhost.imageSource = entryType === "image" ? fileUrl : "";
                dragGhost.previewText = clipboardContent.modal.getEntryPreview(entry);
                const mimeData = {
                    "text/uri-list": uriList,
                    "x-special/gnome-copied-files": "copy\n" + gnomeCopy + "\n"
                };
                if (res.portalKey)
                    mimeData["application/vnd.portal.filetransfer"] = res.portalKey;
                dragLauncher.launch(host, dragGhost, mimeData, Qt.point(dragGhost.width / 2, dragGhost.height / 2), finishDrag);
            });
            return;
        }

        DMSService.sendRequest("clipboard.getEntry", {
            "id": entry.id
        }, function (response) {
            if ((host && !host.shouldBeVisible) || response?.error || !response?.result?.data) {
                clipboardContent._dragInProgress = false;
                return;
            }
            const text = ClipboardUtils.decodeEntryData(response.result.data);
            if (!text) {
                clipboardContent._dragInProgress = false;
                return;
            }
            dragGhost.isImage = false;
            dragGhost.imageSource = "";
            dragGhost.previewText = clipboardContent.modal.getEntryPreview(entry);
            const mimeData = {
                "text/plain": text,
                "text/plain;charset=utf-8": text
            };
            dragLauncher.launch(host, dragGhost, mimeData, Qt.point(dragGhost.width / 2, dragGhost.height / 2), finishDrag);
        });
    }

    function contextEntryAtScreen(screenX, screenY) {
        const host = modal.surfaceHost ?? null;
        const hostX = host?.alignedX;
        const hostY = host?.renderedAlignedY ?? host?.alignedY;

        if (!isNaN(hostX) && !isNaN(hostY))
            return contextEntryAtLocal(screenX - hostX, screenY - hostY);

        const screenRef = host?.effectiveScreen ?? host?.screen ?? modal.Window?.window?.screen ?? null;
        const globalOrigin = mapToGlobal(0, 0);
        const screenOriginX = screenRef?.x || 0;
        const screenOriginY = screenRef?.y || 0;
        return contextEntryAtLocal(screenOriginX + screenX - globalOrigin.x, screenOriginY + screenY - globalOrigin.y);
    }

    function contextEntryAtLocal(localX, localY) {
        const listView = clipboardListView;
        const entries = clipboardContent.entries;

        if (!listView.visible || !entries)
            return null;

        const listPos = mapToItem(listView, localX, localY);
        if (listPos.x < 0 || listPos.x > listView.width || listPos.y < 0 || listPos.y > listView.height)
            return null;

        const index = listView.indexAt(listPos.x + listView.contentX, listPos.y + listView.contentY);
        if (index < 0 || index >= entries.length)
            return null;

        return {
            entry: entries[index],
            x: localX,
            y: localY
        };
    }

    function closeContextMenu() {
        contextMenu.hide();
    }

    readonly property bool contextMenuActive: contextMenu.renderActive

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    anchors.fill: parent

    DeferredAction {
        id: resetScroll
        onTriggered: {
            clipboardListView.forceLayout();
            clipboardListView.positionViewAtBeginning();
        }
    }

    ScriptModel {
        id: entriesModel
        values: clipboardContent.entries
        objectProp: "id"
    }

    ClipboardContextMenu {
        id: contextMenu
        modal: clipboardContent.modal
        parentHandler: clipboardContent
        transientSurfaceTracker: clipboardContent.transientSurfaceTracker
    }

    Column {
        id: headerColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: PopoutMetrics.contentPadding
        spacing: PopoutMetrics.contentGap
        focus: false

        ClipboardHeader {
            width: parent.width
            visible: !modal.popout
            modal: clipboardContent.modal
        }

        Item {
            id: searchRow
            width: parent.width
            implicitHeight: searchField.height

            ClipboardActions {
                id: inlineActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: modal.popout
                modal: clipboardContent.modal
            }

            DSearchField {
                id: searchField

                anchors.left: parent.left
                anchors.right: inlineActions.visible ? inlineActions.left : parent.right
                anchors.rightMargin: inlineActions.visible ? Theme.spacingS : 0
                rightAccessoryWidth: filterButton.width + Theme.spacingS
                placeholderText: I18n.tr("Search", "search field placeholder") + "…"
                focus: true
                ignoreTabKeys: true
                keyForwardTargets: [modal.modalFocusScope]

                onTextChanged: {
                    modal.searchText = text;
                    modal.updateFilteredModel();
                    ClipboardService.selectedIndex = 0;
                    ClipboardService.keyboardNavigationActive = true;
                    Qt.callLater(function () {
                        clipboardListView.positionViewAtBeginning();
                    });
                }

                Keys.onEscapePressed: function (event) {
                    modal.hide();
                    event.accepted = true;
                }

                Component.onCompleted: {
                    Qt.callLater(function () {
                        forceActiveFocus();
                    });
                }
            }

            DActionButton {
                id: filterButton

                anchors.right: searchField.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                iconName: "filter_list"
                iconColor: modal.activeFilter !== "all" ? Theme.primary : Theme.surfaceText
                backgroundColor: modal.activeFilter !== "all" ? Theme.primarySelected : Theme.withAlpha(Theme.primarySelected, 0)
                tooltipText: I18n.tr("Filter by type", "Clipboard history type filter button tooltip")
                onClicked: filterMenuLoader.item?.openDropdownMenu()
            }

            Loader {
                id: filterMenuLoader

                active: true
                sourceComponent: filterMenuComponent
            }

            Component {
                id: filterMenuComponent

                DDropdown {
                    showTrigger: false
                    popupAnchorItem: filterButton
                    popupWidth: 180
                    alignPopupRight: true
                    options: clipboardContent.filterOptions
                    currentValue: {
                        const idx = clipboardContent.filterValues.indexOf(clipboardContent.modal.activeFilter);
                        return idx >= 0 ? clipboardContent.filterOptions[idx] : clipboardContent.filterOptions[0];
                    }

                    onValueChanged: value => {
                        const idx = clipboardContent.filterOptions.indexOf(value);
                        if (idx >= 0) {
                            clipboardContent.modal.activeFilter = clipboardContent.filterValues[idx];
                        }
                    }
                }
            }
        }
    }

    Item {
        id: listContainer
        anchors.top: headerColumn.bottom
        anchors.topMargin: PopoutMetrics.contentGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: keyboardHintsLoader.top
        anchors.leftMargin: PopoutMetrics.contentPadding
        anchors.rightMargin: PopoutMetrics.contentPadding
        anchors.bottomMargin: keyboardHintsLoader.active ? PopoutMetrics.contentGap : 0
        clip: true

        DListView {
            id: clipboardListView
            reuseItems: true
            highlightSelection: false
            anchors.fill: parent
            model: entriesModel

            currentIndex: clipboardContent.modal ? clipboardContent.modal.selectedIndex : 0
            spacing: Theme.groupedListGap
            interactive: true
            flickDeceleration: 1500
            maximumFlickVelocity: 2000
            boundsBehavior: Flickable.StopAtBounds
            boundsMovement: Flickable.FollowBoundsBehavior
            pressDelay: 0
            flickableDirection: Flickable.VerticalFlick

            onContentYChanged: {
                if (contentY + height * 3 >= originY + contentHeight)
                    clipboardContent.modal.loadMore();
            }

            function ensureVisible(index) {
                if (index < 0 || index >= count) {
                    return;
                }
                revealIndex(index);
            }

            onCurrentIndexChanged: {
                // ListView shifts currentIndex itself when rows are inserted above it
                const selected = clipboardContent.modal.selectedIndex;
                if (currentIndex >= 0 && currentIndex !== selected && selected >= 0 && selected < count) {
                    currentIndex = Qt.binding(() => clipboardContent.modal ? clipboardContent.modal.selectedIndex : 0);
                    return;
                }
                if (clipboardContent.modal?.keyboardNavigationActive && currentIndex >= 0) {
                    ensureVisible(currentIndex);
                }
            }

            StyledText {
                text: !clipboardContent.modal.clipboardAvailable ? I18n.tr("Connecting to clipboard service...") : I18n.tr("No recent clipboard entries found")
                anchors.centerIn: parent
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                visible: clipboardContent.entries.length === 0
            }

            delegate: Item {
                id: entryDelegate

                required property int index
                required property var modelData

                readonly property bool showDividerBefore: clipboardContent.hasSplitSections && index === clipboardContent.pinnedSectionCount
                readonly property real dividerBandHeight: showDividerBefore ? Theme.spacingM + 2 : 0

                visible: index >= 0
                width: clipboardListView.width
                height: ClipboardConstants.itemHeight + dividerBandHeight

                ListView.onPooled: entryRow.resetInteractionState()
                ListView.onReused: entryRow.resetInteractionState()

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacingM
                    anchors.rightMargin: Theme.spacingM
                    y: Math.floor((entryDelegate.dividerBandHeight - Theme.groupedListGap - height) / 2)
                    height: 1
                    color: Theme.outlineVariant
                    opacity: 0.85
                    visible: entryDelegate.showDividerBefore
                }

                ClipboardEntry {
                    id: entryRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: ClipboardConstants.itemHeight
                    entry: entryDelegate.modelData
                    itemIndex: entryDelegate.index
                    firstInGroup: entryDelegate.index === 0 || entryDelegate.showDividerBefore
                    lastInGroup: entryDelegate.index === clipboardListView.count - 1 || (clipboardContent.hasSplitSections && entryDelegate.index === clipboardContent.pinnedSectionCount - 1)
                    isSelected: clipboardContent.modal?.keyboardNavigationActive && entryDelegate.index === clipboardContent.modal.selectedIndex
                    modal: clipboardContent.modal
                    listView: clipboardListView
                    onCopyRequested: clipboardContent.modal.copyEntry(entryDelegate.modelData)
                    onPasteRequested: clipboardContent.modal.pasteEntry(entryDelegate.modelData)
                    onDeleteRequested: {
                        if (entryDelegate.modelData.pinned) {
                            clipboardContent.modal.deletePinnedEntry(entryDelegate.modelData);
                            return;
                        }
                        clipboardContent.modal.deleteEntry(entryDelegate.modelData);
                    }
                    onPinRequested: targetEntry => clipboardContent.modal.pinEntry(targetEntry)
                    onUnpinRequested: targetEntry => clipboardContent.modal.unpinEntry(targetEntry)
                    onEditRequested: clipboardContent.modal.editEntry(entryDelegate.modelData)
                    onPreviewRequested: clipboardContent.modal.openPreview(entryDelegate.index)
                    onDragRequested: entry => clipboardContent.startEntryDrag(entry)
                    onContextMenuRequested: (mouseX, mouseY) => {
                        const pos = mapToItem(null, mouseX, mouseY);
                        clipboardContent.showContextMenu(entryDelegate.modelData, pos.x, pos.y);
                    }
                }
            }
        }
    }

    Loader {
        id: keyboardHintsLoader
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: PopoutMetrics.contentPadding
        anchors.rightMargin: PopoutMetrics.contentPadding
        anchors.bottomMargin: PopoutMetrics.contentPadding
        active: modal.showKeyboardHints
        height: item ? item.implicitHeight : 0

        Behavior on height {
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        sourceComponent: ClipboardKeyboardHints {
            pasteAvailable: modal.pasteAvailable
            enterToPaste: SettingsData.clipboardEnterToPaste
        }
    }

    DDragLauncher {
        id: dragLauncher
        width: 1
        height: 1
        visible: true
        opacity: 0
        supportedActions: Qt.CopyAction
    }

    Rectangle {
        id: dragGhost

        property bool isImage: false
        property string imageSource: ""
        property string previewText: ""

        x: -9999
        y: -9999
        visible: true
        opacity: 1
        width: isImage ? 80 : Math.min(220, ghostText.implicitWidth + Theme.spacingM * 2)
        height: isImage ? 80 : 40
        radius: Theme.cornerRadiusL
        color: Theme.chipSurface
        border.width: Theme.outlineWidth
        border.color: Theme.primary
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: Theme.spacingXS
            visible: dragGhost.isImage && dragGhost.imageSource !== ""
            source: dragGhost.imageSource
            sourceSize.width: dragGhost.width
            sourceSize.height: dragGhost.height
            cache: false
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            smooth: true
        }

        StyledText {
            id: ghostText
            anchors.centerIn: parent
            width: Math.min(200, implicitWidth)
            visible: !dragGhost.isImage
            text: dragGhost.previewText
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
