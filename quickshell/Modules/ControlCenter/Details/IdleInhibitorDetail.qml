pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter.Widgets
import qs.Services

CcTimedModeDetail {
    title: I18n.tr("Keep Awake")
    active: SessionService.idleInhibited
    untilMs: SessionData.idleInhibitedUntil
    iconName: "local_cafe"
    toggleText: I18n.tr("Prevent screen timeout")
    offDescription: I18n.tr("Pick how long to stay awake", "idle inhibitor detail subtitle shown while keep awake is off")
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
            "label": I18n.duration(7200),
            "minutes": 120
        },
        {
            "label": I18n.duration(14400),
            "minutes": 240
        },
        {
            "label": I18n.duration(28800),
            "minutes": 480
        },
        {
            "label": I18n.tr("Until I turn it off"),
            "icon": "block",
            "minutes": 0
        }
    ]

    onToggled: checked => checked ? SessionService.enableIdleInhibit(0) : SessionService.disableIdleInhibit()
    onPresetSelected: preset => SessionService.enableIdleInhibit(preset.minutes)

    CcGroup {
        visible: SessionService.loginctlAvailable

        CcToggleRow {
            iconName: "laptop"
            text: I18n.tr("Stay awake with the lid closed", "keep awake option that also blocks suspend on lid close")
            checked: SettingsData.keepAwakeBlocksSleep
            onToggled: checked => SettingsData.set("keepAwakeBlocksSleep", checked)
        }
    }
}
