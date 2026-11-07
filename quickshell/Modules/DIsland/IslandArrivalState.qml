import QtQuick
import qs.Common
import qs.Modules.Notifications
import "../../Common/IslandActivities.js" as Activities
import "../../Common/IslandArrival.js" as Arrival
import "../../Common/IslandArrivalGestures.js" as Gestures
import "../../Common/IslandKit.js" as IslandKit

// Arrival of infos (IslandArrival.js), IslandController's arrival: the island swells as an info arrives, opens its card
// a while (the burst: infos rolling over each other, a countdown dot each), then folds to compact until its time is up.
QtObject {
    id: root

    required property var controller
    property bool reducedMotion: false
    readonly property string style: SettingsData.islandArrivalStyle
    property var burst: Arrival.emptyBurst()
    readonly property var current: root.burst.items[root.burst.index] ?? null
    readonly property int count: root.burst.items.length
    readonly property int topTier: Arrival.topTier(root.burst.items)
    // Bumped each time the shown info changes, so the source can follow it.
    property int shown: 0
    // rest | big (the card) | compact (folded, until the notification's time is up)
    property string phase: "rest"
    property var pulse: null
    property bool swelling: false
    // Bumped per tint flash (tint its strength) and per small bounce of a newcomer rolling in (nudges).
    property int flashes: 0
    property real tint: 0
    property int nudges: 0
    property var countdown: Arrival.freezeEmpty(Arrival.countdown(0, 0), 0, 0)
    property bool dragging: false
    property bool focused: false
    readonly property bool held: root.phase === "big" && (root.controller.pointerInside || root.dragging || root.focused || root.controller.expanded)
    // The finger's pull on the island's height while it drags up or down.
    property real pull: 0
    property var wheelState: Gestures.wheelIdle()
    readonly property bool browsable: root.phase === "big" && !root.controller.expanded && root.count > 1
    // Infos of a burst that ended: they leave the island for the notification list.
    signal released(var items)

    readonly property real dampingRatio: root.phase !== "rest" || root.swelling ? (root.pulse?.ratio ?? 0) : 0
    readonly property int drainMs: IslandKit.beat("drain", root.reducedMotion ? 0 : Theme.currentAnimationBaseDuration)
    readonly property real cardWidth: Math.min(NotificationMetrics.popupWidth, Math.max(NotificationMetrics.popupMinWidth, root.controller.dashboardAvailableWidth * NotificationMetrics.popupScreenRatio)) + (root.topTier >= 2 ? Theme.spacingL * 2 : 0)
    readonly property real cardHeight: NotificationMetrics.cardPadding * 2 + NotificationMetrics.appIconSize + (root.current?.action ? Theme.spacingS + Theme.buttonHeightS : 0) + (root.topTier >= 2 ? Theme.spacingM : 0)
    readonly property var bigTarget: {
        const radius = Math.min(root.cardHeight / 2, NotificationMetrics.popupRadius);
        return Object.assign(root.controller.pillTarget(root.cardWidth, root.cardHeight), root.controller.cardRadii(radius));
    }
    readonly property bool cardShown: root.phase === "big" && root.controller.notificationActive && !root.controller.isVertical

    function pulseFor(tier, card) {
        return Arrival.pulse(root.style, tier, card === true && !root.controller.isVertical, SettingsData.islandArrivalBounce, SettingsData.islandArrivalTint, root.reducedMotion);
    }

    // The compact target as an arrival shapes it: the card, a swell, the finger's pull.
    function shape(target) {
        if (root.controller.activeActivity === "notification" && root.cardShown)
            return root.pulled(root.bigTarget);
        if ((root.swelling && root.pulse) || root.faceHoverSwell)
            return root.pulled(Arrival.swollen(target, (root.swelling && root.pulse ? root.pulse : root.faceSwellPulse).swell, root.controller.compactFaceThickness, root.controller.isVertical));
        return root.pulled(target);
    }

    // The finger's pull on the island's height: up toward the clock, down toward the full card.
    function pulled(target) {
        if (root.pull === 0 || root.controller.isVertical || !root.controller.notificationActive)
            return target;
        return Object.assign({}, target, {
            "height": Math.max(root.controller.compactFaceThickness / 2, Math.min(Math.max(target.height, root.controller.notificationExpandedTarget.height), target.height + root.pull))
        });
    }

    // Pulled down: the info stays open and grows into its full card (actions, quick reply), with no countdown; only a
    // gesture closes it (pushed up, Escape, a click elsewhere), even once the pointer has left.
    function open() {
        if (!root.controller.notificationActive || root.controller.expanded || root.controller.inputSuspended)
            return false;
        root.pull = 0;
        root.controller.hoverExpanded = false;
        root.controller.hoverCloseTimer.stop();
        root.controller.notificationTimer.stop();
        root.controller.keyboardDismissRequested = true;
        root.controller.expanded = true;
        return true;
    }

    function setBurst(next) {
        const changed = next.items[next.index] !== root.burst.items[root.burst.index];
        root.burst = next;
        if (changed)
            root.shown++;
    }

    function flash(amount) {
        if (amount <= 0 || root.reducedMotion)
            return;
        root.tint = amount;
        root.flashes++;
    }

    function swell(pulse) {
        root.pulse = pulse;
        root.swelling = pulse.swell[0] > 0 || pulse.swell[1] > 0;
        root.swellTimer.interval = pulse.holdMs;
        if (root.swelling)
            root.swellTimer.restart();
    }

    function startCountdown() {
        const t = Date.now();
        // A page lives as long as its info is big (a brief one in a burst gets a notification's, to be read).
        const hold = Activities.bigMs(Math.max(Activities.tiers.normal, root.current?.tier ?? Activities.tiers.normal));
        // A ringing call stays big, with no countdown, until it is answered, refused or stops.
        const ringing = !Arrival.expires(root.current);
        root.countdown = root.held || ringing ? Arrival.freezeEmpty(Arrival.countdown(hold, t), t, ringing ? 0 : root.drainMs) : Arrival.countdown(hold, t);
        root.countdownTimer.stop();
        if (!root.held && !ringing) {
            root.countdownTimer.interval = Math.max(1, Arrival.remaining(root.countdown, t));
            root.countdownTimer.start();
        }
    }

    // The swell a face took on arrival, and whose: hovered once folded, that face swells again.
    property var faceSwellPulse: null
    property string faceSwellOwner: ""
    readonly property string faceOwner: root.controller.activeActivity === "plugin" ? root.controller.pluginToken : root.controller.activeActivity
    readonly property bool faceHoverSwell: !!root.faceSwellPulse && Gestures.hoverSwell({
        "hovered": root.controller.pointerInside,
        "owner": root.faceSwellOwner,
        "face": root.faceOwner,
        "notification": root.controller.notificationActive,
        "expanded": root.controller.expanded,
        "vertical": root.controller.isVertical
    })

    // A face that takes the island (system, plugin) only swells: it has no card.
    function face(tier) {
        if (root.phase !== "rest")
            return;
        const pulse = root.pulseFor(tier, false);
        root.faceSwellPulse = pulse;
        root.faceSwellOwner = root.faceOwner;
        root.swell(pulse);
        root.flash(pulse.tint);
    }

    // item: {tier, app, title, detail, image, icon, fallbackText, action, critical, wrapper?, timeout}.
    function arrive(item) {
        const first = root.phase === "rest";
        const held = !first && root.held;
        root.setBurst(Arrival.arrive(root.burst, item, held));
        if (held) {
            // The info being read keeps its place: one more dot, which pops in.
            root.flash((root.pulseFor(item.tier, true).tint) * 0.3);
            return;
        }
        const pulse = root.pulseFor(item.tier, true);
        const big = root.pulseFor(Math.max(item.tier, root.topTier), true);
        root.flash(first ? pulse.tint : pulse.tint * 0.6);
        if (pulse.big || (!first && big.big && root.phase === "big")) {
            root.pulse = big;
            root.swelling = false;
            root.swellTimer.stop();
            if (!first)
                root.nudges++;
            root.phase = "big";
            root.controller.notificationTimer.stop();
            root.startCountdown();
            return;
        }
        root.phase = "compact";
        root.swell(pulse);
        root.controller.syncNotificationTimeout(true);
    }

    function go(index) {
        if (root.phase !== "big")
            return false;
        const next = Arrival.go(root.burst, index);
        if (!next)
            return false;
        root.setBurst(next);
        root.startCountdown();
        return true;
    }

    function step(direction) {
        return root.browsable && root.go(root.burst.index + direction);
    }

    function countdownDone() {
        if (root.phase !== "big" || root.held)
            return;
        const next = Arrival.afterCountdown(root.burst);
        if (next) {
            root.setBurst(next);
            root.startCountdown();
            return;
        }
        root.phase = "compact";
        root.countdown = Arrival.freezeEmpty(root.countdown, Date.now(), 0);
        root.controller.syncNotificationTimeout(true);
    }

    // Hovered or pulled down once folded: the card opens again, its dot empty and still while held. A style without a
    // card refuses, or the island would grow to the card's size with nothing in it.
    function reopen() {
        if (root.phase !== "compact" || root.count === 0 || !root.controller.notificationActive || root.controller.expanded || root.controller.isVertical)
            return false;
        const card = root.pulseFor(Math.max(1, root.topTier), true);
        if (!card.big)
            return false;
        root.swelling = false;
        root.swellTimer.stop();
        if (!root.pulse?.big)
            root.pulse = card;
        root.phase = "big";
        root.controller.notificationTimer.stop();
        root.startCountdown();
        return true;
    }

    // Pushed up: straight back to the clock, every info to the notification list.
    function tidy() {
        if (!root.controller.notificationActive)
            return false;
        return root.controller.completeNotification();
    }

    function end() {
        if (root.phase === "rest" && root.count === 0)
            return;
        // Released while still in the burst, so a source never takes them back in as new.
        root.released(root.burst.items);
        root.countdownTimer.stop();
        root.swellTimer.stop();
        root.swelling = false;
        root.phase = "rest";
        root.pull = 0;
        root.burst = Arrival.emptyBurst();
        root.shown++;
    }

    // The wheel or a touchpad over the open card turns its pages; false leaves the wheel to the island.
    function wheel(delta) {
        if (!root.browsable || !SettingsData.islandArrivalWheel)
            return false;
        root.wheelState = Gestures.wheel(root.wheelState, SettingsData.islandArrivalWheelInverted ? -delta : delta, Date.now());
        if (root.wheelState.step !== 0)
            root.step(root.wheelState.step);
        return true;
    }

    // A drag let go: sideways turns the page, toward the screen edge tidies away, away from it reopens.
    function swipe(dx, dy) {
        root.pull = 0;
        return Gestures.runArrival(root, Gestures.swipe(dx, dy, undefined, root.controller.farEdge)) === true;
    }

    // The read info goes (dismissed, acted on): the next one shows, or the island goes back to the clock.
    function drop() {
        const next = Arrival.drop(root.burst);
        if (!next)
            return root.controller.completeNotification();
        root.setBurst(next);
        if (root.phase === "big")
            root.startCountdown();
        return true;
    }

    // A burst lives as long as its notification face, or while a system face holds it.
    readonly property bool alive: root.controller.notificationActive || root.controller.notificationHeldForSystem
    onAliveChanged: {
        if (!root.alive)
            root.end();
    }

    onHeldChanged: {
        const t = Date.now();
        if (root.held) {
            root.countdownTimer.stop();
            root.countdown = Arrival.freeze(root.countdown, t, root.drainMs);
            return;
        }
        if (root.phase === "big")
            root.startCountdown();
    }

    property Timer countdownTimer: Timer {
        onTriggered: root.countdownDone()
    }

    property Timer swellTimer: Timer {
        onTriggered: {
            root.swelling = false;
            root.controller.syncNotificationTimeout(true);
        }
    }
}
