import QtQuick
import qs.Common
import qs.Modules.Sysmon

Behavior {
    enabled: MonitorMetrics.animationsEnabled

    NumberAnimation {
        duration: MonitorMetrics.meterDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.expressiveSlowEffects
    }
}
