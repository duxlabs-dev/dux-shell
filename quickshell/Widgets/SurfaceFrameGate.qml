import QtQuick

// Reports the first frame the surface commits after each show, so a host reveals onto a rendered buffer.
Item {
    id: root

    required property bool surfaceVisible
    property bool ready: false

    onSurfaceVisibleChanged: {
        if (!surfaceVisible)
            ready = false;
    }

    Connections {
        target: root.Window.window
        enabled: root.surfaceVisible && !root.ready

        function onFrameSwapped() {
            root.ready = true;
        }
    }
}
