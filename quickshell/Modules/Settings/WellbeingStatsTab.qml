pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../DDash/Wellbeing/Wellbeing.js" as Wellbeing

Item {
    id: root

    property var parentModal: null
    property var stats: Wellbeing.breakStats([])

    readonly property bool breaksEnabled: SettingsData.wellbeingBreaksEnabled
    readonly property bool statsAvailable: BreakReminderService.statsAvailable
    readonly property int revision: BreakReminderService.statsRevision

    onStatsAvailableChanged: refresh()
    onRevisionChanged: refresh()
    Component.onCompleted: refresh()

    function refresh() {
        BreakReminderService.stats(result => root.stats = result);
    }

    function rateText(totals) {
        if (totals.rate < 0)
            return "—";
        return totals.completed + "/" + totals.total + " (" + totals.rate + "%)";
    }

    SettingsPage {
        SettingsDeferred {
            when: root.statsAvailable

            SettingsCard {
                iconName: "bar_chart"
                title: I18n.tr("Statistics", "settings card title, break reminder statistics")
                settingKey: "wellbeingBreakStats"
                tab: "wellbeing_stats"
                tags: ["wellbeing", "break", "statistics", "history", "completed", "skipped", "snoozed"]

                headerActions: DButton {
                    text: I18n.tr("Reset")
                    variant: "tonal"
                    danger: true
                    buttonHeight: Theme.buttonHeightXS
                    enabled: root.stats.all.total > 0
                    onClicked: BreakReminderService.resetStats()
                }

                SettingsRow {
                    iconName: "today"
                    title: I18n.tr("Today")
                    trailingBadge: root.rateText(root.stats.today)
                }

                SettingsRow {
                    iconName: "date_range"
                    title: I18n.tr("This week", "screen time chart title, the seven days ending today")
                    trailingBadge: root.rateText(root.stats.week)
                }

                SettingsRow {
                    iconName: "check_circle"
                    title: I18n.tr("Completed")
                    trailingBadge: String(root.stats.all.completed)
                }

                SettingsRow {
                    iconName: "skip_next"
                    title: I18n.tr("Skipped", "break statistics, number of skipped breaks")
                    trailingBadge: String(root.stats.all.skipped)
                }

                SettingsRow {
                    iconName: "snooze"
                    title: I18n.tr("Snoozed", "break statistics, number of snoozed breaks")
                    trailingBadge: String(root.stats.all.snoozed)
                }

                SettingsRow {
                    iconName: "leaderboard"
                    title: I18n.tr("Total")
                    trailingBadge: String(root.stats.all.total)
                }
            }
        }

        SettingsDeferred {
            SettingsCard {
                iconName: "preview"
                title: I18n.tr("Testing & preview", "settings card title, try out break reminder surfaces")
                settingKey: "wellbeingBreakPreview"
                tab: "wellbeing_stats"
                tags: ["wellbeing", "break", "preview", "test", "sound"]

                SettingsRow {
                    iconName: "notifications"
                    title: I18n.tr("Preview pre-break warning", "break reminder test action")
                    enabled: root.breaksEnabled && SettingsData.wellbeingBreakWarning > 0
                    clickable: true
                    onClicked: BreakReminderService.previewWarning()
                }

                SettingsRow {
                    iconName: "fullscreen"
                    title: I18n.tr("Preview fullscreen break", "break reminder test action")
                    clickable: true
                    onClicked: BreakReminderService.previewBreak()
                }

                SettingsRow {
                    iconName: "volume_up"
                    title: I18n.tr("Test alert sound", "break reminder test action")
                    enabled: SettingsData.wellbeingBreakSound && SettingsData.soundsEnabled
                    clickable: true
                    onClicked: BreakReminderService.playSound(true)
                }
            }
        }
    }
}
