pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.DDash
import qs.Modules.DDash.Wellbeing
import qs.Modules.ControlCenter.Widgets

FocusScope {
    id: root

    property string entryId: "wellbeing"
    property bool live: Window.window?.visible ?? false
    property var transientSurfaceTracker: null
    property var days: []

    readonly property date today: new Date()
    readonly property int revision: WellbeingService.revision
    readonly property Item focusTarget: root
    readonly property var menuActions: [
        {
            label: I18n.tr("Settings"),
            iconName: "settings",
            action: () => {
                PopoutService.closeDankDash();
                PopoutService.openSettingsWithTab("wellbeing");
            }
        }
    ]

    implicitHeight: DashMetrics.tabMinHeight
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    onLiveChanged: {
        if (!live) {
            limitSheet.dismiss();
            return;
        }
        chart.showToday();
        refresh();
    }
    onRevisionChanged: {
        if (live)
            refresh();
    }

    function refresh() {
        WellbeingService.summary(result => root.days = result);
    }

    function handleKeyEvent(event) {
        if (event.key !== Qt.Key_Escape || !limitSheet.shown)
            return false;
        limitSheet.dismiss();
        return true;
    }

    CcEmptyState {
        anchors.centerIn: parent
        visible: !WellbeingService.available
        iconName: "digital_wellbeing"
        title: I18n.tr("DMS out of date")
        subtitle: I18n.tr("Update the dms package with your package manager, then restart the shell.", "shown when the running shell is older than the installed dms binary")
    }

    Column {
        id: content
        anchors.fill: parent
        spacing: DashMetrics.contentGap
        visible: WellbeingService.available

        WeeklyChart {
            id: chart
            width: parent.width
            height: WellbeingMetrics.chartHeight
            days: root.days
            today: root.today
            limitSeconds: SettingsData.wellbeingDailyLimit * 60
        }

        AppUsageList {
            width: parent.width
            height: parent.height - y
            day: chart.selectedDay
            onLimitRequested: appId => limitSheet.presentFor(appId)
        }
    }

    AppLimitSheet {
        id: limitSheet
        backdrop: content
    }
}
