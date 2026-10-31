import QtQuick
import qs.Common
import qs.Modules.DDash

Item {
    id: root

    required property Item group

    readonly property Item segment: parent
    property real leading: group.leadingRadius(segment)
    property real trailing: group.trailingRadius(segment)

    Behavior on leading {
        enabled: DashMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.standard
        }
    }

    Behavior on trailing {
        enabled: DashMetrics.animationsEnabled
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.standard
        }
    }

    Binding {
        target: root.segment
        property: "topLeftRadius"
        value: root.leading
    }

    Binding {
        target: root.segment
        property: "bottomLeftRadius"
        value: root.leading
    }

    Binding {
        target: root.segment
        property: "topRightRadius"
        value: root.trailing
    }

    Binding {
        target: root.segment
        property: "bottomRightRadius"
        value: root.trailing
    }
}
