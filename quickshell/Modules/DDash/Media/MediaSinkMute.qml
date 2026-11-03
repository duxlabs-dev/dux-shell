import QtQuick
import qs.Common
import qs.Services

MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        if (!AudioService.sink?.audio)
            return;
        SessionData.suppressOSDTemporarily();
        AudioService.sink.audio.muted = !AudioService.sink.audio.muted;
    }
}
