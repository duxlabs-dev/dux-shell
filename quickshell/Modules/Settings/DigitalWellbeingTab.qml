pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash.Wellbeing
import "../DDash/Wellbeing/Wellbeing.js" as Wellbeing

Item {
    id: root

    property var parentModal: null
    property var days: []

    readonly property date today: new Date()
    readonly property date anchor: Wellbeing.addDays(today, chart.weekOffset * Wellbeing.weekLength)
    readonly property var limits: SettingsData.wellbeingAppLimits ?? {}
    readonly property var limitedApps: Object.keys(limits).filter(appId => Number(limits[appId]) > 0).sort((a, b) => WellbeingService.appName(a).localeCompare(WellbeingService.appName(b)))
    readonly property bool available: WellbeingService.available
    readonly property int revision: WellbeingService.revision
    readonly property int firstDayOfWeek: SettingsData.firstDayOfWeek >= 7 || SettingsData.firstDayOfWeek < 0 ? Qt.locale().firstDayOfWeek : SettingsData.firstDayOfWeek

    onAvailableChanged: refresh()
    onRevisionChanged: refresh()
    Component.onCompleted: refresh()

    function toggleLimit(appId) {
        WellbeingService.setAppLimit(appId, WellbeingService.appLimitMinutes(appId) > 0 ? 0 : WellbeingMetrics.defaultLimitMinutes);
    }

    function refresh() {
        if (!available)
            return;
        WellbeingService.summary(result => root.days = result);
    }

    ConfirmModal {
        id: clearConfirm
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            visible: root.available && SettingsData.wellbeingEnabled
            iconName: "show_chart"
            title: I18n.tr("Weekly screen time", "chart title, screen time per day over the week")
            settingKey: "wellbeingChart"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "chart", "week"]

            WeeklyChart {
                id: chart
                height: WellbeingMetrics.chartHeight
                color: "transparent"
                pad: 0
                showTitle: false
                days: root.days
                today: root.today
                firstDayOfWeek: root.firstDayOfWeek
                limitSeconds: SettingsData.wellbeingDailyLimit * 60
            }
        }

        SettingsCard {
            width: parent.width
            visible: root.available && SettingsData.wellbeingEnabled
            iconName: "apps"
            title: I18n.tr("Most used apps", "screen time card title, apps ranked by time")
            settingKey: "wellbeingApps"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "apps", "usage"]

            AppUsageList {
                height: implicitHeight
                color: "transparent"
                pad: 0
                showTitle: false
                fillHeight: false
                days: root.days
                firstDayOfWeek: root.firstDayOfWeek
                anchor: root.anchor
                today: root.today
                onLimitRequested: appId => root.toggleLimit(appId)
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "digital_wellbeing"
            title: I18n.tr("Screen time", "dashboard card and settings card title, time spent in apps")
            settingKey: "wellbeing"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "usage", "limit"]

            SettingsToggleRow {
                settingKey: "wellbeingEnabled"
                tab: "wellbeing"
                tags: ["wellbeing", "screen time", "tracking"]
                text: I18n.tr("Track screen time", "digital wellbeing main toggle")
                description: I18n.tr("Counts time in the focused app while the session is active. Stays on this device.", "track screen time toggle description")
                checked: SettingsData.wellbeingEnabled
                onToggled: checked => SettingsData.set("wellbeingEnabled", checked)
            }

            SettingsRow {
                settingKey: "wellbeingDailyLimit"
                tab: "wellbeing"
                tags: ["wellbeing", "screen time", "limit", "daily"]
                title: I18n.tr("Daily limit", "screen time limit per day, total or for one app")
                subtitle: SettingsData.wellbeingDailyLimit > 0 ? I18n.tr("Notifies when today's screen time passes the limit", "daily screen time limit description") : I18n.tr("Off")

                DurationSteppers {
                    anchors.verticalCenter: parent.verticalCenter
                    minutes: SettingsData.wellbeingDailyLimit
                    onCommitted: next => SettingsData.set("wellbeingDailyLimit", next)
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "timer"
            title: I18n.tr("App limits", "settings card title, per-app screen time limits")
            settingKey: "wellbeingAppLimits"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "limit", "app"]

            SettingsRow {
                visible: root.limitedApps.length === 0
                title: I18n.tr("No app limits", "empty state, per-app screen time limits list")
                subtitle: I18n.tr("Pick an app from the list above or the dashboard tab", "app limits empty state description")
            }

            Repeater {
                model: root.limitedApps

                SettingsRow {
                    id: limitRow

                    required property string modelData

                    settingKey: "wellbeingAppLimits:" + modelData
                    resetKeys: []
                    title: WellbeingService.appName(modelData)

                    leading: CcAppIcon {
                        appId: limitRow.modelData
                        iconSize: Theme.iconSizeLarge
                    }

                    DurationSteppers {
                        anchors.verticalCenter: parent.verticalCenter
                        minutes: WellbeingService.appLimitMinutes(limitRow.modelData)
                        onCommitted: next => WellbeingService.setAppLimit(limitRow.modelData, next)
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"
                        iconColor: Theme.surfaceVariantText
                        Accessible.name: I18n.tr("Remove")
                        onClicked: WellbeingService.setAppLimit(limitRow.modelData, 0)
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "history"
            title: I18n.tr("History")
            settingKey: "wellbeingHistory"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "history", "clear"]

            SettingsRow {
                title: I18n.tr("Screen time history", "settings row title, stored screen time data")
                subtitle: I18n.tr("Kept for %1 days on this device", "screen time history description, %1 is a number of days").arg(WellbeingMetrics.retentionDays)

                DButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonHeight: Theme.buttonHeightXS
                    text: I18n.tr("Clear")
                    backgroundColor: Theme.errorContainer
                    textColor: Theme.error
                    enabled: root.available
                    onClicked: clearConfirm.showWithOptions({
                        "title": I18n.tr("Clear History?"),
                        "message": I18n.tr("Deletes all stored screen time", "confirmation message before clearing screen time history"),
                        "confirmText": I18n.tr("Clear"),
                        "confirmColor": Theme.error,
                        "onConfirm": () => {
                            WellbeingService.clearHistory();
                            root.days = [];
                        }
                    })
                }
            }
        }
    }
}
