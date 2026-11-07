pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets

ClippingRectangle {
    id: root

    color: "transparent"
    radius: Theme.windowRadius

    property var entry: null
    property string cachedImageData: ""
    property string cachedMimeType: ""
    property var requestedEntryId: null

    readonly property string sourceUrl: ClipboardService.imageDataUrl(cachedImageData, cachedMimeType || (entry?.mimeType ?? ""))
    readonly property string caption: (entry?.preview ?? "").replace(/^\[\[\s*/, "").replace(/\s*\]\]$/, "")

    signal closeRequested

    function loadEntry() {
        if (!ClipboardService.canPreviewEntry(entry)) {
            requestedEntryId = null;
            cachedImageData = "";
            cachedMimeType = "";
            return;
        }
        if (entry.id === requestedEntryId)
            return;

        cachedImageData = "";
        cachedMimeType = "";
        const entryId = entry.id;
        requestedEntryId = entryId;
        DMSService.sendRequest("clipboard.getEntry", {
            "id": entryId
        }, function (response) {
            if (root.requestedEntryId !== entryId)
                return;
            if (response.error) {
                root.requestedEntryId = null;
                return;
            }
            if (!response.result) {
                root.requestedEntryId = null;
                ClipboardService.refresh();
                return;
            }
            const mimeType = (response.result.mimeType ?? root.entry?.mimeType ?? "").toString();
            const data = (response.result.data ?? "").toString();
            if (!ClipboardService.imageDataUrl(data, mimeType)) {
                root.requestedEntryId = null;
                return;
            }
            root.cachedMimeType = mimeType;
            root.cachedImageData = data;
        });
    }

    onEntryChanged: loadEntry()
    Component.onCompleted: loadEntry()

    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.backdropColor, Theme.scrimAlpha)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.closeRequested()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: card

        anchors.fill: parent
        anchors.margins: Theme.spacingL
        radius: Theme.cornerRadiusL
        color: Theme.floatingWindowNestedSurface
        border.color: Theme.outlineMedium
        border.width: Theme.layerOutlineWidth

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.closeRequested()
            onWheel: wheel => wheel.accepted = true
        }

        DWindowHeader {
            id: header

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            controls: null
            horizontalPadding: 0
            verticalPadding: 0
            title: I18n.tr("Preview", "noun, clipboard image preview window title")
            onCloseRequested: root.closeRequested()
        }

        Item {
            id: frame

            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: captionText.top
            anchors.margins: Theme.spacingM

            Image {
                id: previewImage

                anchors.fill: parent
                source: root.sourceUrl
                asynchronous: true
                cache: false
                smooth: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(frame.width)
                sourceSize.height: Math.round(frame.height)
                visible: status === Image.Ready && source != ""
            }

            DIcon {
                anchors.centerIn: parent
                name: "image"
                size: Theme.iconSizeLarge
                color: Theme.primary
                visible: !previewImage.visible
            }
        }

        StyledText {
            id: captionText

            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacingM
            text: root.caption
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
