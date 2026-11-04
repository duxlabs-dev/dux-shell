pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.SurfaceWidgets

MediaActivityFace {
    id: root
    required property var controller
    titleVisible: controller.mediaTitleVisible
    visualizerIdle: controller.mediaVisualizerIdle
    artworkCircular: controller.mediaArtworkCircular
    dense: controller.compactDense
    isVertical: controller.isVertical
    artworkSize: controller.compactIconSize
    clockVisible: controller.mediaClockVisible
    lyricsEnabled: controller.mediaLyrics
    maxLength: controller.mediaCompactMaxLength
    function updateLength() {
        controller.setMediaContentLength(isVertical ? implicitHeight : implicitWidth);
    }
    onImplicitWidthChanged: updateLength()
    onImplicitHeightChanged: updateLength()
    onIsVerticalChanged: updateLength()
    Component.onCompleted: updateLength()
    onClockClicked: controller.requestActivity("home", false, false)
    onMediaClicked: controller.requestActivity("media", true, false)
}
