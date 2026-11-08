pragma ComponentBehavior: Bound

import QtQuick
import qs.DCommon.Common as DC

QtObject {
    id: root

    property bool enabled: true
    property bool reducedMotion: false
    property bool running: false
    property real stiffness: 220
    property real damping: 23
    property real mass: 1
    property real positionEpsilon: 0.035
    property real velocityEpsilon: 0.035

    property rect value: Qt.rect(0, 0, 1, 1)
    property rect target: value
    property vector4d velocity: Qt.vector4d(0, 0, 0, 0)

    readonly property real timeConstantMs: 2000 * mass / Math.max(1, damping)
    property int settleDurationMs: 0

    function snapTo(rect, initialVelocity) {
        target = rect;
        velocity = initialVelocity ?? Qt.vector4d(0, 0, 0, 0);
        value = rect;
        running = false;
    }

    function retarget(rect) {
        if (!enabled || reducedMotion) {
            snapTo(rect);
            return;
        }
        target = rect;
        if (isSettled(value, velocity)) {
            snapTo(rect);
            return;
        }
        const distance = Math.max(Math.abs(target.x - value.x), Math.abs(target.y - value.y), Math.abs(target.width - value.width), Math.abs(target.height - value.height));
        const speed = Math.max(Math.abs(velocity.x), Math.abs(velocity.y), Math.abs(velocity.z), Math.abs(velocity.w));
        const amplitude = distance + speed * timeConstantMs / 1000;
        settleDurationMs = Math.round(Math.max(timeConstantMs * 3, timeConstantMs * Math.log(Math.max(amplitude, positionEpsilon) / positionEpsilon)));
        running = true;
    }

    function isSettled(rect, speed) {
        return Math.abs(target.x - rect.x) <= positionEpsilon && Math.abs(target.y - rect.y) <= positionEpsilon && Math.abs(target.width - rect.width) <= positionEpsilon && Math.abs(target.height - rect.height) <= positionEpsilon && Math.abs(speed.x) <= velocityEpsilon && Math.abs(speed.y) <= velocityEpsilon && Math.abs(speed.z) <= velocityEpsilon && Math.abs(speed.w) <= velocityEpsilon;
    }

    function advance(rawFrameTime) {
        if (!enabled || !running || reducedMotion)
            return;
        if (rawFrameTime <= 0)
            return;
        const matrix = DC.SpringSolver.coefficients(stiffness, damping, mass, rawFrameTime);
        const dx = value.x - target.x;
        const dy = value.y - target.y;
        const dw = value.width - target.width;
        const dh = value.height - target.height;
        const x = target.x + matrix[0] * dx + matrix[1] * velocity.x;
        const y = target.y + matrix[0] * dy + matrix[1] * velocity.y;
        const w = target.width + matrix[0] * dw + matrix[1] * velocity.z;
        const h = target.height + matrix[0] * dh + matrix[1] * velocity.w;
        const vx = matrix[2] * dx + matrix[3] * velocity.x;
        const vy = matrix[2] * dy + matrix[3] * velocity.y;
        const vw = matrix[2] * dw + matrix[3] * velocity.z;
        const vh = matrix[2] * dh + matrix[3] * velocity.w;

        const next = Qt.rect(x, y, Math.max(1, w), Math.max(1, h));
        const speed = Qt.vector4d(vx, vy, w < 1 ? 0 : vw, h < 1 ? 0 : vh);
        if (isSettled(next, speed)) {
            snapTo(target);
            return;
        }
        velocity = speed;
        value = next;
    }

    onReducedMotionChanged: {
        if (reducedMotion)
            snapTo(target);
    }

    onEnabledChanged: {
        if (!enabled)
            snapTo(target);
    }

    property FrameAnimation driver: FrameAnimation {
        running: root.enabled && root.running && !root.reducedMotion
        onTriggered: root.advance(frameTime)
    }
}
