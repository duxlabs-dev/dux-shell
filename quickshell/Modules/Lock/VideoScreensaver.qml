pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root
    readonly property var log: Log.scoped("VideoScreensaver")

    required property string screenName
    property bool active: false
    property string videoSource: ""
    property bool inputEnabled: false
    property point lastMousePos: Qt.point(-1, -1)
    property bool mouseInitialized: false
    readonly property var videoPlayer: playerLoader.item

    signal dismissed

    visible: active
    z: 1000

    Rectangle {
        id: background
        anchors.fill: parent
        color: Theme.screenOffColor
        visible: root.active

        Loader {
            id: playerLoader
            anchors.fill: parent
            active: false
            source: "VideoScreensaverPlayer.qml"
            onLoaded: {
                item.errorOccurred.connect((error, errorString) => {
                    log.warn("playback error:", errorString);
                    ToastService.showError(I18n.tr("Video screensaver"), I18n.tr("Playback error: %1", "%1 is the player error text").arg(errorString));
                    root.dismiss();
                });
                if (root.videoSource) {
                    item.source = root.videoSource;
                    item.play();
                }
            }
        }
    }

    Timer {
        id: inputEnableTimer
        interval: 500
        onTriggered: root.inputEnabled = true
    }

    Process {
        id: videoPicker
        property string result: ""
        property string folder: ""

        command: ["sh", "-c", "find '" + folder + "' -maxdepth 1 -type f \\( " + "-iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o " + "-iname '*.mov' -o -iname '*.avi' -o -iname '*.m4v' " + "\\) 2>/dev/null | shuf -n1"]

        stdout: SplitParser {
            onRead: data => {
                const path = data.trim();
                if (path) {
                    videoPicker.result = path;
                    root.videoSource = "file://" + path;
                }
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0 || !videoPicker.result) {
                log.warn("no video found in folder");
                ToastService.showError(I18n.tr("Video screensaver"), I18n.tr("No video found in folder"));
                root.dismiss();
            }
        }
    }

    Process {
        id: fileChecker
        command: ["test", "-d", SettingsData.lockScreenVideoPath]

        onExited: exitCode => {
            const isDir = exitCode === 0;
            const videoPath = SettingsData.lockScreenVideoPath;

            if (isDir) {
                videoPicker.folder = videoPath;
                videoPicker.running = true;
            } else if (SettingsData.lockScreenVideoCycling) {
                const parentFolder = videoPath.substring(0, videoPath.lastIndexOf('/'));
                videoPicker.folder = parentFolder;
                videoPicker.running = true;
            } else {
                root.videoSource = "file://" + videoPath;
            }
        }
    }

    function start() {
        if (!SettingsData.lockScreenVideoEnabled || !SettingsData.lockScreenVideoPath)
            return;

        MultimediaService.ensureProbed();
        if (!MultimediaService.available) {
            ToastService.showError(I18n.tr("Video screensaver"), I18n.tr("QtMultimedia is not available"));
            return;
        }

        playerLoader.active = true;
        if (playerLoader.status === Loader.Error) {
            log.warn("Failed to load video player");
            playerLoader.active = false;
            return;
        }

        videoPicker.result = "";
        videoPicker.folder = "";
        inputEnabled = false;
        mouseInitialized = false;
        lastMousePos = Qt.point(-1, -1);
        active = true;
        inputEnableTimer.start();
        fileChecker.running = true;
    }

    function dismiss() {
        if (!active)
            return;
        if (videoPlayer)
            videoPlayer.stop();
        playerLoader.active = false;
        inputEnabled = false;
        active = false;
        videoSource = "";
        dismissed();
    }

    onVideoSourceChanged: {
        if (videoSource && active && videoPlayer) {
            videoPlayer.source = videoSource;
            videoPlayer.play();
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.active && root.inputEnabled
        hoverEnabled: true
        propagateComposedEvents: false

        onPositionChanged: mouse => {
            if (!root.mouseInitialized) {
                root.lastMousePos = Qt.point(mouse.x, mouse.y);
                root.mouseInitialized = true;
                return;
            }
            var dx = Math.abs(mouse.x - root.lastMousePos.x);
            var dy = Math.abs(mouse.y - root.lastMousePos.y);
            if (dx > 5 || dy > 5) {
                root.dismiss();
            }
        }
        onClicked: root.dismiss()
        onPressed: root.dismiss()
        onWheel: root.dismiss()
    }

    Connections {
        target: IdleService

        function onLockRequested() {
            if (SettingsData.lockScreenVideoEnabled && !root.active) {
                root.start();
            }
        }

        function onFadeToLockRequested() {
            if (SettingsData.lockScreenVideoEnabled && !root.active) {
                IdleService.cancelFadeToLock();
                root.start();
            }
        }
    }
}
