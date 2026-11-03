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
        if (wheel.phase === Qt.ScrollEnd)
            gestureActive = false;
        if (!scrollEnabled || actionInProgress)
            return;

        const delta = WheelInput.dominantDelta(wheel.angleDelta);
        if (delta === 0)
            return;
        const isTouchpad = WheelInput.isTouchpad(wheel);
        if (horizontalGesture(wheel, isTouchpad)) {
            if (xBehavior !== "none")
                accumulateX(isTouchpad, delta, xBehavior);
            return;
        }
        if (yBehavior === "none")
            return;
        accumulateY(isTouchpad, delta, yBehavior);
    }

    onWheel: wheel => processWheel(wheel)
}
