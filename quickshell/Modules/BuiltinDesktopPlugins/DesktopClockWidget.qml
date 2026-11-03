import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets

DClockWidget {
    id: root

    property real widgetWidth: 280
    property real widgetHeight: 200
    property string instanceId: ""
    property var instanceData: null
    property var lockHost: null

    cfg: instanceData?.config ?? ({})
    enabled: instanceData?.enabled ?? true
    now: systemClock.date
    locale: I18n.locale()
    use24HourClock: SettingsData.use24HourClock
    padHours12Hour: SettingsData.padHours12Hour
    showAmPm: SettingsData.showAmPm
    dateFormat: lockScreen ? SettingsData.lockDateFormat : SettingsData.clockDateFormat
    fallbackFontFamily: SettingsData.lockScreenFontFamily
    accentColor: lockHost ? lockHost.contentColor(colorMode, customColor) : themeAccent

    SystemClock {
        id: systemClock
        precision: root.needsSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Connections {
        target: SessionService

        function onSessionResumed() {
            systemClock.enabled = false;
            systemClock.enabled = true;
        }
    }
}
