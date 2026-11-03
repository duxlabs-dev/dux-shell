import QtQuick
import qs.Services

MouseArea {
    id: root

    required property var player
    required property Item button

    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: root.player.toggleMute()
    onWheel: wheel => {
        if (wheel.angleDelta.y === 0)
            return;
        wheel.accepted = true;
        root.player.adjustVolume((wheel.angleDelta.y > 0 ? 1 : -1) * AudioService.wheelVolumeStep);
        root.button.showTooltip();
    }
}
