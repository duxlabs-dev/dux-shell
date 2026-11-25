pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash.Wellbeing
import "../DDash/Wellbeing/Wellbeing.js" as Wellbeing

Column {
    id: root

    property var parentModal: null
    property var days: []
    property bool appsOpen: false

    readonly property date today: new Date()
    readonly property bool available: WellbeingService.available
    readonly property int revision: WellbeingService.revision

    onAvailableChanged: refresh()
    onRevisionChanged: refresh()
    Component.onCompleted: refresh()

    function refresh() {
        if (!available)
            return;
        WellbeingService.summary(result => root.days = result);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsDeferred {
        SettingsCard {
            iconName: "digital_wellbeing"
            settingKey: "wellbeingTracking"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "tracking"]

            SettingsToggleRow {
                tab: "wellbeing"
                tags: ["wellbeing", "screen time", "tracking"]
                settingKey: "wellbeingEnabled"
                text: I18n.tr("Track screen time", "digital wellbeing main toggle")
                description: I18n.tr("Counts time in the focused app while the session is active. Stays on this device.", "track screen time toggle description")
                checked: SettingsData.wellbeingEnabled
                onToggled: checked => SettingsData.set("wellbeingEnabled", checked)
            }
        }
    }

    SettingsDeferred {
        when: root.available && SettingsData.wellbeingEnabled

        SettingsCard {
            iconName: "show_chart"
            title: I18n.tr("Weekly screen time", "chart title, screen time per day over the week")
            settingKey: "wellbeingChart"
            tab: "wellbeing"
            tags: ["wellbeing", "screen time", "chart", "week"]

            WeeklyChart {
                id: chart
                height: WellbeingMetrics.chartHeight
                color: "transparent"
                controlColor: SettingsMetrics.controlColor
                pad: 0
                days: root.days
                today: root.today
                limitSeconds: SettingsData.wellbeingDailyLimit * 60
            }

            SettingsFoldRow {
                id: appsRow

                readonly property var apps: chart.selectedDay ? Wellbeing.topApps([chart.selectedDay], WellbeingMetrics.listedApps) : []

                tab: "wellbeing"
                tags: ["wellbeing", "screen time", "apps", "usage"]
                settingKey: "wellbeingApps"
                title: I18n.tr("Most used apps", "screen time card title, apps ranked by time")
                open: root.appsOpen
                onToggled: root.appsOpen = !root.appsOpen

                accessory: Row {
                    spacing: -Theme.spacingS

                    Repeater {
                        model: appsRow.apps.slice(0, WellbeingMetrics.stackedApps)

                        StyledRect {
                            required property var modelData

                            width: Theme.iconButtonSize
                            height: width
                            radius: Theme.cornerRadiusS
                            color: appsRow.rowColor

                            CcAppIcon {
                                anchors.centerIn: parent
                                appId: parent.modelData.appId
                                iconSize: Theme.iconSizeLarge
                            }
                        }
                    }
                }

                body: Loader {
                    width: parent.width
                    visible: active
                    active: appsRow.open

                    sourceComponent: SettingsGroup {
                        slotColor: SettingsMetrics.controlColor

                        SettingsRow {
                            visible: appsRow.apps.length === 0
                            title: I18n.tr("Nothing tracked yet", "empty state of the screen time app list")
                            titleColor: Theme.surfaceVariantText
                        }

                        Repeater {
                            model: appsRow.apps

                            SettingsRow {
                                id: appRow

                                required property var modelData
                                readonly property int limitMinutes: WellbeingService.appLimitMinutes(modelData.appId)
                                readonly property bool overLimit: limitMinutes > 0 && modelData.seconds >= limitMinutes * 60

                                title: WellbeingService.appName(modelData.appId)
                                trailingBadge: WellbeingService.formatDuration(modelData.seconds)
                                trailingBadgeColor: overLimit ? Theme.error : supportingContentColor

                                leading: CcAppIcon {
                                    appId: appRow.modelData.appId
                                    iconSize: Theme.iconSizeLarge
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
