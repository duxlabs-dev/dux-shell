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
    property bool grid: !compact
    property color gridColor: Theme.outlineLight
    property bool curved: false
    property real fillOpacity: Theme.tonalTintAlpha
    property real lineWidth: compact ? Theme.outlineWidth : Theme.outlineWidthFocused
    property real insetBottom: lineWidth

    implicitHeight: compact ? Theme.iconButtonSize : Theme.listItemHeight * 3

    Repeater {
        model: root.grid ? 3 : 0

        Rectangle {
            required property int index

            width: root.width
            height: Theme.outlineWidth
            y: Math.round((root.height - height) * (index + 1) / 4)
            color: root.gridColor
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
        curved: root.curved
        fillOpacity: root.fillOpacity
        lineWidth: root.lineWidth
        insetBottom: root.insetBottom
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
