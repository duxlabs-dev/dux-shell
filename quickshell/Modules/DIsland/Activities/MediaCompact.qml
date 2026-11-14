pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.SurfaceWidgets

MediaActivityFace {
    id: root
    required property var controller
    dense: controller.compactDense
    isVertical: controller.isVertical
    artworkSize: controller.compactIconSize
    clockVisible: controller.mediaClockVisible
    controlsVisible: controller.mediaControls
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
    // Hovering a control must not let the island expand out from under the pointer.
    readonly property bool hoverSuppressed: clockHovered || controlsHovered
    property bool hoverCounted: false
    onHoverSuppressedChanged: {
        if (hoverCounted === hoverSuppressed)
            return;
        hoverCounted = hoverSuppressed;
        if (hoverSuppressed)
            controller.slotHoverEntered();
        else
            controller.slotHoverExited();
    }
    Component.onDestruction: if (hoverCounted)
        controller.slotHoverExited()
}
