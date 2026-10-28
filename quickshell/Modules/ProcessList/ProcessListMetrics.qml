pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Common as DCommon
import qs.Services
import qs.Modules.Settings.Widgets

Singleton {
    readonly property real rowHeight: Math.max(Theme.listItemHeight + Theme.densityStepM, Theme.buttonHeightS + Theme.spacingXS)
    readonly property real cpuColumnWidth: Theme.fontSizeSmall * 7
    readonly property real memoryColumnWidth: Theme.fontSizeSmall * 8
    readonly property real pidColumnWidth: Theme.fontSizeSmall * 6
    readonly property real actionColumnWidth: Theme.iconButtonSize
    readonly property real headerHeight: Theme.buttonHeightS
    readonly property real windowHeight: SettingsMetrics.windowHeight
    readonly property real menuWidth: 240
    readonly property real menuRowHeight: DCommon.Style.menuRowHeight
    readonly property real menuPadding: DCommon.Style.menuPadding
    readonly property real dialogWidth: 360
    readonly property int refreshInterval: DgopService.updateInterval
}
