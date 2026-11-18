import QtQuick
import qs.Common

SettingsToggleRow {
    active: checked
    minHeight: SettingsMetrics.rowMinHeightTwoLine
    paddingH: SettingsMetrics.rowPaddingH + Theme.spacingS
    topRadius: height / 2
    bottomRadius: height / 2
}
