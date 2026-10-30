import QtQuick
import "../../../Common/IslandKit.js" as Kit
import "../../../Common/IslandClock.js" as Clock

// A Timer, not a FrameAnimation: it starts no animation driver, so no other window redraws. The image cadence lives
// here too because it counts the very refreshes these ticks add.
QtObject {
    id: clock

    property bool running: false
    // The screen's refresh: dt and the tick interval are counted in its periods.
    property real refresh: Kit.fallbackHz
    signal tick(real dt)

    readonly property real hz: Clock.clockRate(clock.refresh)
    readonly property real period: 1 / clock.hz
    readonly property int every: Clock.clockEvery(clock.hz)
    property real _last: 0
    property real _ticks: 0
    property int _frames: 0
    property int _held: 0
    property real _drawnAt: 0

    onRunningChanged: {
        clock._last = Date.now();
        clock.resetCadence();
    }

    // Starts the decor's cadence over: its next image is due as soon as it moved (a decor played again).
    function resetCadence() {
        clock._ticks = 0;
    }

    function framesFor(speed: real): int {
        return Clock.framesHeld(clock.hz, speed, clock._frames, clock._held, Date.now() - clock._drawnAt);
    }

    // Counts the image it allows: ask once per tick.
    function due(frames: int, moved: real): bool {
        if (!Kit.cadenceDue(clock._ticks, frames, moved))
            return false;
        clock._held = frames === clock._frames ? clock._held + 1 : 0;
        clock._frames = frames;
        clock._drawnAt = Date.now();
        clock._ticks = Kit.cadenceCarry(clock._ticks, frames);
        return true;
    }

    readonly property Timer timer: Timer {
        running: clock.running
        repeat: true
        interval: Math.round(1000 * clock.every * clock.period)
        onTriggered: {
            const now = Date.now();
            const dt = Clock.clockStep(clock.period, (now - clock._last) / 1000);
            clock._last = now;
            clock._ticks += dt * clock.hz;
            clock.tick(dt);
        }
    }
}
