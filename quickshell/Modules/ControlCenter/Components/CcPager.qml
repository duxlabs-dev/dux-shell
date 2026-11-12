pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Common
import qs.Modules.ControlCenter
import "../../../DCommon/Widgets/ScrollConstants.js" as Scroll

Item {
    id: root

    property int count: 1
    property int currentIndex: 0
    // Instantiated once per page with `required property int index`; the pager owns its x, width and visible.
    property Component delegate: null
    property bool swipeEnabled: true
    // Room beside the pages: a neighbor slides in from past it, and the clip while sliding reaches it.
    property real gutter: 0
    readonly property real stride: width + gutter * 2
    readonly property real position: motion.value
    readonly property bool dragging: swipe.active || touchpadAxis === 1
    readonly property bool moving: dragging || motion.running
    // Every page's item in page order, so a binding over all pages follows them coming and going.
    property list<Item> items: []
    readonly property Item currentItem: items[currentIndex] ?? null

    property real dragBase: 0
    property real dragStartX: 0
    property real dragTravel: 0
    property var dragSamples: []
    property real wheelQuietUntil: 0
    // Locked per touchpad gesture: 0 undecided, 1 pages, -1 left to the vertical scroll around the pager.
    property int touchpadAxis: 0
    property real touchpadBase: 0
    property real touchpadTravel: 0
    property var touchpadSamples: []

    function pageShown(index: int): bool {
        return Math.abs(index - position) < 1;
    }

    function goTo(index, animate = true) {
        const page = Math.max(0, Math.min(count - 1, index));
        currentIndex = page;
        if (animate) {
            motion.retarget(page);
            return;
        }
        motion.snapTo(page);
    }

    function logical(value: real): real {
        return I18n.isRtl ? -value : value;
    }

    function overscrolled(value: real): real {
        const last = Math.max(0, count - 1);
        if (value < 0)
            return value * CcMetrics.pageOverscrollRate;
        if (value > last)
            return last + (value - last) * CcMetrics.pageOverscrollRate;
        return value;
    }

    function follow(base: real, travel: real) {
        motion.snapTo(overscrolled(base - logical(travel) / Math.max(1, stride)));
    }

    function settle(travel: real, distance: real, velocity: real) {
        const flick = Math.abs(velocity) > CcMetrics.pageSwipeVelocity;
        const far = Math.abs(travel) > stride * distance;
        if (!flick && !far) {
            goTo(currentIndex);
            return;
        }
        goTo(currentIndex - Math.sign(logical(flick ? velocity : travel)));
    }

    function sampled(samples: var, travel: real): var {
        const now = Date.now();
        return samples.filter(sample => now - sample.time < Scroll.velocitySampleWindowMs).concat({
            "x": travel,
            "time": now
        });
    }

    function velocityOf(samples: var): real {
        const now = Date.now();
        const recent = samples.filter(sample => now - sample.time < Scroll.velocitySampleWindowMs);
        if (recent.length < 2)
            return 0;
        const span = recent[recent.length - 1].time - recent[0].time;
        return span > 0 ? (recent[recent.length - 1].x - recent[0].x) / span * 1000 : 0;
    }

    function syncPages() {
        while (pageModel.count < count)
            pageModel.append({
                "page": pageModel.count
            });
        while (pageModel.count > Math.max(0, count))
            pageModel.remove(pageModel.count - 1);
    }

    function beginSwipe() {
        dragBase = motion.value;
        dragStartX = swipe.centroid.scenePosition.x;
        dragTravel = 0;
        dragSamples = [];
    }

    function moveSwipe() {
        dragTravel = swipe.centroid.scenePosition.x - dragStartX;
        dragSamples = sampled(dragSamples, dragTravel);
        follow(dragBase, dragTravel);
    }

    function endSwipe() {
        const velocity = velocityOf(dragSamples);
        dragSamples = [];
        settle(dragTravel, CcMetrics.pageSwipeDistance, velocity);
    }

    // Only finger scrolling carries a phase on Wayland, so a phaseless event is a wheel notch.
    function wheelBy(event) {
        if (event.phase !== Qt.NoScrollPhase) {
            touchpadBy(event);
            return;
        }
        if (Math.abs(event.angleDelta.x) <= Math.abs(event.angleDelta.y)) {
            event.accepted = false;
            return;
        }
        const quiet = Date.now() >= wheelQuietUntil;
        wheelQuietUntil = Date.now() + CcMetrics.pageWheelQuietMs;
        if (swipe.active || !quiet)
            return;
        goTo(currentIndex + (event.angleDelta.x > 0 ? -1 : 1) * (I18n.isRtl ? -1 : 1));
    }

    function touchpadBy(event) {
        if (event.phase === Qt.ScrollBegin)
            endTouchpad();
        if (event.phase === Qt.ScrollEnd) {
            event.accepted = touchpadAxis === 1;
            endTouchpad();
            return;
        }
        if (event.phase === Qt.ScrollMomentum) {
            event.accepted = false;
            return;
        }
        if (touchpadAxis === 0) {
            const dx = event.pixelDelta.x;
            const dy = event.pixelDelta.y;
            if (dx === 0 && dy === 0) {
                event.accepted = false;
                return;
            }
            touchpadAxis = Math.abs(dx) > Math.abs(dy) && !swipe.active ? 1 : -1;
            touchpadBase = motion.value;
            touchpadTravel = 0;
            touchpadSamples = [];
        }
        if (touchpadAxis !== 1) {
            event.accepted = false;
            return;
        }
        // Qt Wayland negates finger deltas; natural scrolling flips them back and reports inverted.
        touchpadTravel += (event.inverted ? event.pixelDelta.x : -event.pixelDelta.x) * Scroll.touchpadSpeed;
        touchpadSamples = sampled(touchpadSamples, touchpadTravel);
        follow(touchpadBase, touchpadTravel);
        touchpadLost.restart();
    }

    function endTouchpad() {
        touchpadLost.stop();
        const paging = touchpadAxis === 1;
        touchpadAxis = 0;
        if (!paging)
            return;
        const velocity = velocityOf(touchpadSamples);
        touchpadSamples = [];
        settle(touchpadTravel, CcMetrics.pageWheelDistance, velocity);
    }

    onCountChanged: {
        syncPages();
        if (currentIndex > count - 1)
            goTo(count - 1);
    }

    onCurrentIndexChanged: {
        if (!dragging)
            motion.retarget(currentIndex);
    }

    Component.onCompleted: {
        syncPages();
        motion.snapTo(currentIndex);
    }

    ListModel {
        id: pageModel
    }

    SpringMotion {
        id: motion

        readonly property var spring: Theme.springPreset("defaultSpatial", Theme.currentAnimationBaseDuration)

        enabled: CcMetrics.animationsEnabled
        stiffness: spring.stiffness
        damping: spring.damping
        positionEpsilon: 1 / Math.max(1, root.stride)
        velocityEpsilon: positionEpsilon * damping / (2 * mass)
    }

    // Settles a gesture whose ScrollEnd went elsewhere, so the pager never stays parked between pages.
    Timer {
        id: touchpadLost

        interval: CcMetrics.pageTouchpadLostMs
        onTriggered: root.endTouchpad()
    }

    Item {
        id: viewport

        x: -root.gutter
        y: -root.gutter
        width: root.width + root.gutter * 2
        height: root.height + root.gutter * 2
        // Only while sliding: at rest the other pages are hidden, and a lifted tile or its edit chrome may overhang.
        clip: root.moving

        Item {
            x: root.gutter - Math.round(root.logical(root.position) * root.stride)
            y: root.gutter
            width: root.width
            height: root.height

            Repeater {
                model: pageModel
                delegate: root.delegate
                // Pages only leave from the end, so an index stays its page's index.
                onItemAdded: (index, item) => {
                    item.x = Qt.binding(() => root.logical(index) * root.stride);
                    item.width = Qt.binding(() => root.width);
                    item.visible = Qt.binding(() => root.pageShown(index));
                    const next = Array.from(root.items);
                    next[index] = item;
                    root.items = next;
                }
                onItemRemoved: (index, item) => root.items = Array.from(root.items).filter(other => other !== item)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        // Unset: every MouseArea starts with an arrow cursor, which would cover the tiles' own cursors.
        cursorShape: undefined
        enabled: root.swipeEnabled && root.count > 1
        onWheel: event => root.wheelBy(event)
    }

    DragHandler {
        id: swipe

        property bool verticalLock: false

        target: null
        enabled: root.swipeEnabled && root.count > 1
        acceptedButtons: Qt.LeftButton
        yAxis.enabled: false
        xAxis.enabled: !verticalLock
        // Steals from tile MouseAreas, so the release is no tap; a slider's preventStealing and an edit-mode
        // tile DragHandler that grabbed first both keep their drag.
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.ApprovesCancellation

        onGrabChanged: transition => {
            if (transition === PointerDevice.GrabPassive)
                verticalLock = false;
        }

        onActiveChanged: {
            if (active) {
                root.beginSwipe();
                return;
            }
            root.endSwipe();
        }

        onCentroidChanged: {
            if (active) {
                root.moveSwipe();
                return;
            }
            const dx = centroid.scenePosition.x - centroid.scenePressPosition.x;
            const dy = centroid.scenePosition.y - centroid.scenePressPosition.y;
            if (Math.abs(dy) > dragThreshold && Math.abs(dy) > Math.abs(dx))
                verticalLock = true;
        }
    }
}
