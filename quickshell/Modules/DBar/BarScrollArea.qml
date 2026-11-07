pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../DCommon/Common/WheelInput.js" as WheelInput

MouseArea {
    id: root

    property bool scrollEnabled: true
    property string xBehavior: "focusWindow"
    property string yBehavior: "workspace"
    property string screenName: ""
    property var screen: null
    property var barConfig: null
    property real touchpadAccumulatorX: 0
    property real touchpadAccumulatorY: 0
    property real mouseAccumulatorX: 0
    property real mouseAccumulatorY: 0
    property bool actionInProgress: false
    property bool gestureActive: false
    property bool gestureHorizontal: false

    signal workspaceSwitchRequested(int direction)

    acceptedButtons: Qt.NoButton

    Timer {
        id: cooldownTimer
        interval: 100
        onTriggered: root.actionInProgress = false
    }

    function isLevelBehavior(behavior) {
        return behavior === "volume" || behavior === "brightness";
    }

    function handleLevelAction(behavior, step, direction) {
        switch (behavior) {
        case "volume":
            if (!AudioService.sink?.audio)
                return false;
            AudioService.adjustDefaultSinkVolume(step, direction);
            return true;
        case "brightness":
            return BrightnessService.adjustScreenBrightness(root.screen ?? root.screenName, step, direction);
        default:
            return false;
        }
    }

    function handleScrollAction(behavior, direction) {
        switch (behavior) {
        case "workspace":
            workspaceSwitchRequested(direction);
            return true;
        case "focusWindow":
            return CompositorService.stepWindowFocus(screenName, direction);
        default:
            return false;
        }
    }

    function fire(accumulated, behavior) {
        const reverse = SettingsData.widgetOption("workspaceSwitcher", SettingsData.barWidgetEntry(root.barConfig, "workspaceSwitcher"), "reverseScrolling") ? -1 : 1;
        const direction = accumulated * reverse < 0 ? 1 : -1;
        if (!handleScrollAction(behavior, direction))
            return;
        actionInProgress = true;
        cooldownTimer.restart();
    }

    function stepLevelAccumulator(accumulated, delta, threshold) {
        const base = (accumulated * delta) < 0 ? 0 : accumulated;
        const next = base + delta;
        const units = Math.trunc(Math.abs(next) / threshold);
        if (units <= 0)
            return {
                remainder: next,
                units: 0,
                sign: 0
            };
        const sign = next > 0 ? 1 : -1;
        return {
            remainder: next - sign * units * threshold,
            units: units,
            sign: sign
        };
    }

    function levelStepAmount(behavior, isTouchpad, units) {
        if (isTouchpad)
            return units;
        const perNotch = behavior === "volume" ? Math.max(1, AudioService.wheelVolumeStep) : 5;
        return perNotch * units;
    }

    function accumulateLevelX(wheel, isTouchpad, delta, behavior) {
        if (isTouchpad) {
            if (wheel.phase === Qt.ScrollBegin)
                touchpadAccumulatorX = 0;
            const res = stepLevelAccumulator(touchpadAccumulatorX, delta, 100);
            touchpadAccumulatorX = res.remainder;
            if (res.units > 0)
                handleLevelAction(behavior, levelStepAmount(behavior, true, res.units), res.sign);
            return;
        }
        const res = stepLevelAccumulator(mouseAccumulatorX, delta, 120);
        mouseAccumulatorX = res.remainder;
        if (res.units > 0)
            handleLevelAction(behavior, levelStepAmount(behavior, false, res.units), res.sign);
    }

    function accumulateLevelY(wheel, isTouchpad, delta, behavior) {
        if (isTouchpad) {
            if (wheel.phase === Qt.ScrollBegin)
                touchpadAccumulatorY = 0;
            const res = stepLevelAccumulator(touchpadAccumulatorY, delta, 100);
            touchpadAccumulatorY = res.remainder;
            if (res.units > 0)
                handleLevelAction(behavior, levelStepAmount(behavior, true, res.units), res.sign);
            return;
        }
        const res = stepLevelAccumulator(mouseAccumulatorY, delta, 120);
        mouseAccumulatorY = res.remainder;
        if (res.units > 0)
            handleLevelAction(behavior, levelStepAmount(behavior, false, res.units), res.sign);
    }

    function accumulateX(isTouchpad, delta, behavior) {
        if (isTouchpad) {
            touchpadAccumulatorX += delta;
            if (Math.abs(touchpadAccumulatorX) < 500)
                return;
            fire(touchpadAccumulatorX, behavior);
            touchpadAccumulatorX = 0;
            return;
        }
        mouseAccumulatorX += delta;
        if (Math.abs(mouseAccumulatorX) < 120)
            return;
        fire(mouseAccumulatorX, behavior);
        mouseAccumulatorX = 0;
    }

    function accumulateY(isTouchpad, delta, behavior) {
        if (isTouchpad) {
            touchpadAccumulatorY += delta;
            if (Math.abs(touchpadAccumulatorY) < 500)
                return;
            fire(touchpadAccumulatorY, behavior);
            touchpadAccumulatorY = 0;
            return;
        }
        mouseAccumulatorY += delta;
        if (Math.abs(mouseAccumulatorY) < 120)
            return;
        fire(mouseAccumulatorY, behavior);
        mouseAccumulatorY = 0;
    }

    function horizontalGesture(wheel, isTouchpad) {
        if (!isTouchpad)
            return WheelInput.isHorizontal(wheel);
        if (!gestureActive || wheel.phase === Qt.ScrollBegin)
            gestureHorizontal = WheelInput.isHorizontal(wheel);
        gestureActive = true;
        return gestureHorizontal;
    }

    function processWheel(wheel) {
        wheel.accepted = false;
        if (wheel.phase === Qt.ScrollEnd) {
            gestureActive = false;
            touchpadAccumulatorX = 0;
            touchpadAccumulatorY = 0;
        }
        if (!scrollEnabled)
            return;

        const delta = WheelInput.dominantDelta(wheel.angleDelta);
        if (delta === 0)
            return;
        const isTouchpad = WheelInput.isTouchpad(wheel);
        if (horizontalGesture(wheel, isTouchpad)) {
            if (xBehavior === "none")
                return;
            if (isLevelBehavior(xBehavior)) {
                accumulateLevelX(wheel, isTouchpad, delta, xBehavior);
            } else if (!actionInProgress) {
                accumulateX(isTouchpad, delta, xBehavior);
            }
            return;
        }
        if (yBehavior === "none")
            return;
        if (isLevelBehavior(yBehavior)) {
            accumulateLevelY(wheel, isTouchpad, delta, yBehavior);
            return;
        }
        if (!actionInProgress)
            accumulateY(isTouchpad, delta, yBehavior);
    }

    onWheel: wheel => processWheel(wheel)
}
