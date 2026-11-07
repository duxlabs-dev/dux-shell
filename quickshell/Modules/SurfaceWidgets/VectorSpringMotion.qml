pragma ComponentBehavior: Bound

import QtQuick
import "../../Common/FrameCadence.js" as FrameCadence

QtObject {
    id: root

    property bool enabled: true
    property bool running: false
    property bool reducedMotion: false

    property real stiffness: 560
    property real damping: 37
    property real mass: 1
    property real positionEpsilon: 0.035
    property real velocityEpsilon: 0.035
    property real maximumFrameTime: 1 / 30
    property real integrationStep: 1 / 240
    property int maximumSubsteps: 256
    readonly property real timeConstantMs: reducedMotion ? 0 : 2000 * mass / Math.max(1, damping)

    property real currentWidth: 176
    property real currentHeight: 42
    property real currentOffsetAlong: 0
    property real currentOffsetCross: 8
    property real currentTopLeftRadius: 21
    property real currentTopRightRadius: 21
    property real currentBottomLeftRadius: 21
    property real currentBottomRightRadius: 21

    property real targetWidth: currentWidth
    property real targetHeight: currentHeight
    property real targetOffsetAlong: currentOffsetAlong
    property real targetOffsetCross: currentOffsetCross
    property real targetTopLeftRadius: currentTopLeftRadius
    property real targetTopRightRadius: currentTopRightRadius
    property real targetBottomLeftRadius: currentBottomLeftRadius
    property real targetBottomRightRadius: currentBottomRightRadius

    property real velocityWidth: 0
    property real velocityHeight: 0
    property real velocityOffsetAlong: 0
    property real velocityOffsetCross: 0
    property real velocityTopLeftRadius: 0
    property real velocityTopRightRadius: 0
    property real velocityBottomLeftRadius: 0
    property real velocityBottomRightRadius: 0
    // Seconds of frames above 120 a second, folded into the next step (FrameCadence.fold).
    property real _foldedTime: 0
    // One frame's integrated [current, velocity] for each of the eight axes, made once so advance() allocates nothing per
    // frame.
    readonly property var _frame: new Float64Array(2 * 8)

    // One per integration step, so consumers copy the body once instead of binding to eight currents.
    signal stepped()

    function matchesTarget(target) {
        return targetWidth === target.width && targetHeight === target.height && targetOffsetAlong === target.offsetAlong && targetOffsetCross === target.offsetCross && targetTopLeftRadius === target.topLeftRadius && targetTopRightRadius === target.topRightRadius && targetBottomLeftRadius === target.bottomLeftRadius && targetBottomRightRadius === target.bottomRightRadius;
    }

    function setTarget(target, seedVelocity) {
        if (matchesTarget(target) && !seedVelocity)
            return;
        targetWidth = target.width;
        targetHeight = target.height;
        targetOffsetAlong = target.offsetAlong;
        targetOffsetCross = target.offsetCross;
        targetTopLeftRadius = target.topLeftRadius;
        targetTopRightRadius = target.topRightRadius;
        targetBottomLeftRadius = target.bottomLeftRadius;
        targetBottomRightRadius = target.bottomRightRadius;

        if (seedVelocity) {
            velocityOffsetAlong = seedVelocity.offsetAlong ?? velocityOffsetAlong;
            velocityOffsetCross = seedVelocity.offsetCross ?? velocityOffsetCross;
        }

        if (reducedMotion) {
            settle();
            return;
        }

        if (!isSettled())
            running = true;
    }

    function snapTo(target) {
        targetWidth = target.width;
        targetHeight = target.height;
        targetOffsetAlong = target.offsetAlong;
        targetOffsetCross = target.offsetCross;
        targetTopLeftRadius = target.topLeftRadius;
        targetTopRightRadius = target.topRightRadius;
        targetBottomLeftRadius = target.bottomLeftRadius;
        targetBottomRightRadius = target.bottomRightRadius;

        currentWidth = target.width;
        currentHeight = target.height;
        currentOffsetAlong = target.offsetAlong;
        currentOffsetCross = target.offsetCross;
        currentTopLeftRadius = target.topLeftRadius;
        currentTopRightRadius = target.topRightRadius;
        currentBottomLeftRadius = target.bottomLeftRadius;
        currentBottomRightRadius = target.bottomRightRadius;

        velocityWidth = 0;
        velocityHeight = 0;
        velocityOffsetAlong = 0;
        velocityOffsetCross = 0;
        velocityTopLeftRadius = 0;
        velocityTopRightRadius = 0;
        velocityBottomLeftRadius = 0;
        velocityBottomRightRadius = 0;
        running = false;
        stepped();
    }

    function isSettled() {
        const positionSettled = Math.abs(targetWidth - currentWidth) <= positionEpsilon && Math.abs(targetHeight - currentHeight) <= positionEpsilon && Math.abs(targetOffsetAlong - currentOffsetAlong) <= positionEpsilon && Math.abs(targetOffsetCross - currentOffsetCross) <= positionEpsilon && Math.abs(targetTopLeftRadius - currentTopLeftRadius) <= positionEpsilon && Math.abs(targetTopRightRadius - currentTopRightRadius) <= positionEpsilon && Math.abs(targetBottomLeftRadius - currentBottomLeftRadius) <= positionEpsilon && Math.abs(targetBottomRightRadius - currentBottomRightRadius) <= positionEpsilon;
        const velocitySettled = Math.abs(velocityWidth) <= velocityEpsilon && Math.abs(velocityHeight) <= velocityEpsilon && Math.abs(velocityOffsetAlong) <= velocityEpsilon && Math.abs(velocityOffsetCross) <= velocityEpsilon && Math.abs(velocityTopLeftRadius) <= velocityEpsilon && Math.abs(velocityTopRightRadius) <= velocityEpsilon && Math.abs(velocityBottomLeftRadius) <= velocityEpsilon && Math.abs(velocityBottomRightRadius) <= velocityEpsilon;
        return positionSettled && velocitySettled;
    }

    function settle() {
        currentWidth = targetWidth;
        currentHeight = targetHeight;
        currentOffsetAlong = targetOffsetAlong;
        currentOffsetCross = targetOffsetCross;
        currentTopLeftRadius = targetTopLeftRadius;
        currentTopRightRadius = targetTopRightRadius;
        currentBottomLeftRadius = targetBottomLeftRadius;
        currentBottomRightRadius = targetBottomRightRadius;

        velocityWidth = 0;
        velocityHeight = 0;
        velocityOffsetAlong = 0;
        velocityOffsetCross = 0;
        velocityTopLeftRadius = 0;
        velocityTopRightRadius = 0;
        velocityBottomLeftRadius = 0;
        velocityBottomRightRadius = 0;
        running = false;
        stepped();
    }

    function _integrate(axis, target, x, v, steps, step, inverseMass) {
        const k = stiffness;
        const c = damping;
        for (let i = 0; i < steps; i++) {
            v += (k * (target - x) - c * v) * inverseMass * step;
            x += v * step;
        }
        _frame[2 * axis] = x;
        _frame[2 * axis + 1] = v;
    }

    function advance(rawFrameTime) {
        if (!enabled || !running || reducedMotion)
            return;

        const frameTime = Math.min(Math.max(rawFrameTime, 0), maximumFrameTime);
        if (frameTime <= 0)
            return;

        const inverseMass = 1 / Math.max(0.001, mass);
        // Short animation speeds scale stiffness by 1/f², so shrink the step until explicit Euler stays stable.
        const stableStep = 1 / Math.max(1, damping * inverseMass, Math.sqrt(stiffness * inverseMass));
        const steps = Math.min(maximumSubsteps, Math.max(1, Math.ceil(frameTime / Math.min(integrationStep, stableStep))));
        const step = frameTime / steps;

        // The axes are independent: each is integrated in plain locals, then all are written once per frame (no array
        // per frame), since every property write re-runs its bindings.
        _integrate(0, targetWidth, currentWidth, velocityWidth, steps, step, inverseMass);
        _integrate(1, targetHeight, currentHeight, velocityHeight, steps, step, inverseMass);
        _integrate(2, targetOffsetAlong, currentOffsetAlong, velocityOffsetAlong, steps, step, inverseMass);
        _integrate(3, targetOffsetCross, currentOffsetCross, velocityOffsetCross, steps, step, inverseMass);
        _integrate(4, targetTopLeftRadius, currentTopLeftRadius, velocityTopLeftRadius, steps, step, inverseMass);
        _integrate(5, targetTopRightRadius, currentTopRightRadius, velocityTopRightRadius, steps, step, inverseMass);
        _integrate(6, targetBottomLeftRadius, currentBottomLeftRadius, velocityBottomLeftRadius, steps, step, inverseMass);
        _integrate(7, targetBottomRightRadius, currentBottomRightRadius, velocityBottomRightRadius, steps, step, inverseMass);
        if (!_frame.every(Number.isFinite)) {
            settle();
            return;
        }

        const f = _frame;
        velocityWidth = f[1];
        velocityHeight = f[3];
        velocityOffsetAlong = f[5];
        velocityOffsetCross = f[7];
        velocityTopLeftRadius = f[9];
        velocityTopRightRadius = f[11];
        velocityBottomLeftRadius = f[13];
        velocityBottomRightRadius = f[15];
        currentWidth = f[0];
        currentHeight = f[2];
        currentOffsetAlong = f[4];
        currentOffsetCross = f[6];
        currentTopLeftRadius = f[8];
        currentTopRightRadius = f[10];
        currentBottomLeftRadius = f[12];
        currentBottomRightRadius = f[14];

        if (isSettled())
            settle();
        else
            stepped();
    }

    onEnabledChanged: {
        if (!enabled) settle();
    }

    onReducedMotionChanged: {
        if (reducedMotion)
            settle();
    }

    property FrameAnimation frameAnimation: FrameAnimation {
        running: root.enabled && root.running && !root.reducedMotion
        onRunningChanged: root._foldedTime = 0
        onTriggered: root._onFrame(frameTime)
    }

    // One screen frame through the fold: steps the spring (advance) at most 120 times a second, with the time folded.
    function _onFrame(frameTime) {
        const time = FrameCadence.fold(_foldedTime, frameTime);
        _foldedTime = Math.max(0, -time);
        if (time > 0)
            advance(time);
    }
}
