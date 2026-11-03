pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Rectangle {
    id: root

    property var entry: null
    property string cachedImageData: ""
    property string cachedMimeType: ""
    property var _requestedEntryId: null

    readonly property bool canLoadImage: ClipboardService.canPreviewEntry(entry)
    readonly property string sourceUrl: ClipboardService.imageDataUrl(cachedImageData, cachedMimeType || (entry?.mimeType ?? ""))

    radius: Theme.cornerRadiusM
    clip: true
    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    border.color: Theme.outlineMedium
    border.width: Theme.layerOutlineWidth

    onEntryChanged: reloadPreview()
    Component.onCompleted: reloadPreview()

    function reloadPreview() {
        if (!canLoadImage || typeof entry?.id !== "number") {
            _requestedEntryId = null;
            cachedImageData = "";
            cachedMimeType = "";
            return;
        }

        if (entry.id === _requestedEntryId)
            return;

        cachedImageData = "";
        cachedMimeType = "";
        const entryId = entry.id;
        _requestedEntryId = entryId;
        DMSService.sendRequest("clipboard.getEntry", {
            "id": entryId
        }, function (response) {
            if (_requestedEntryId !== entryId)
                return;
            if (response.error) {
                _requestedEntryId = null;
                return;
            }
            if (!response.result) {
                _requestedEntryId = null;
                ClipboardService.refresh();
                return;
            }
            const result = response.result;
            const mimeType = (result.mimeType ?? entry?.mimeType ?? "").toString();
            const data = (result.data ?? "").toString();
            if (data.length === 0 || !ClipboardService.imageDataUrl(data, mimeType)) {
                _requestedEntryId = null;
                return;
            }
            cachedMimeType = mimeType;
            cachedImageData = data;
        });
    }

    Image {
        id: previewImage
        anchors.fill: parent
        source: root.sourceUrl
        asynchronous: true
        cache: false
        smooth: true
        sourceSize.width: Theme.launcherTileSize
        sourceSize.height: Theme.launcherTileSize
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }

    DIcon {
        anchors.centerIn: parent
        name: "image"
        size: Math.min(Theme.iconSize, Math.max(Theme.iconSizeSmall, root.height / 2))
        color: Theme.primary
        visible: previewImage.status !== Image.Ready
    }
}
