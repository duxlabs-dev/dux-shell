pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../../../Common/Format.js" as Format

Singleton {
    property real nowMs: Date.now()

    readonly property bool active: SessionService.idleInhibited
    readonly property bool timed: SessionData.idleInhibitedUntil > 0
    readonly property real remainingMs: timed ? Math.max(0, SessionData.idleInhibitedUntil - nowMs) : 0
    readonly property string status: timed ? Format.formatRemaining(remainingMs, I18n.tr("Off"), I18n.tr("%1 min left"), I18n.tr("%1 h left"), I18n.tr("%1 h %2 m left")) + " · " + I18n.tr("until %1", "lowercase, follows the remaining time after a separator, %1 is a clock time").arg(Format.formatUntil(SessionData.idleInhibitedUntil, SettingsData.use24HourClock)) : I18n.tr("On indefinitely")

    readonly property var presetOptions: [
        {
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(900)),
            "minutes": 15
        },
        {
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(1800)),
            "minutes": 30
        },
        {
            "label": I18n.tr("For 1 hour", "timed preset menu option"),
            "minutes": 60
        },
        {
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(7200)),
            "minutes": 120
        },
        {
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(14400)),
            "minutes": 240
        },
        {
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(28800)),
            "minutes": 480
        },
        {
            "label": I18n.tr("Until I turn it off"),
            "minutes": 0
        }
    ]

    function syncNow() {
        nowMs = Date.now();
    }

    function selectPreset(option) {
        if (!option)
            return;
        SessionService.enableIdleInhibit(option.minutes);
    }

    function turnOff() {
        SessionService.disableIdleInhibit();
    }
}
