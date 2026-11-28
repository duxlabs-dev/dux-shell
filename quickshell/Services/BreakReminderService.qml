pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../Modules/DDash/Wellbeing/Wellbeing.js" as Wellbeing

Singleton {
    id: root

    readonly property int idleTimeoutSeconds: 300
    readonly property int snoozeSeconds: 300
    readonly property int statsApiVersion: 45

    readonly property bool enabled: SettingsData.wellbeingBreaksEnabled
    readonly property bool sessionLocked: IdleService.isShellLocked || SessionService.locked
    readonly property bool sessionActive: !idleMonitor.isIdle && !sessionLocked
    readonly property bool counting: enabled && sessionActive
    readonly property int workSeconds: SettingsData.wellbeingBreakInterval * 60
    readonly property int warningSeconds: SettingsData.wellbeingBreakWarning
    readonly property int breakSeconds: kind === "long" ? SettingsData.wellbeingLongBreakDuration * 60 : SettingsData.wellbeingBreakDuration
    readonly property bool watchesMicrophone: enabled && SettingsData.wellbeingBreakSuppressMeetings
    readonly property bool microphoneActive: watchesMicrophone && PrivacyService.microphoneActive
    readonly property bool breakShown: phase === "break" || previewing
    readonly property bool statsAvailable: WellbeingService.available && DMSService.apiVersion >= statsApiVersion

    property string phase: "idle"
    property string kind: "short"
    property int shortsDone: 0
    property bool previewing: false
    property real breakEndsAt: 0
    property real warningEndsAt: 0
    property var pausedPlayers: []
    property int statsRevision: 0

    signal warningShown
    signal warningDismissed

    IdleMonitor {
        id: idleMonitor
        timeout: root.idleTimeoutSeconds
        respectInhibitors: true
        enabled: root.enabled
    }

    Timer {
        id: phaseTimer
        onTriggered: root.advance()
    }

    Timer {
        id: previewTimer
        onTriggered: root.endPreview()
    }

    // going idle during a break is the point of the break, so only a lock or the setting ends one early
    onCountingChanged: {
        if (phase === "break" && enabled && !sessionLocked)
            return;
        if (counting)
            startWork(workSeconds);
        else
            stop();
    }
    onSessionLockedChanged: {
        if (sessionLocked)
            stop();
    }
    onWorkSecondsChanged: {
        if (phase === "work")
            startWork(workSeconds);
    }
    onWatchesMicrophoneChanged: {
        if (watchesMicrophone)
            PrivacyService.addRef();
        else
            PrivacyService.removeRef();
    }
    onMicrophoneActiveChanged: {
        if (microphoneActive && (phase === "warning" || phase === "break"))
            postpone();
    }

    function suppressed() {
        if (microphoneActive)
            return true;
        return SettingsData.wellbeingBreakSuppressFullscreen && Quickshell.screens.some(screen => CompositorService.fullscreenToplevelOnScreen(screen));
    }

    function wait(seconds) {
        phaseTimer.interval = Math.max(1, seconds) * 1000;
        phaseTimer.restart();
    }

    function stop() {
        const wasBreak = phase === "break";
        phaseTimer.stop();
        phase = "idle";
        warningDismissed();
        if (wasBreak)
            resumeMedia();
    }

    function startWork(seconds) {
        phase = "work";
        warningDismissed();
        wait(seconds - warningSeconds);
    }

    function advance() {
        switch (phase) {
        case "work":
            startWarning();
            return;
        case "warning":
            startBreak();
            return;
        case "break":
            finishBreak("completed");
            return;
        }
    }

    function startWarning() {
        if (suppressed()) {
            postpone();
            return;
        }
        if (warningSeconds <= 0) {
            startBreak();
            return;
        }
        warningEndsAt = Date.now() + warningSeconds * 1000;
        phase = "warning";
        wait(warningSeconds);
        warningShown();
    }

    function startBreak() {
        if (suppressed()) {
            postpone();
            return;
        }
        endPreview();
        breakEndsAt = Date.now() + breakSeconds * 1000;
        phase = "break";
        warningDismissed();
        wait(breakSeconds);
        playSound(true);
        pauseMedia();
    }

    function finishBreak(outcome) {
        logOutcome(outcome);
        if (outcome === "completed")
            playSound(false);
        resumeMedia();
        const next = Wellbeing.nextBreak(kind, shortsDone, SettingsData.wellbeingBreaksBeforeLong);
        kind = next.kind;
        shortsDone = next.shortsDone;
        if (!counting) {
            stop();
            return;
        }
        startWork(workSeconds);
    }

    function postpone() {
        if (phase === "break")
            resumeMedia();
        startWork(snoozeSeconds);
    }

    function skip() {
        if (previewing) {
            endPreview();
            return;
        }
        switch (phase) {
        case "warning":
            logOutcome("skipped");
            startWork(workSeconds);
            return;
        case "break":
            finishBreak("skipped");
            return;
        }
    }

    function snooze() {
        if (previewing) {
            endPreview();
            return;
        }
        if (phase !== "warning" && phase !== "break")
            return;
        logOutcome("snoozed");
        postpone();
    }

    function previewWarning() {
        warningEndsAt = Date.now() + Math.max(1, warningSeconds) * 1000;
        warningShown();
    }

    function previewBreak() {
        if (phase === "break")
            return;
        breakEndsAt = Date.now() + breakSeconds * 1000;
        previewing = true;
        previewTimer.interval = breakSeconds * 1000;
        previewTimer.restart();
    }

    function endPreview() {
        previewTimer.stop();
        previewing = false;
    }

    function playSound(starting) {
        if (!SettingsData.wellbeingBreakSound)
            return;
        if (starting)
            AudioService.playNormalNotificationSound();
        else
            AudioService.playVolumeChangeSound();
    }

    function pauseMedia() {
        if (!SettingsData.wellbeingBreakPauseMedia)
            return;
        const players = MprisController.availablePlayers.filter(player => player.isPlaying && player.canPause);
        for (const player of players)
            player.pause();
        pausedPlayers = players;
    }

    function resumeMedia() {
        const players = pausedPlayers;
        pausedPlayers = [];
        for (const player of players) {
            if (MprisController.availablePlayers.includes(player) && player.canPlay)
                player.play();
        }
    }

    function logOutcome(outcome) {
        if (!statsAvailable)
            return;
        DMSService.sendRequest("wellbeing.logBreak", {
            "outcome": outcome
        }, () => root.statsRevision++);
    }

    function stats(callback) {
        if (!statsAvailable) {
            callback(Wellbeing.breakStats([]));
            return;
        }
        DMSService.sendRequest("wellbeing.breaks", {
            "days": Wellbeing.retentionDays
        }, response => callback(Wellbeing.breakStats(response?.result?.days ?? [])));
    }

    function resetStats() {
        if (!statsAvailable)
            return;
        DMSService.sendRequest("wellbeing.clearBreaks", null, () => root.statsRevision++);
    }
}
