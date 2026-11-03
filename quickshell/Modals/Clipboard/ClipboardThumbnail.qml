import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets

ClippingRectangle {
    id: thumbnail
    readonly property var log: Log.scoped("ClipboardThumbnail")

    required property var entry
    required property string entryType
    required property var modal
    required property var listView
    required property int itemIndex
    property bool disposed: false
    property color iconColor: Theme.primary

    radius: Theme.cornerRadiusS
    color: "transparent"
    antialiasing: true

    Image {
        id: thumbnailImage

        property bool isVisible: false
        property string cachedImageData: ""
        property bool loadQueued: false
        property bool activeLoad: false
        property bool completed: false
        property int loadGeneration: 0
        property var activeEntryId: null
        property var activeRequest: null
        property var currentEntryId: entry && entry.id !== undefined ? entry.id : null
        property string currentEntryType: entryType

        anchors.fill: parent
        source: cachedImageData ? `data:image/png;base64,${cachedImageData}` : ""
        fillMode: Image.PreserveAspectCrop
        smooth: true
        cache: false
        visible: entryType === "image" && status === Image.Ready && source != ""
        asynchronous: true
        sourceSize.width: 128
        sourceSize.height: 128

        onCurrentEntryIdChanged: {
            if (thumbnailImage.completed) {
                thumbnailImage.resetForEntry();
            }
        }

        onCurrentEntryTypeChanged: {
            if (thumbnailImage.completed) {
                thumbnailImage.resetForEntry();
            }
        }

        function hasValidEntryId() {
            return entry && entry.id !== undefined && entry.id !== null;
        }

        function releaseActiveLoad() {
            if (!thumbnailImage.activeLoad) {
                return;
            }
            thumbnailImage.activeLoad = false;
            if (modal && modal.activeImageLoads > 0) {
                modal.activeImageLoads--;
            }
        }

        function finishLoad(request) {
            thumbnailImage.loadQueued = false;
            thumbnailImage.activeEntryId = null;
            if (!request || thumbnailImage.activeRequest === request) {
                thumbnailImage.activeRequest = null;
            }
            thumbnailImage.releaseActiveLoad();
        }

        function cancelLoad() {
            if (thumbnailImage.activeRequest) {
                thumbnailImage.activeRequest.cancelled = true;
                thumbnailImage.activeRequest = null;
            }
            retryTimer.stop();
            visibilityTimer.stop();
            thumbnailImage.loadQueued = false;
            thumbnailImage.activeEntryId = null;
            thumbnailImage.releaseActiveLoad();
        }

        function resetForEntry() {
            thumbnailImage.loadGeneration++;
            thumbnailImage.cachedImageData = "";
            thumbnailImage.isVisible = false;
            thumbnailImage.cancelLoad();
            Qt.callLater(function () {
                if (thumbnail.disposed) {
                    return;
                }
                thumbnailImage.checkVisibility();
            });
        }

        function startLoad() {
            if (!modal) {
                thumbnailImage.loadQueued = false;
                return;
            }
            modal.activeImageLoads++;
            thumbnailImage.activeLoad = true;
            thumbnailImage.loadImage();
        }

        function tryLoadImage() {
            if (thumbnail.disposed || thumbnailImage.loadQueued || entryType !== "image" || thumbnailImage.cachedImageData || !thumbnailImage.hasValidEntryId()) {
                return;
            }
            thumbnailImage.loadQueued = true;
            if (modal && modal.activeImageLoads < modal.maxConcurrentLoads) {
                thumbnailImage.startLoad();
            } else {
                retryTimer.restart();
            }
        }

        function loadImage() {
            if (!thumbnailImage.hasValidEntryId()) {
                thumbnailImage.finishLoad();
                return;
            }
            const requestedId = entry.id;
            const generation = thumbnailImage.loadGeneration;
            const request = {
                "cancelled": false
            };
            thumbnailImage.activeEntryId = requestedId;
            thumbnailImage.activeRequest = request;
            DMSService.sendRequest("clipboard.getEntry", {
                "id": requestedId
            }, function (response) {
                if (request.cancelled) {
                    return;
                }
                if (thumbnail.disposed || generation !== thumbnailImage.loadGeneration || thumbnailImage.activeRequest !== request || thumbnailImage.activeEntryId !== requestedId) {
                    return;
                }
                thumbnailImage.finishLoad(request);
                if (!entry || entry.id !== requestedId || entryType !== "image") {
                    return;
                }
                if (response.error) {
                    log.warn("Failed to load image:", requestedId);
                    return;
                }
                if (!response.result) {
                    ClipboardService.refresh();
                    return;
                }
                const data = response.result?.data;
                if (data) {
                    thumbnailImage.cachedImageData = data;
                }
            });
        }

        Timer {
            id: retryTimer
            interval: ClipboardConstants.retryInterval
            onTriggered: {
                if (!thumbnailImage.loadQueued) {
                    return;
                }
                if (modal && modal.activeImageLoads < modal.maxConcurrentLoads) {
                    thumbnailImage.startLoad();
                } else {
                    retryTimer.restart();
                }
            }
        }

        Component.onCompleted: {
            thumbnailImage.completed = true;
            if (entryType !== "image" || listView.height <= 0 || !thumbnailImage.hasValidEntryId()) {
                return;
            }

            const itemY = itemIndex * (ClipboardConstants.itemHeight + listView.spacing);
            const viewTop = listView.contentY;
            const viewBottom = viewTop + listView.height;
            isVisible = (itemY + ClipboardConstants.itemHeight >= viewTop && itemY <= viewBottom);

            if (isVisible) {
                tryLoadImage();
            }
        }

        Component.onDestruction: {
            thumbnail.disposed = true;
            thumbnailImage.cancelLoad();
        }

        Timer {
            id: visibilityTimer
            interval: 100
            onTriggered: thumbnailImage.checkVisibility()
        }

        function checkVisibility() {
            if (thumbnail.disposed || entryType !== "image" || listView.height <= 0 || isVisible || !thumbnailImage.hasValidEntryId()) {
                return;
            }
            const itemY = itemIndex * (ClipboardConstants.itemHeight + listView.spacing);
            const viewTop = listView.contentY - ClipboardConstants.viewportBuffer;
            const viewBottom = viewTop + listView.height + ClipboardConstants.extendedBuffer;
            const nowVisible = (itemY + ClipboardConstants.itemHeight >= viewTop && itemY <= viewBottom);
            if (nowVisible) {
                isVisible = true;
                tryLoadImage();
            }
        }

        readonly property real listContentY: listView.contentY
        readonly property real listHeight: listView.height

        onListContentYChanged: {
            if (isVisible || entryType !== "image") {
                return;
            }
            visibilityTimer.restart();
        }

        onListHeightChanged: {
            if (isVisible || entryType !== "image") {
                return;
            }
            visibilityTimer.restart();
        }
    }

    DIcon {
        visible: !(entryType === "image" && thumbnailImage.status === Image.Ready && thumbnailImage.source != "")
        name: {
            switch (entryType) {
            case "image":
                return "image";
            case "long_text":
                return "subject";
            default:
                return "content_copy";
            }
        }
        size: Theme.iconSize
        color: thumbnail.iconColor
        anchors.centerIn: parent
    }
}
