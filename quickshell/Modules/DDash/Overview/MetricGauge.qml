import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.DDash

DRingGauge {
    id: root

    property real usage: -1
    property string iconName: ""
    property real iconSize: Theme.iconSizeSmall
    property color iconColor: Theme.primary
    property color discColor: Theme.chipSurface

    readonly property real discSize: hasRing ? width - (strokeWidth + DashMetrics.gaugeGap) * 2 : width

    value: usage
    strokeWidth: DashMetrics.gaugeStroke
    trackColor: Theme.withAlpha(Theme.surfaceText, Theme.stateLayerFocus)
    animated: DashMetrics.animationsEnabled
    animationDuration: DashMetrics.meterDuration

    Rectangle {
        anchors.centerIn: parent
        width: root.discSize
        height: root.discSize
        radius: width / 2
        color: root.discColor
    }

    DIcon {
        anchors.centerIn: parent
        name: root.iconName
        size: root.iconSize
        color: root.iconColor
    }
}
