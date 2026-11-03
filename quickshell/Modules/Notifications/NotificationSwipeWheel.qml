import QtQuick
import "../../DCommon/Common/WheelInput.js" as WheelInput
import "../../DCommon/Widgets/ScrollConstants.js" as Scroll

WheelHandler {
    id: handler

    property real travel: 0
    property real drift: 0
    property bool engaged: false
    property real lastTime: 0
    property var samples: []
    readonly property Timer settle: Timer {
        interval: NotificationMetrics.swipeWheelSettleMs
        onTriggered: handler.finish()
    }

    signal began
    signal moved(real travel)
    signal ended(real velocity)

    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    orientation: Qt.Horizontal
    blocking: false
    target: null

    function velocity() {
        if (samples.length < 2)
            return 0;
        const span = samples[samples.length - 1].time - samples[0].time;
        if (span <= 0)
            return 0;
        const total = samples.reduce((sum, s) => sum + s.delta, 0);
        return Math.max(-Scroll.maxMomentumVelocity, Math.min(Scroll.maxMomentumVelocity, total / span * 1000));
    }

    function finish() {
        settle.stop();
        const lifted = Date.now() - lastTime < Scroll.velocitySampleWindowMs;
        const fling = lifted ? velocity() : 0;
        travel = 0;
        drift = 0;
        samples = [];
        if (!engaged)
            return;
        engaged = false;
        ended(fling);
    }

    onWheel: event => {
        if (!WheelInput.isTouchpad(event))
            return;
        const now = Date.now();
        // Qt Wayland negates finger deltas; natural scrolling flips them back and reports inverted
        const delta = (event.inverted ? event.pixelDelta.x : -event.pixelDelta.x) * Scroll.touchpadSpeed;
        travel += delta;
        drift += event.pixelDelta.y * Scroll.touchpadSpeed;
        samples = samples.filter(s => now - s.time < Scroll.velocitySampleWindowMs).concat({
            "delta": delta,
            "time": now
        });
        lastTime = now;
        settle.restart();
        if (!engaged) {
            if (Math.abs(travel) < NotificationMetrics.swipeWheelEngageDistance || Math.abs(travel) <= Math.abs(drift))
                return;
            engaged = true;
            began();
        }
        moved(travel);
    }

    onActiveChanged: {
        if (!active)
            finish();
    }
}
