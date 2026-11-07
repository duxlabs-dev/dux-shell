import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.Settings.Widgets

SettingsRow {
    minHeight: CcMetrics.rowHeight
    paddingH: CcMetrics.rowPaddingH
    paddingV: CcMetrics.rowPaddingV
    rowColor: CcMetrics.rowColor
    iconColor: active ? Theme.accentOnSelectedContainer : Theme.surfaceText
}
