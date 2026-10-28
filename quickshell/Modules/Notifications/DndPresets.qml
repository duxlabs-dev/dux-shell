pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import "../../Common/Format.js" as Format

Singleton {
    readonly property bool active: SessionData.doNotDisturb
    readonly property string status: SessionData.doNotDisturbUntil > 0 ? I18n.tr("until %1", "lowercase, follows the remaining time after a separator, %1 is a clock time").arg(Format.formatUntil(SessionData.doNotDisturbUntil, SettingsData.use24HourClock)) : I18n.tr("Until I turn it off")

    function minutesUntilTomorrowMorning() {
        const now = new Date();
        const target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 8, 0, 0, 0);
        return Math.max(1, Math.round((target.getTime() - now.getTime()) / 60000));
    }

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
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(10800)),
            "minutes": 180
        },
        {
            "label": I18n.tr("For %1", "timed preset menu option, %1 is a duration such as 15 minutes").arg(I18n.duration(28800)),
            "minutes": 480
        },
        {
            "label": I18n.tr("Until tomorrow, 8:00 AM"),
            "minutesFn": true
        },
        {
            "label": I18n.tr("Until I turn it off"),
            "minutes": 0
        }
    ]

    function selectPreset(option) {
        if (!option)
            return;
        const minutes = option.minutesFn ? minutesUntilTomorrowMorning() : option.minutes;
        SessionData.setDoNotDisturb(true, minutes);
    }

    function turnOff() {
        SessionData.setDoNotDisturb(false);
    }
}
