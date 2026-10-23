import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property MprisPlayer activePlayer
    property real stableLength: 0
    readonly property bool canSeek: enabled && (activePlayer?.canSeek ?? false) && stableLength > 0
    readonly property real minimumValue: 0
    readonly property real maximumValue: 1
    readonly property real stepSize: stableLength > 0 ? 5 / stableLength : 0
    readonly property bool wantsPosition: visible && (Window.window?.visible ?? false)
    property bool _positionHeld: false
    onWantsPositionChanged: _syncPositionRef(wantsPosition)
    Component.onCompleted: _syncPositionRef(wantsPosition)
    Component.onDestruction: _syncPositionRef(false)

    function _syncPositionRef(wanted) {
        if (wanted === _positionHeld)
            return;
        _positionHeld = wanted;
        if (wanted) {
            MprisController.addPositionRef();
            return;
        }
        MprisController.removePositionRef();
    }
    activeFocusOnTab: canSeek
    Accessible.role: Accessible.Slider
    Accessible.name: I18n.tr("Playback position", "media seekbar accessible name")
    Accessible.focusable: canSeek
    Accessible.onIncreaseAction: seekBy(5)
    Accessible.onDecreaseAction: seekBy(-5)

    function seekTo(position) {
        if (!canSeek)
            return;
        const clamped = Math.max(0.1, Math.min(position, stableLength * 0.99));
        activePlayer.position = clamped;
        beginCommittedSeekPreview(clamped);
    }

    function seekBy(seconds) {
        seekTo(value * stableLength + seconds);
    }

    Keys.onPressed: event => {
        if (!canSeek)
            return;
        switch (event.key) {
        case Qt.Key_Left:
            seekBy(-5);
            break;
        case Qt.Key_Right:
            seekBy(5);
            break;
        case Qt.Key_PageUp:
            seekBy(stableLength / 10);
            break;
        case Qt.Key_PageDown:
            seekBy(-stableLength / 10);
            break;
        case Qt.Key_Home:
            seekTo(0);
            break;
        case Qt.Key_End:
            seekTo(stableLength);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    FocusRing {
        radius: Theme.cornerRadiusXS + Theme.focusRingOffset
        visible: root.activeFocus
        border.color: root.focusRingColor
    }
    property color accentColor: Theme.primary
    property color focusRingColor: Theme.focusRingColor
    property color accentTrackColor: Theme.withAlpha(accentColor, 0.28)
    property color accentSubtleColor: Theme.withAlpha(accentColor, 0.55)
    // Disabled, the bar takes Material's disabled colours like the controls around it.
    readonly property color shownAccent: enabled ? accentColor : Theme.onSurface_38
    readonly property color shownTrack: enabled ? accentTrackColor : Theme.onSurface_12

    property real waveLineWidth: 2
    property real waveAmplitude: 1.6
    property real wavelength: 20
    // The round handle keeps half its size from the ends, so the track maps onto the span between them.
    property bool showHandle: false
    property real handleSize: 0
    property real handleDragWidth: 0
    property real handleDragHeight: 0
    property real handleGap: 0
    readonly property real handleInset: showHandle ? handleSize / 2 : 0
    readonly property real handleTravel: Math.max(1, width - handleInset * 2)
    property real handleWidth: isSeeking ? handleDragWidth : handleSize
    property real handleHeight: isSeeking ? handleDragHeight : handleSize

    Behavior on handleWidth {
        enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Behavior on handleHeight {
        enabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    property real seekPreviewRatio: -1
    readonly property real playerValue: {
        if (!activePlayer || stableLength <= 0)
            return 0;
        const pos = activePlayer.position || 0;
        const calculatedRatio = pos / stableLength;
        return Math.max(0, Math.min(1, calculatedRatio));
    }
    property real value: seekPreviewRatio >= 0 ? seekPreviewRatio : playerValue
    property bool isSeeking: false
    property bool isDraggingSeek: false
    property real committedSeekRatio: -1
    property int previewSettleChecksRemaining: 0
    property real dragThreshold: 4
    property int holdIndicatorDelay: 180

    function clampRatio(ratio) {
        return Math.max(0, Math.min(1, ratio));
    }

    function trackValue(ratio) {
        return width > 0 ? (handleInset + ratio * handleTravel) / width : ratio;
    }

    function ratioForPosition(position) {
        if (!activePlayer || stableLength <= 0)
            return 0;
        return clampRatio(position / stableLength);
    }

    function positionForRatio(ratio) {
        if (!activePlayer || stableLength <= 0)
            return 0;
        const rawPosition = clampRatio(ratio) * stableLength;
        return Math.min(rawPosition, stableLength * 0.99);
    }

    function updatePreviewFromMouse(mouseX, width) {
        if (!activePlayer || stableLength <= 0 || width <= 0)
            return;
        seekPreviewRatio = clampRatio((mouseX - handleInset) / handleTravel);
    }

    function clearCommittedSeekPreview() {
        previewSettleTimer.stop();
        committedSeekRatio = -1;
        previewSettleChecksRemaining = 0;
        if (!isSeeking)
            seekPreviewRatio = -1;
    }

    function beginCommittedSeekPreview(position) {
        seekPreviewRatio = ratioForPosition(position);
        committedSeekRatio = seekPreviewRatio;
        previewSettleChecksRemaining = 15;
        previewSettleTimer.restart();
    }

    function handleSeekPressed(mouse, width, mouseArea, holdTimer) {
        isSeeking = true;
        isDraggingSeek = false;
        mouseArea.pressX = mouse.x;
        clearCommittedSeekPreview();
        holdTimer.restart();
        if (activePlayer && stableLength > 0 && activePlayer.canSeek) {
            updatePreviewFromMouse(mouse.x, width);
            mouseArea.pendingSeekPosition = positionForRatio(seekPreviewRatio);
        }
    }

    function handleSeekReleased(mouseArea, holdTimer) {
        holdTimer.stop();
        isSeeking = false;
        isDraggingSeek = false;
        if (mouseArea.pendingSeekPosition >= 0 && activePlayer && activePlayer.canSeek && stableLength > 0) {
            const clamped = Math.min(mouseArea.pendingSeekPosition, stableLength * 0.99);
            activePlayer.position = Math.max(0.1, clamped);
            mouseArea.pendingSeekPosition = -1;
            beginCommittedSeekPreview(clamped);
        } else {
            seekPreviewRatio = -1;
        }
    }

    function handleSeekPositionChanged(mouse, width, mouseArea) {
        if (mouseArea.pressed && isSeeking && activePlayer && stableLength > 0 && activePlayer.canSeek) {
            if (!isDraggingSeek && Math.abs(mouse.x - mouseArea.pressX) >= dragThreshold)
                isDraggingSeek = true;
            updatePreviewFromMouse(mouse.x, width);
            mouseArea.pendingSeekPosition = positionForRatio(seekPreviewRatio);
        }
    }

    function handleSeekCanceled(mouseArea, holdTimer) {
        holdTimer.stop();
        isSeeking = false;
        isDraggingSeek = false;
        mouseArea.pendingSeekPosition = -1;
        clearCommittedSeekPreview();
    }

    Timer {
        id: previewSettleTimer
        interval: 80
        repeat: true
        onTriggered: {
            if (root.isSeeking || root.committedSeekRatio < 0) {
                stop();
                return;
            }

            const previewSettled = Math.abs(root.playerValue - root.committedSeekRatio) <= 0.0015;
            if (previewSettled || root.previewSettleChecksRemaining <= 0) {
                root.clearCommittedSeekPreview();
                return;
            }

            root.previewSettleChecksRemaining -= 1;
        }
    }

    implicitHeight: 20

    Loader {
        anchors.fill: parent
        visible: activePlayer && stableLength > 0
        sourceComponent: MediaOptions.waveProgress ? waveProgressComponent : flatProgressComponent
        z: 1

        Component {
            id: waveProgressComponent

            M3WaveProgress {
                value: root.trackValue(root.value)
                actualValue: root.trackValue(root.playerValue)
                showActualPlaybackState: root.isSeeking
                lineWidth: root.waveLineWidth
                amp: root.waveAmplitude
                wavelength: root.wavelength
                showHandle: root.showHandle
                handleWidth: root.handleWidth
                handleHeight: root.handleHeight
                handleGap: root.handleGap
                handleColor: root.shownAccent
                fillColor: root.shownAccent
                playheadColor: root.shownAccent
                trackColor: root.shownTrack
                actualProgressColor: root.accentSubtleColor
                isPlaying: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing
                onFrameTicked: {
                    if (!root.isSeeking)
                        MprisController.refreshPosition(activePlayer);
                }

                MouseArea {
                    id: waveMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: activePlayer && activePlayer.canSeek && stableLength > 0

                    property real pendingSeekPosition: -1
                    property real pressX: 0

                    Timer {
                        id: waveHoldIndicatorTimer
                        interval: root.holdIndicatorDelay
                        repeat: false
                        onTriggered: {
                            if (parent.pressed && root.isSeeking)
                                root.isDraggingSeek = true;
                        }
                    }

                    onPressed: mouse => root.handleSeekPressed(mouse, parent.width, waveMouseArea, waveHoldIndicatorTimer)
                    onReleased: root.handleSeekReleased(waveMouseArea, waveHoldIndicatorTimer)
                    onPositionChanged: mouse => root.handleSeekPositionChanged(mouse, parent.width, waveMouseArea)
                    onCanceled: root.handleSeekCanceled(waveMouseArea, waveHoldIndicatorTimer)
                }
            }
        }

        Component {
            id: flatProgressComponent

            Item {
                id: flatBar

                property real lineWidth: root.showHandle ? root.waveLineWidth : 3
                property color trackColor: root.showHandle ? root.shownTrack : Theme.withAlpha(Theme.surfaceVariant, 0.40)
                property color fillColor: root.shownAccent
                property color playheadColor: root.shownAccent
                property color actualProgressColor: Theme.onSurface_38
                readonly property real midY: height / 2
                readonly property real handleX: root.trackValue(root.value) * width

                Rectangle {
                    x: root.showHandle ? flatBar.handleX + root.handleWidth / 2 + root.handleGap : 0
                    width: Math.max(0, parent.width - x)
                    height: parent.lineWidth
                    anchors.verticalCenter: parent.verticalCenter
                    color: parent.trackColor
                    radius: Theme.fullRadius(width, height)
                }

                Rectangle {
                    width: Math.max(0, Math.min(parent.width, root.showHandle ? flatBar.handleX : parent.width * root.value))
                    height: parent.lineWidth
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: parent.fillColor
                    radius: Theme.fullRadius(width, height)
                }

                Rectangle {
                    visible: root.showHandle
                    x: flatBar.handleX - width / 2
                    y: parent.midY - height / 2
                    width: root.handleWidth
                    height: root.handleHeight
                    radius: Theme.fullRadius(width, height)
                    color: parent.fillColor
                    z: 3
                }

                Rectangle {
                    visible: root.isDraggingSeek && !root.showHandle
                    width: 2
                    height: Math.max(parent.lineWidth + 4, 10)
                    radius: Theme.fullRadius(width, height)
                    color: parent.actualProgressColor
                    x: Math.max(0, Math.min(parent.width, parent.width * root.playerValue)) - width / 2
                    y: parent.midY - height / 2
                    z: 2
                }

                Rectangle {
                    id: playhead
                    visible: !root.showHandle
                    width: 3
                    height: Math.max(parent.lineWidth + 8, 14)
                    radius: Theme.fullRadius(width, height)
                    color: parent.playheadColor
                    x: Math.max(0, Math.min(parent.width, parent.width * root.value)) - width / 2
                    y: parent.midY - height / 2
                    z: 3
                }

                MouseArea {
                    id: flatMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: activePlayer && activePlayer.canSeek && stableLength > 0

                    property real pendingSeekPosition: -1
                    property real pressX: 0

                    Timer {
                        id: flatHoldIndicatorTimer
                        interval: root.holdIndicatorDelay
                        repeat: false
                        onTriggered: {
                            if (parent.pressed && root.isSeeking)
                                root.isDraggingSeek = true;
                        }
                    }

                    onPressed: mouse => root.handleSeekPressed(mouse, parent.width, flatMouseArea, flatHoldIndicatorTimer)
                    onReleased: root.handleSeekReleased(flatMouseArea, flatHoldIndicatorTimer)
                    onPositionChanged: mouse => root.handleSeekPositionChanged(mouse, parent.width, flatMouseArea)
                    onCanceled: root.handleSeekCanceled(flatMouseArea, flatHoldIndicatorTimer)
                }
            }
        }
    }
}
