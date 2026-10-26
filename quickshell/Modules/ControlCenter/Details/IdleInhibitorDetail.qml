pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Services
import qs.DCommon.Widgets
import "../../../Common/Format.js" as Format

Item {
    id: root

    implicitHeight: column.height

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    readonly property string title: I18n.tr("Keep Awake")
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

    Timer {
        interval: CcMetrics.dndRefreshInterval
        repeat: true
        running: root.visible && SessionService.idleInhibited && SessionData.idleInhibitedUntil > 0
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    function formatRemaining(ms) {
        return Format.formatRemaining(ms, "", I18n.tr("%1 min left"), I18n.tr("%1 h left"), I18n.tr("%1 h %2 m left"));
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
                    iconName: SessionService.idleInhibited ? "motion_sensor_active" : "motion_sensor_idle"
                    iconColor: SessionService.idleInhibited ? Theme.primary : Theme.surfaceText
                    text: I18n.tr("Prevent screen timeout")
                    description: {
                        if (!SessionService.idleInhibited)
                            return I18n.tr("Pick how long to stay awake", "idle inhibitor detail subtitle shown while keep awake is off");
                        if (SessionData.idleInhibitedUntil <= 0)
                            return I18n.tr("On indefinitely");
                        const remaining = Math.max(0, SessionData.idleInhibitedUntil - root.nowMs);
                        return root.formatRemaining(remaining) + " · " + I18n.tr("until %1", "lowercase, follows the remaining time after a separator, %1 is a clock time").arg(Format.formatUntil(SessionData.idleInhibitedUntil, SettingsData.use24HourClock));
                    }
                    checked: SessionService.idleInhibited
                    onToggled: checked => checked ? SessionService.enableIdleInhibit(0) : SessionService.disableIdleInhibit()
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
                            onClicked: SessionService.enableIdleInhibit(modelData.minutes)
                        }
                    }
                }
            }

            CcGroup {
                visible: SessionService.loginctlAvailable

                CcToggleRow {
                    iconName: "laptop"
                    text: I18n.tr("Stay awake with the lid closed")
                    checked: SettingsData.keepAwakeBlocksSleep
                    onToggled: checked => SettingsData.set("keepAwakeBlocksSleep", checked)
                }
            }
        }
    }
}
