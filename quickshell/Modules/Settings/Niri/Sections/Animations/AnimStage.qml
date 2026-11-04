import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import "../../../../../Common/niri/anim.js" as Anim

// A sample window moved by one niri animation; it only moves while play() runs, then rests at the end state.
Rectangle {
    id: root

    property var anim: null
    property string effect: "open"
    property real slowdown: 1
    property bool animationsOn: true
    property real windowWidth: 0.52
    property real windowHeight: 0.64

    readonly property var samples: anim ? Anim.samples(anim) : [1]
    readonly property int last: samples.length - 1
    property real elapsed: 0
    readonly property real progress: playing ? samples[Math.min(last, Math.floor(elapsed))] ?? 1 : 1
    readonly property bool playing: player.running
    readonly property int markIndex: playing ? Math.min(last, Math.floor(elapsed)) : -1
    // Reduce motion, or DMS animations set to none: show the end state only
    readonly property bool still: !animationsOn || SettingsData.reduceMotion || Theme.currentAnimationBaseDuration <= 0
    readonly property bool shown: visible && (Window.window?.visible ?? false)

    readonly property real p: progress
    readonly property real sx: effect === "open" || effect === "resize" ? 0.6 + 0.4 * p : effect === "close" ? 1 - 0.4 * p : 1
    readonly property real sy: effect === "open" ? 0.6 + 0.4 * p : effect === "close" ? 1 - 0.4 * p : 1

    function play() {
        player.stop();
        if (still || !shown)
            return;
        player.restart();
    }

    onShownChanged: {
        if (!shown)
            player.complete();
    }

    radius: Theme.cornerRadiusS
    color: SettingsMetrics.controlColor
    clip: true

    NumberAnimation {
        id: player
        target: root
        property: "elapsed"
        from: 0
        to: root.last
        duration: Math.max(1, root.last * root.slowdown)
    }

    Rectangle {
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: parent.width * root.windowWidth
        height: parent.height * root.windowHeight
        // Also the end state of a close: the place the window left
        radius: Theme.cornerRadiusS
        color: "transparent"
        border.width: Theme.outlineWidth
        border.color: Theme.outline
        opacity: Theme.pendingOpacity
    }

    Rectangle {
        id: win

        x: (parent.width - width) / 2 + (root.effect === "h" ? (1 - root.p) * -0.8 * width : 0)
        y: (parent.height - height) / 2 + (root.effect === "v" ? (1 - root.p) * 1.1 * height : 0)
        width: parent.width * root.windowWidth
        height: parent.height * root.windowHeight
        radius: Theme.cornerRadiusS
        color: Theme.surfaceContainerHighest
        border.width: Theme.outlineWidthFocused
        border.color: Theme.primary
        opacity: root.effect === "open" ? Math.max(0, Math.min(1, root.p)) : root.effect === "close" ? Math.max(0, Math.min(1, 1 - root.p)) : 1

        transform: Scale {
            origin.x: win.width / 2
            origin.y: win.height / 2
            xScale: root.sx
            yScale: root.sy
        }
    }
}
