import QtQuick
import qs.Common

Item {
    id: root

    required property int index
    property NotificationSwipeGroup group: null
    property real bleed: 0
    property bool dismissing: false
    property int dismissDirection: 1
    property real topRoundness: roundness(true)
    property real bottomRoundness: roundness(false)
    readonly property real offset: motion.value
    readonly property real contentOpacity: 1 - Math.min(1, Math.abs(motion.value) / Math.max(1, width * NotificationMetrics.swipeContentFadeEnd))
    readonly property bool magnetActive: group !== null && group.row !== null
    readonly property bool magnetDetached: group !== null && group.detached
    readonly property real magnetTranslation: group ? group.translation : 0

    signal dismissed

    function slot(values, distance) {
        const i = distance + (values.length - 1) / 2;
        return i >= 0 && i < values.length ? values[i] : 0;
    }

    function roundness(top) {
        if (dismissing)
            return 1;
        if (!group?.row)
            return 0;
        const distance = index - group.row.index;
        if (group.detached)
            return distance === 0 || distance === (top ? 1 : -1) ? 1 : 0;
        const reach = (NotificationMetrics.swipeRoundness.length - 1) / 2;
        if (distance === (top ? -reach : reach))
            return 0;
        const pull = Math.abs(slot(NotificationMetrics.swipePull, 0) * group.translation) / NotificationMetrics.swipeDetachDistance;
        return slot(NotificationMetrics.swipeRoundness, distance) * Math.min(NotificationMetrics.swipePullRoundnessMax, pull);
    }

    function magnetTarget() {
        if (!group?.row)
            return 0;
        const distance = index - group.row.index;
        if (group.detached)
            return distance === 0 ? group.translation : 0;
        return slot(NotificationMetrics.swipePull, distance) * group.translation;
    }

    function springTo(spring, target) {
        if (dismissing)
            return;
        motion.stiffness = spring.stiffness;
        motion.damping = spring.damping;
        motion.retarget(target);
    }

    function release(velocity = 0) {
        if (group?.row !== root)
            return;
        const projected = group.translation + velocity * NotificationMetrics.swipeFlingProjectionMs / 1000;
        if (Math.abs(projected) > width * NotificationMetrics.swipeThreshold) {
            dismissing = true;
            dismissDirection = projected > 0 ? 1 : -1;
            motion.snapTo(motion.value);
            dismissAnimation.to = dismissDirection * (width + bleed);
            dismissAnimation.start();
        }
        group.end(root);
    }

    onMagnetTranslationChanged: {
        if (dismissing)
            return;
        if (motion.running) {
            motion.retarget(magnetTarget());
            return;
        }
        motion.snapTo(magnetTarget());
    }

    onMagnetDetachedChanged: {
        if (!group?.row)
            return;
        if (!group.detached) {
            springTo(NotificationMetrics.swipeAttachSpring, magnetTarget());
            return;
        }
        springTo(group.row === root ? NotificationMetrics.swipeDetachSpring : NotificationMetrics.swipeSnapSpring, magnetTarget());
    }

    onMagnetActiveChanged: {
        if (magnetActive)
            return;
        springTo(NotificationMetrics.swipeSnapSpring, 0);
    }

    Component.onDestruction: group?.end(root)

    Behavior on topRoundness {
        enabled: NotificationMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    Behavior on bottomRoundness {
        enabled: NotificationMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }
    }

    SpringMotion {
        id: motion
        reducedMotion: !NotificationMetrics.animationsEnabled
    }

    NumberAnimation {
        id: dismissAnimation
        target: motion
        property: "value"
        duration: NotificationMetrics.animationsEnabled ? Theme.notificationExitDuration : 0
        easing.type: Easing.BezierSpline
        easing.bezierCurve: NotificationMetrics.dismissCurve
        onFinished: root.dismissed()
    }

    DragHandler {
        target: null
        yAxis.enabled: false
        enabled: root.group !== null && !root.dismissing
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
        onActiveChanged: {
            if (active) {
                root.group.begin(root);
                return;
            }
            root.release();
        }
        onTranslationChanged: root.group?.drag(root, translation.x)
    }

    NotificationSwipeWheel {
        enabled: root.group !== null && !root.dismissing
        onBegan: root.group.begin(root)
        onMoved: travel => root.group?.drag(root, travel)
        onEnded: velocity => root.release(velocity)
    }
}
