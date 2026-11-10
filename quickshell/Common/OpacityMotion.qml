pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

QtObject {
    id: root

    property bool enabled: true
    property int duration: Theme.currentAnimationBaseDuration
    property real target: 0
    readonly property real value: Math.max(0, Math.min(1, motion.value))
    readonly property bool running: motion.running
    // Critically damped motion falls under the 0.001 epsilon at omega * t = 9.23, so the fade settles at duration.
    readonly property real omega: 9.23 / Math.max(0.001, duration / 1000)

    onTargetChanged: {
        if (motion)
            motion.retarget(target);
    }
    Component.onCompleted: motion.snapTo(target)

    readonly property SpringMotion motion: SpringMotion {
        enabled: root.enabled
        reducedMotion: root.duration <= 0
        stiffness: root.omega * root.omega
        damping: 2 * root.omega
        positionEpsilon: 0.001
        velocityEpsilon: positionEpsilon * damping / (2 * mass)
    }
}
