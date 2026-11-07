pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../../Common/IslandKit.js" as Kit

// Rings pushed only while a ring or the swing still moves, so an alert at rest or stopped costs no frame.
Item {
    id: root

    // The shape's diameter the rings leave from, and how many times its size they reach.
    property real base: 0
    property real reach: 2.6
    property int rings: 1
    // Ring arithmetic counts on one ring at least.
    readonly property int ringCount: Math.max(1, root.rings)
    // 0: rings again after each pause until stop(), or until motion is reduced (onStillChanged).
    property int cycles: 1
    property bool ringsShown: true
    property color color: Theme.error
    property real stroke: Theme.outlineWidthFocused * 2
    // The spring the shape swings back on, [stiffness, damping ratio, mass]; none: no swing.
    property var spring: null
    // A ring lasts and weighs twice a slow spatial step, so it reads at the default speed.
    readonly property int span: Theme.expressiveDurations.expressiveSlowSpatial * 2
    readonly property int gap: Kit.beat("ringGap", Theme.currentAnimationBaseDuration)
    readonly property int pause: Kit.beat("ringPause", Theme.currentAnimationBaseDuration)
    readonly property bool still: Theme.currentAnimationBaseDuration <= 0 || SettingsData.reduceMotion
    // The pushed clock (bindings read it at the kit's cadence) and the running one under it.
    property real ms: -1
    property real elapsed: -1
    property real since: 0
    property real swing: 0
    // The screen's refresh (its clock steps by it, and keeps the pushes' cadence).
    readonly property real refresh: root.screenHz || Kit.fallbackHz
    readonly property real screenHz: Kit.screenRefresh(NiriService.outputs, root.Screen.name)
    readonly property bool running: root.elapsed >= 0

    function play() {
        if (root.still)
            return;
        root.elapsed = 0;
        root.since = 0;
        ringClock.resetCadence();
        root.ms = 0;
        root.swing = 0;
    }

    function stop() {
        root.elapsed = -1;
        root.ms = -1;
        root.swing = 0;
    }

    function swingAt(ms: real): real {
        return root.spring ? Kit.ringSwing(ms, root.span, root.gap, root.ringCount, root.pause, root.cycles, root.spring[0], root.spring[1], root.spring[2]) : 0;
    }

    function tipMoved(swing: real): real {
        return Math.abs(swing - root.swing) * Kit.ringTilt * Math.PI / 180 * root.base / 2;
    }

    function ringing(): bool {
        const local = root.elapsed % Kit.ringCycle(root.span, root.gap, root.ringCount, root.pause);
        return local < root.span + (root.ringCount - 1) * root.gap || Kit.ringT(root.ms, root.span, root.gap, root.ringCount, root.pause, root.cycles, root.ringCount - 1) < 1;
    }

    function ringsMoved(): real {
        const c = Theme.expressiveCurves.expressiveEffects;
        let moved = 0;
        for (let i = 0; i < root.ringCount; i++) {
            const from = Kit.bezier(c[0], c[1], c[2], c[3], Kit.ringT(root.ms, root.span, root.gap, root.ringCount, root.pause, root.cycles, i));
            const to = Kit.bezier(c[0], c[1], c[2], c[3], Kit.ringT(root.elapsed, root.span, root.gap, root.ringCount, root.pause, root.cycles, i));
            moved = Math.max(moved, Math.abs(to - from) * (root.width - root.base) / 2);
        }
        return moved;
    }

    width: root.base * root.reach
    height: width

    // play() refuses to start under reduced motion; rings already going stop when it turns on.
    onStillChanged: {
        if (root.still)
            root.stop();
    }

    Repeater {
        model: root.ringCount

        Rectangle {
            id: ring

            required property int index
            readonly property real t: Kit.ringT(root.ms, root.span, root.gap, root.ringCount, root.pause, root.cycles, ring.index)
            readonly property var c: Theme.expressiveCurves.expressiveEffects
            readonly property real eased: Kit.bezier(ring.c[0], ring.c[1], ring.c[2], ring.c[3], ring.t)

            anchors.centerIn: parent
            width: root.base + (root.width - root.base) * ring.eased
            height: ring.width
            radius: ring.width / 2
            color: "transparent"
            border.width: root.stroke
            border.color: Theme.withAlpha(root.color, 1 - ring.eased)
            visible: root.ringsShown && ring.t < 1
        }
    }

    IslandDecorClock {
        id: ringClock

        refresh: root.refresh
        running: root.running && root.visible && (root.Window.window?.visible ?? false)
        onTick: dt => {
            root.elapsed += dt * 1000;
            root.since += dt;
            if (Kit.ringsOver(root.elapsed, root.span, root.gap, root.ringCount, root.pause, root.cycles)) {
                root.stop();
                return;
            }
            const swing = root.swingAt(root.elapsed);
            const tip = root.tipMoved(swing);
            // In the pause, once the last ring is gone and the swing has settled, nothing moves: nothing is pushed.
            const moving = root.ringing() || tip >= Kit.minStepPx;
            if (!ringClock.due(ringClock.framesFor(Math.max(tip, root.ringsMoved()) / root.since), moving ? 1 : 0))
                return;
            root.since = 0;
            root.ms = root.elapsed;
            root.swing = swing;
        }
    }
}
