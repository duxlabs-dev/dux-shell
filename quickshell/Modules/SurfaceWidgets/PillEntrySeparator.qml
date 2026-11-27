import QtQuick
import qs.Common
import qs.Modules.DBar

Rectangle {
    property bool dot: false
    property bool vertical: false

    width: dot ? BarMetrics.pillDotSize : (vertical ? BarMetrics.pillRuleLength : Theme.dividerWidth)
    height: dot ? BarMetrics.pillDotSize : (vertical ? Theme.dividerWidth : BarMetrics.pillRuleLength)
    radius: dot ? width / 2 : 0
    color: Theme.outlineVariant
    Accessible.ignored: true
}
