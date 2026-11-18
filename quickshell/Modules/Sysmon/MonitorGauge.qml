import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Sysmon

DRingGauge {
    id: root

    property real usage: -1
    property string iconName: ""
    property real iconSize: Theme.iconSizeSmall
    property color iconColor: Theme.primary
    property color discColor: Theme.chipSurface

    readonly property real discSize: hasRing ? width - (strokeWidth + MonitorMetrics.gaugeGap) * 2 : width

    value: usage
    strokeWidth: MonitorMetrics.gaugeStroke
    trackColor: Theme.withAlpha(Theme.surfaceText, Theme.stateLayerFocus)
    animated: MonitorMetrics.animationsEnabled
    animationDuration: MonitorMetrics.meterDuration

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
