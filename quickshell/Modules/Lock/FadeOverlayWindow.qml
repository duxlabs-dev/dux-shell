pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
    id: root

    property bool active: false
    property bool _completed: false
    property bool fadeEnabled: true
    property int gracePeriod: 5
    property int fadeDurationMs: gracePeriod * 1000
    property color overlayColor: "black"
    property bool holdsAfterCompletion: false

    signal fadeCompleted
    signal fadeCancelled

    visible: active
    color: "transparent"

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    Rectangle {
        id: fadeOverlay
        anchors.fill: parent
        color: root.overlayColor
        opacity: 0

        onOpacityChanged: {
            if (opacity >= 0.99 && root.active && !root._completed) {
                root._completed = true;
                root.fadeCompleted();
            }
        }
    }

    SequentialAnimation {
        id: fadeSeq
        running: false

        NumberAnimation {
            target: fadeOverlay
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: root.fadeDurationMs
            easing.type: Easing.OutCubic
        }
    }

    function startFade() {
        if (!fadeEnabled)
            return;
        _completed = false;
        active = true;
        fadeOverlay.opacity = 0.0;
        fadeSeq.stop();
        fadeSeq.start();
    }

    function cancelFade() {
        if (holdsAfterCompletion && _completed)
            return;
        dismiss();
        fadeCancelled();
    }

    function dismiss() {
        fadeSeq.stop();
        fadeOverlay.opacity = 0.0;
        active = false;
        _completed = false;
    }

    readonly property bool idleShellLocked: IdleService.isShellLocked

    onIdleShellLockedChanged: {
        if (idleShellLocked)
            return;
        if (holdsAfterCompletion && !_completed)
            return;
        dismiss();
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.active
        onClicked: root.cancelFade()
        onPressed: root.cancelFade()
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: root.active

        Keys.onPressed: event => {
            root.cancelFade();
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        if (active)
            keyScope.forceActiveFocus();
    }

    onActiveChanged: {
        if (active)
            keyScope.forceActiveFocus();
    }
}
