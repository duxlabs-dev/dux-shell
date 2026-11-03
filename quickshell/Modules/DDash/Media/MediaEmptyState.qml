pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.DCommon.Widgets
import qs.DCommon.Common as DCommon

Item {
    id: root

    readonly property real textSize: Theme.fontSizeXXLarge
    readonly property color inkColor: Theme.onSurfaceVariant

    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingXXS

        // Drawn instead of typed: the kaomoji glyphs live in CJK and syllabics fallback fonts.
        Shape {
            id: sleepingCat

            readonly property real unit: root.textSize / 100

            anchors.horizontalCenter: parent.horizontalCenter
            width: 532 * unit
            height: 89 * unit
            preferredRendererType: Shape.CurveRenderer
            Accessible.ignored: true

            ShapePath {
                scale: Qt.size(sleepingCat.unit, sleepingCat.unit)
                strokeColor: root.inkColor
                strokeWidth: 8 * sleepingCat.unit
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: "M5 84 L45 5 L73 41 M120 49 H148 M198 54 H212 M205 54 V65 M259 49 H287 M315 35 H351 L332 57 M325 49 L346 71 M423 21 H443 L423 41 H443 M491 37 H527 L491 73 H527"
                }
            }
        }

        StyledText {
            width: parent.width
            text: I18n.tr("No media found.", "Media player empty state when no player is running")
            color: root.inkColor
            fontToken: DCommon.Fonts.gochiHand
            font.pixelSize: root.textSize
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
