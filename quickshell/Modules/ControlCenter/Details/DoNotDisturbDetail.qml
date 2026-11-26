pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Widgets
import "../../../Common/Format.js" as Format

CcTimedModeDetail {
    title: I18n.tr("Do not disturb")
    active: SessionData.doNotDisturb
    untilMs: SessionData.doNotDisturbUntil
    iconName: SessionData.doNotDisturb ? "do_not_disturb_on" : "notifications_paused"
    toggleText: I18n.tr("Silence notifications")
    offDescription: I18n.tr("Pick how long to pause notifications")
    presets: [
        {
            "label": I18n.tr("%1 min", "short duration chip, %1 is a number of minutes").arg(15),
            "minutes": 15
        },
        {
            "label": I18n.tr("%1 min", "short duration chip, %1 is a number of minutes").arg(30),
            "minutes": 30
        },
        {
            "label": I18n.duration(3600),
            "minutes": 60
        },
        {
            "label": I18n.duration(10800),
            "minutes": 180
        },
        {
            "label": I18n.duration(28800),
            "minutes": 480
        },
        {
            "label": I18n.tr("Until 8 AM"),
            "minutesFn": true
        },
        {
            "label": I18n.tr("Until I turn it off"),
            "icon": "block",
            "minutes": 0
        }
    ]

    onToggled: checked => SessionData.setDoNotDisturb(checked, 0)
    onPresetSelected: preset => {
        const minutes = preset.minutesFn ? Format.minutesUntilTomorrowMorning() : preset.minutes;
        SessionData.setDoNotDisturb(true, minutes);
    }
}
