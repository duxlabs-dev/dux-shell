pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import "../../../Common/IslandArrival.js" as Arrival
import "../../../Common/IslandKit.js" as Kit

// Page dots (a burst in the island, the infos waiting behind a bubble). Five at most, the row slides and the
// dots at a hidden end shrink; the shown page's dot is long and, with a countdown, fills (UIPageControlTimerProgress).
Item {
    id: root

    property int count: 0
    property int index: 0
    // IslandArrival countdown state, or null for plain dots.
    property var countdown: null
    property bool reducedMotion: false
    signal picked(int index)

    readonly property real dot: Theme.spacingXS + Theme.spacingXXS
    readonly property real gap: Theme.spacingXS
    readonly property real longDot: root.countdown ? Theme.spacingL + Theme.spacingXS : Theme.spacingM + Theme.spacingXXS
    readonly property var layout: Arrival.pager(root.count, root.index)
    readonly property int beat: root.reducedMotion ? 0 : Kit.beat("pop", Theme.currentAnimationBaseDuration)
    // A new page's dot pops in from this share of its size, overshooting on the way (OutBack).
    readonly property real popFrom: 0.4
    property real fill: 0
    // An inactive dot, the text tone at this opacity: 3:1 on the island's surface (3.8:1 on a light theme, 5:1 on a dark
    // one), as a mark the eye must find.
    readonly property real dotAlpha: 0.55
    // The countdown's [fill, track alpha]: 3:1 off each other and off every island ground (IslandKit.countdownTones).
    readonly property var countdownTones: Kit.countdownTones(Theme, Theme.isLightMode)

    // Each page's share of the row's pointer target is DMS's touch target, wide and tall: the target is the row stretched
    // by targetStretch from its right end, so it reaches over the header's free band, never over a right-hand neighbour
    // (a card's close button). island arrival next|prev and each dot's press action do the same from the keyboard.
    readonly property real pageTarget: Theme.minimumTouchTargetSize
    readonly property real targetStretch: Math.max(1, root.pageTarget / (root.dot + root.gap))
    readonly property real targetWidth: row.width * root.targetStretch + 2 * root.gap

    // The page a click at x (in the pager) picks, read back onto the row, or -1.
    function pageAt(x: real): int {
        return root.nearest(row.width + (x - row.x - row.width) / root.targetStretch);
    }

    // The dot nearest to x (in the row), or -1 for the shown page's or a gone one.
    function nearest(x: real): int {
        let best = -1;
        let far = Infinity;
        for (let i = 0; i < root.count; i++) {
            const cell = dots.itemAt(i);
            if (!cell || (root.layout.dots[i] ?? "gone") === "gone")
                continue;
            const d = Math.abs(cell.x + cell.width / 2 - x);
            if (d < far) {
                far = d;
                best = i;
            }
        }
        return best >= 0 && root.layout.dots[best] !== "on" ? best : -1;
    }

    implicitHeight: root.dot
    implicitWidth: row.width + 2 * root.gap

    // Steps of half a pixel of the dot at most, and nothing ticks once it is full, or empty and frozen.
    function sample() {
        if (!root.countdown) {
            root.fill = 0;
            return false;
        }
        const now = Date.now();
        root.fill = Arrival.shown(root.fill, Arrival.fill(root.countdown, now), root.longDot);
        return Arrival.ticking(root.countdown, now) && root.fill < 1;
    }
    onCountdownChanged: ticker.running = root.visible && root.sample()
    onVisibleChanged: ticker.running = root.visible && root.sample()

    // One step a quantum (half a pixel of the dot), timed from the countdown (IslandArrival.stepMs): no image is asked
    // between two steps.
    Timer {
        id: ticker

        repeat: true
        interval: root.countdown ? Arrival.stepMs(root.countdown, root.longDot) : 1000
        onTriggered: {
            if (!root.sample())
                ticker.stop();
        }
    }

    property int lastCount: 0
    onCountChanged: {
        if (root.count > root.lastCount && root.lastCount > 0 && root.beat > 0)
            popIn.restart();
        root.lastCount = root.count;
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 0

        Repeater {
            id: dots

            model: root.count

            Item {
                id: cell

                required property int index
                readonly property string kind: root.layout.dots[cell.index] ?? "gone"
                readonly property bool on: cell.kind === "on"
                readonly property bool gone: cell.kind === "gone"
                readonly property real size: cell.kind === "edge" ? root.dot - Theme.spacingXXS : root.dot

                width: cell.gone ? 0 : (cell.on ? root.longDot : cell.size) + root.gap
                height: root.dot
                opacity: cell.gone ? 0 : 1
                scale: cell.index === root.count - 1 ? popIn.scale : 1

                Behavior on width {
                    NumberAnimation {
                        duration: root.beat
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    id: track

                    anchors.centerIn: parent
                    width: parent.width - root.gap
                    height: cell.size
                    radius: height / 2
                    color: !cell.on ? Theme.withAlpha(Theme.surfaceText, root.dotAlpha) : !root.countdown ? Theme.primary : Theme.withAlpha(root.countdownTones[0], root.countdownTones[1])

                    Rectangle {
                        visible: cell.on && !!root.countdown
                        width: track.width * root.fill
                        height: parent.height
                        radius: parent.radius
                        color: root.countdownTones[0]
                    }
                }

                // Its page for a screen reader; the pointer goes through the row's own target.
                Item {
                    anchors.fill: parent
                    visible: !cell.gone && !cell.on
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr("Page %1 of %2", "island card pager: one dot, the page it shows").arg(cell.index + 1).arg(root.count)
                    Accessible.onPressAction: root.picked(cell.index)
                }
            }
        }
    }

    // One pointer target for the row, DMS's touch target tall and targetWidth wide (dots a few pixels apart could not each
    // have one without overlapping): a click picks the nearest dot.
    MouseArea {
        anchors.right: row.right
        anchors.rightMargin: -root.gap
        anchors.verticalCenter: row.verticalCenter
        width: root.targetWidth
        height: Math.max(row.height, Theme.minimumTouchTargetSize)
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            const i = root.pageAt(mapToItem(root, mouse.x, 0).x);
            if (i >= 0)
                root.picked(i);
        }
    }

    QtObject {
        id: popIn

        property real scale: 1

        function restart() {
            anim.restart();
        }

        property NumberAnimation anim: NumberAnimation {
            target: popIn
            property: "scale"
            from: root.popFrom
            to: 1
            duration: root.beat
            easing.type: Easing.OutBack
        }
    }
}
