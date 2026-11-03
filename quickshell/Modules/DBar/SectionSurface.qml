import QtQuick
import qs.Common
import qs.Modules.SurfaceWidgets

Item {
    id: root

    property real alongPos: 0
    property real alongSize: 0
    property real alongExtent: 0
    property real crossSize: 0
    property real crossExtent: crossSize
    property bool isVertical: false
    property bool crossFar: false
    property bool trailing: false
    property bool edgeAligned: false
    property real pad: 0
    property real cornerRadius: Theme.windowRadius
    property real sweep: 0
    property bool gothEnabled: false
    property color fillColor: "transparent"
    property real clearEdge: NaN
    property real dpr: 1

    readonly property real fullAlongStart: edgeAligned && !trailing ? 0 : alongPos - pad
    readonly property real fullAlongEnd: edgeAligned && trailing ? alongExtent : alongPos + alongSize + pad
    readonly property real alongStart: trailing && !isNaN(clearEdge) ? Math.max(fullAlongStart, clearEdge) : fullAlongStart
    readonly property real alongEnd: !trailing && !isNaN(clearEdge) ? Math.min(fullAlongEnd, clearEdge) : fullAlongEnd
    readonly property real chromeAlongPos: Theme.snap(alongStart, dpr)
    readonly property real chromeAlongSize: alongSize <= 0 ? 0 : Math.max(0, Theme.snap(alongEnd, dpr) - chromeAlongPos)
    readonly property real cornerR: Math.max(0, Math.min(cornerRadius, crossSize / 2))
    readonly property real sweepR: gothEnabled ? Math.max(0, sweep) : 0
    // Same clamps as BarSurface wings: free ends lose depth to the strip, attached ends lose reach to the body.
    readonly property real freeCrossR: Math.min(sweepR, Math.max(0, crossSize - cornerR))
    readonly property real attachedAlongR: Math.min(sweepR, Math.max(0, chromeAlongSize - cornerR))
    readonly property bool canonicalBottomEdge: !isVertical && crossFar
    readonly property bool canonicalRightSide: isVertical ? (crossFar ? trailing : !trailing) : trailing
    readonly property bool startAttached: edgeAligned && !canonicalRightSide
    readonly property bool endAttached: edgeAligned && canonicalRightSide
    readonly property alias body: body
    readonly property real startAlongR: startAttached ? attachedAlongR : sweepR
    readonly property real endAlongR: endAttached ? attachedAlongR : sweepR
    readonly property real startCrossR: startAttached ? sweepR : freeCrossR
    readonly property real endCrossR: endAttached ? sweepR : freeCrossR

    readonly property real alongStartRadius: edgeAligned && !trailing ? 0 : cornerR
    readonly property real alongEndRadius: edgeAligned && trailing ? 0 : cornerR
    readonly property rect startSweepRect: localRect(startAttached ? 0 : -startAlongR, startAttached ? crossSize : 0, startAlongR, startCrossR)
    readonly property rect startSweepDisc: localRect(startAttached ? 0 : -startAlongR * 2, startAttached ? crossSize : 0, startAlongR * 2, startCrossR * 2)
    readonly property rect endSweepRect: localRect(endAttached ? chromeAlongSize - endAlongR : chromeAlongSize, endAttached ? crossSize : 0, endAlongR, endCrossR)
    readonly property rect endSweepDisc: localRect(endAttached ? chromeAlongSize - endAlongR * 2 : chromeAlongSize, endAttached ? crossSize : 0, endAlongR * 2, endCrossR * 2)

    function localRect(cx, cy, cw, ch) {
        const along = chromeAlongSize;
        const cross = crossSize;
        if (!isVertical)
            return crossFar ? Qt.rect(cx, cross - cy - ch, cw, ch) : Qt.rect(cx, cy, cw, ch);
        return crossFar ? Qt.rect(cross - cy - ch, cx, ch, cw) : Qt.rect(cy, along - cx - cw, ch, cw);
    }

    visible: chromeAlongSize > 0
    x: isVertical ? (crossFar ? crossExtent - crossSize : 0) : chromeAlongPos
    y: isVertical ? chromeAlongPos : (crossFar ? crossExtent - crossSize : 0)
    width: isVertical ? crossSize : chromeAlongSize
    height: isVertical ? chromeAlongSize : crossSize

    Item {
        id: canvas

        anchors.centerIn: parent
        width: root.chromeAlongSize
        height: root.crossSize
        rotation: root.isVertical ? (root.crossFar ? 90 : -90) : 0
        transform: Scale {
            yScale: root.canonicalBottomEdge ? -1 : 1
            origin.y: canvas.height / 2
        }

        Rectangle {
            id: body
            anchors.fill: parent
            color: root.fillColor
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: root.startAttached ? 0 : root.cornerR
            bottomRightRadius: root.endAttached ? 0 : root.cornerR
        }

        GothCorner {
            visible: !root.startAttached && root.startAlongR > 0 && root.startCrossR > 0
            radiusX: root.startAlongR
            radiusY: root.startCrossR
            color: root.fillColor
            x: -radiusX
            y: 0
            corner: "bottomLeft"
        }

        GothCorner {
            visible: !root.endAttached && root.endAlongR > 0 && root.endCrossR > 0
            radiusX: root.endAlongR
            radiusY: root.endCrossR
            color: root.fillColor
            x: canvas.width
            y: 0
            corner: "bottomRight"
        }

        GothCorner {
            visible: root.startAttached && root.startAlongR > 0 && root.startCrossR > 0
            radiusX: root.startAlongR
            radiusY: root.startCrossR
            color: root.fillColor
            x: 0
            y: canvas.height
            corner: "bottomRight"
        }

        GothCorner {
            visible: root.endAttached && root.endAlongR > 0 && root.endCrossR > 0
            radiusX: root.endAlongR
            radiusY: root.endCrossR
            color: root.fillColor
            x: canvas.width - radiusX
            y: canvas.height
            corner: "bottomLeft"
        }
    }
}
