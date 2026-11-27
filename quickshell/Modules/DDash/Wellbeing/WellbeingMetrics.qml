pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.DDash
import "Wellbeing.js" as Wellbeing

Singleton {
    readonly property real chartHeight: DashMetrics.heightForRows(2)
    readonly property real barWidthRatio: 0.72
    readonly property real minBarHeight: Theme.spacingXS
    readonly property real axisLabelWidth: 28
    readonly property real wheelNotch: 120
    readonly property int settleDelay: 150
    readonly property real appRowHeight: Theme.listItemHeight
    readonly property int listedApps: 12
    readonly property int cardApps: 3
    readonly property int stackedApps: 3
    readonly property int defaultLimitMinutes: 60
    readonly property int retentionDays: Wellbeing.retentionDays
}
