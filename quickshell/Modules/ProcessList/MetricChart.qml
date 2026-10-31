pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: root

    property var values: []
    property var secondaryValues: []
    property color color: Theme.primary
    property color secondaryColor: Theme.tertiary
    property real maximum: 0
    property int historyLength: 0
    property bool compact: false

    implicitHeight: compact ? Theme.iconButtonSize : Theme.listItemHeight * 3

    Repeater {
        model: root.compact ? 0 : 3

        Rectangle {
            required property int index

            width: root.width
            height: Theme.outlineWidth
            y: Math.round((root.height - height) * (index + 1) / 4)
            color: Theme.outlineLight
        }
    }

    DSparkline {
        id: sparkline
        anchors.fill: parent
        values: root.values
        secondaryValues: root.secondaryValues
        lineColor: root.color
        secondaryLineColor: "transparent"
        maximum: root.maximum
        historyLength: root.historyLength
        curved: false
        fillOpacity: Theme.tonalTintAlpha
        lineWidth: root.compact ? Theme.outlineWidth : Theme.outlineWidthFocused
    }

    // The sparkline can't dash its second series, so it is drawn here from the same path and range.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.secondaryColor
            strokeWidth: sparkline.lineWidth
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 3]
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: sparkline.secondaryLinePath
            }
        }
    }
}
