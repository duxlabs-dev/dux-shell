import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.DCommon.Widgets

// Device glyphs Material Symbols lacks, drawn on its 24 px grid.
Item {
    id: root

    property string name: ""
    property real size: Theme.iconSize
    property color color: Theme.surfaceText

    readonly property var paths: ({
            "gpu": ["M2.5 4.5h2v15", "M8.5 6h11a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z", "M13 11.5a2.25 2.25 0 1 0-4.5 0a2.25 2.25 0 1 0 4.5 0z", "M19.5 11.5a2.25 2.25 0 1 0-4.5 0a2.25 2.25 0 1 0 4.5 0z", "M10 17v2.5h7V17"],
            "nvme": ["M5 8h14.5a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H5v-2a2 2 0 0 0 0-4z", "M9 11h5v2H9z"]
        })
    readonly property var drawn: paths[name] ?? null

    implicitWidth: size
    implicitHeight: size

    DIcon {
        visible: root.drawn === null
        anchors.centerIn: parent
        name: visible ? root.name : ""
        size: root.size
        color: root.color
    }

    Shape {
        visible: root.drawn !== null
        width: 24
        height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.drawn?.[0] ?? ""
            }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.drawn?.[1] ?? ""
            }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.drawn?.[2] ?? ""
            }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.drawn?.[3] ?? ""
            }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 1.8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.drawn?.[4] ?? ""
            }
        }
    }
}
