pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.DCommon.Widgets
import "../../../Common/Format.js" as Format

Item {
    id: root

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string title: I18n.tr("Do not disturb")
    property real nowMs: Date.now()

    readonly property var presets: [
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

    Timer {
        interval: CcMetrics.dndRefreshInterval
        repeat: true
        running: root.visible && SessionData.doNotDisturb && SessionData.doNotDisturbUntil > 0
        onTriggered: root.nowMs = Date.now()
    }

    function formatRemaining(ms) {
        return Format.formatRemaining(ms, "", I18n.tr("%1 min left", "time remaining on a timed mode, %1 is minutes"), I18n.tr("%1 h left", "time remaining on a timed mode, %1 is hours"), I18n.tr("%1 h %2 m left", "time remaining on a timed mode, %1 is hours, %2 is minutes"));
    }

    function minutesUntilTomorrowMorning() {
        const now = new Date();
        const target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 8, 0, 0, 0);
        return Math.max(1, Math.round((target.getTime() - now.getTime()) / 60000));
    }

    DFlickable {
        anchors.fill: parent
        contentHeight: column.height
        clip: true

        Column {
            id: column
            width: parent.width
            spacing: CcMetrics.detailContentGap

            CcGroup {
                CcToggleRow {
                    iconName: SessionData.doNotDisturb ? "do_not_disturb_on" : "notifications_paused"
                    iconColor: SessionData.doNotDisturb ? Theme.primary : Theme.surfaceText
                    text: I18n.tr("Silence notifications")
                    description: {
                        if (!SessionData.doNotDisturb)
                            return I18n.tr("Pick how long to pause notifications");
                        if (SessionData.doNotDisturbUntil <= 0)
                            return I18n.tr("On indefinitely");
                        const remaining = Math.max(0, SessionData.doNotDisturbUntil - root.nowMs);
                        return root.formatRemaining(remaining) + " · " + I18n.tr("until %1", "lowercase, follows the remaining time after a separator, %1 is a clock time").arg(Format.formatUntil(SessionData.doNotDisturbUntil, SettingsData.use24HourClock));
                    }
                    checked: SessionData.doNotDisturb
                    onToggled: checked => SessionData.setDoNotDisturb(checked, 0)
                }
            }

            CcGroup {
                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.presets

                        DButton {
                            required property var modelData

                            buttonHeight: Theme.buttonHeightXS
                            iconName: modelData.icon || ""
                            iconSize: Theme.iconSizeSmall
                            text: modelData.label
                            backgroundColor: Theme.chipSurface
                            textColor: Theme.surfaceText
                            onClicked: {
                                const minutes = modelData.minutesFn ? root.minutesUntilTomorrowMorning() : modelData.minutes;
                                SessionData.setDoNotDisturb(true, minutes);
                            }
                        }
                    }
                }
            }
        }
    }
}
