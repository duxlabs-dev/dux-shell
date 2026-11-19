pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modals.DLauncherV2
import "ControllerUtils.js" as ControllerUtils

Rectangle {
    id: root

    property string filePath: ""
    property string thumbnailUrl: ""
    property string _requestedPath: ""

    readonly property bool isImage: ControllerUtils.isImage(filePath)
    readonly property bool isPreviewable: ControllerUtils.isPreviewableMedia(filePath)
    readonly property bool previewReady: previewImage.status === Image.Ready

    radius: Theme.cornerRadiusM
    clip: true
    color: Theme.foregroundColor(Theme.cardSurface, Theme.isFloatingWindow(root))
    border.color: Theme.outlineMedium
    border.width: Theme.layerOutlineWidth

    onFilePathChanged: reloadPreview()
    Component.onCompleted: reloadPreview()

    function reloadPreview() {
        if (!filePath || !isPreviewable) {
            _requestedPath = "";
            thumbnailUrl = "";
            return;
        }
        if (filePath === _requestedPath)
            return;

        thumbnailUrl = "";
        const target = filePath;
        _requestedPath = target;

        if (!FilesService.connected) {
            if (isImage)
                thumbnailUrl = Paths.toFileUrl(target);
            return;
        }

        FilesService.thumbnails([target], "normal", "", function (response) {
            if (root._requestedPath !== target)
                return;
            const found = !response?.error ? (response?.results ?? []).find(entry => entry.path === target) : null;
            if (found?.thumbnail) {
                thumbnailUrl = Paths.toFileUrl(found.thumbnail);
                return;
            }
            if (root.isImage)
                thumbnailUrl = Paths.toFileUrl(target);
        });
    }

    Image {
        id: previewImage
        anchors.fill: parent
        source: root.thumbnailUrl
        asynchronous: true
        cache: false
        smooth: true
        sourceSize.width: LauncherMetrics.previewWidth * 2
        sourceSize.height: LauncherMetrics.previewHeight * 2
        fillMode: Image.PreserveAspectCrop
        visible: status === Image.Ready
    }
}
