import QtQuick
import "../../Common/IslandActivities.js" as Activities
import "../../Common/IslandArrival.js" as Arrival

// A plugin activity's turn in the island: begin and end write the controller's state as requestSystemActivity does;
// requestCollapse only resets returnExpanded and calls syncTimeout() here.
QtObject {
    id: root

    required property var controller
    // Set by the host: the plugin's own faces, else the shell-drawn face (readyFace), and its system face, if any.
    property var activity: null
    property var face: null
    property var systemFace: null
    // Set by the content host while the plugin's face is on screen, its fade out included.
    property bool shown: false
    property int timeoutMs: 0
    property string returnActivity: ""
    property bool returnExpanded: false
    readonly property bool active: root.controller.pluginActive
    readonly property bool suspended: root.controller.timeoutSuspended
    readonly property bool holdsHost: Activities.holdsHost(root.controller.transientActive, root.active, root.timeoutMs, root.arrivalHold.running)

    // A face handed back by a notification or an OSD arrives again and restarts its countdown; an open sheet holds the
    // countdown as a hover does.
    onActiveChanged: {
        root.arrivalHold.running = root.active;
        root.syncTimeout(true);
    }
    onSuspendedChanged: root.syncTimeout(!root.suspended)

    function syncTimeout(restart) {
        if (!Activities.countdownRuns(root.active, root.suspended, root.timeoutMs)) {
            root.timer.stop();
            return;
        }
        if (restart === true || !root.timer.running)
            root.timer.restart();
    }

    function begin(token, kind, expand, timeoutMs) {
        const island = root.controller;
        if (!island.pluginActive) {
            root.returnActivity = island.activeActivity;
            root.returnExpanded = island.expanded;
        }
        island.clearPendingRequests("");
        island.launcherSessionActive = false;
        island.hoverExpanded = false;
        island.hoverOpenTimer.stop();
        island.hoverCloseTimer.stop();
        island.transientTimer.stop();
        island.notificationTimer.stop();
        island.keyboardDismissRequested = false;
        island.pluginKind = kind;
        root.timeoutMs = timeoutMs;
        // The host loads the plugin's faces from the token, so expandability is known only after it is set.
        island.pluginToken = token;
        const displaced = island.systemActivityActive ? island.activeActivity : "";
        const arriving = !island.pluginActive && kind !== "live";
        // A plugin taking over from a plugin keeps activeActivity, so its change handler would leave userHeld set.
        island.userHeld = false;
        // Switch before expanding: the expanded handlers read transientActive.
        island.activeActivity = "plugin";
        island.expanded = expand === true && island.pluginExpandable;
        root.arrivalHold.restart();
        if (arriving && !island.expanded)
            island.arrival.face(Arrival.tierOf({
                "urgent": kind === "alert"
            }));
        root.syncTimeout(true);
        island.displaceSystem(displaced);
    }

    function end() {
        const island = root.controller;
        island.pluginToken = "";
        root.timer.stop();
        if (island.suspendedActivity === "plugin") {
            island.suspendedActivity = island.idleActivity();
            island.suspendedExpanded = false;
        }
        if (island.transientReturnActivity === "plugin")
            island.transientReturnActivity = "";
        const back = root.returnActivity;
        const backExpanded = root.returnExpanded;
        root.returnActivity = "";
        root.returnExpanded = false;
        if (!island.pluginActive)
            return;
        island.expanded = false;
        island.keyboardDismissRequested = false;
        island.activeActivity = island.idleActivity();
        // A sheet the user had open comes back once the activity is done.
        if (backExpanded && island.isDestination(back))
            island.requestActivity(back, true, true);
    }

    property Timer timer: Timer {
        interval: Math.max(1, root.timeoutMs)
        onTriggered: root.controller.pluginDismissed(root.controller.pluginToken, "timeout")
    }

    // Without it, an alert that does not open or a live activity would arrive unseen in a hidden bar.
    property Timer arrivalHold: Timer {
        interval: Activities.glanceTimeoutMs
    }
}
