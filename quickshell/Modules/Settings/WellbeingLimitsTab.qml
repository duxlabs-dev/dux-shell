pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.Common
import qs.Modules.Settings.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.DDash.Wellbeing

Item {
    id: root

    property var parentModal: null
    property var desktopApps: []

    readonly property var limits: SettingsData.wellbeingAppLimits ?? {}
    readonly property var limitedApps: Object.keys(limits).filter(appId => Number(limits[appId]) > 0).sort((a, b) => WellbeingService.appName(a).localeCompare(WellbeingService.appName(b)))

    function addLimit(entryId) {
        const bare = entryId.endsWith(".desktop") ? entryId.slice(0, -8) : entryId;
        const appId = DesktopEntries.byId(bare)?.startupClass || bare;
        if (WellbeingService.appLimitMinutes(appId) > 0)
            return;
        WellbeingService.setAppLimit(appId, WellbeingMetrics.defaultLimitMinutes);
    }

    Component.onCompleted: desktopApps = AppSearchService.getVisibleApplications() || []
    Component.onDestruction: desktopApps = []

    ConfirmModal {
        id: clearConfirm
    }

    AppBrowserPopup {
        id: appBrowser
        appsModel: root.desktopApps
        parentModal: root.parentModal
        onAppSelected: entryId => root.addLimit(entryId)
    }

    SettingsPage {
        SettingsCard {
            iconName: "hourglass_empty"
            settingKey: "wellbeingLimits"
            tab: "wellbeing_limits"
            tags: ["wellbeing", "screen time", "limit", "daily"]

            SettingsRow {
                settingKey: "wellbeingDailyLimit"
                tab: "wellbeing_limits"
                tags: ["wellbeing", "screen time", "limit", "daily"]
                title: I18n.tr("Daily limit", "screen time limit per day, total or for one app")
                subtitle: SettingsData.wellbeingDailyLimit > 0 ? I18n.tr("Notifies when today's screen time passes the limit", "daily screen time limit description") : I18n.tr("Off")

                body: SettingsDurationPicker {
                    width: parent.width
                    minutes: SettingsData.wellbeingDailyLimit
                    onCommitted: next => SettingsData.set("wellbeingDailyLimit", next)
                }
            }
        }

        SettingsDeferred {
            SettingsCard {
                iconName: "timer"
                title: I18n.tr("App limits", "settings card title, per-app screen time limits")
                settingKey: "wellbeingAppLimits"
                tab: "wellbeing_limits"
                tags: ["wellbeing", "screen time", "limit", "app"]

                headerActions: DButton {
                    text: I18n.tr("Add", "verb, button that adds a new item to a list")
                    iconName: "add"
                    buttonHeight: Theme.buttonHeightXS
                    onClicked: appBrowser.show()
                }

                SettingsRow {
                    visible: root.limitedApps.length === 0
                    title: I18n.tr("No app limits", "empty state, per-app screen time limits list")
                    titleColor: Theme.surfaceVariantText
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
        }

        SettingsDeferred {
            SettingsCard {
                iconName: "history"
                title: I18n.tr("History")
                settingKey: "wellbeingHistory"
                tab: "wellbeing_limits"
                tags: ["wellbeing", "screen time", "history", "clear"]

                SettingsRow {
                    title: I18n.tr("Screen time history", "settings row title, stored screen time data")
                    subtitle: I18n.tr("Kept for %1 days on this device", "screen time history description, %1 is a number of days").arg(WellbeingMetrics.retentionDays)

                    DButton {
                        anchors.verticalCenter: parent.verticalCenter
                        buttonHeight: Theme.buttonHeightXS
                        text: I18n.tr("Clear")
                        variant: "tonal"
                        danger: true
                        enabled: WellbeingService.available
                        onClicked: clearConfirm.showWithOptions({
                            "title": I18n.tr("Clear History?"),
                            "message": I18n.tr("Deletes all stored screen time", "confirmation message before clearing screen time history"),
                            "confirmText": I18n.tr("Clear"),
                            "danger": true,
                            "onConfirm": () => WellbeingService.clearHistory()
                        })
                    }
                }
            }
        }
    }
}
