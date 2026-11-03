pragma Singleton

import Quickshell
import qs.DCommon.Common as DCommon

Singleton {
    readonly property var rounding: DCommon.Appearance.rounding
    readonly property var spacing: DCommon.Appearance.spacing
    readonly property var fontSize: DCommon.Appearance.fontSize
    readonly property var anim: DCommon.Appearance.anim
}
