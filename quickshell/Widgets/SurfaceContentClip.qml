pragma ComponentBehavior: Bound

import QtQuick
import "../Common/FluidGeometry.js" as FluidGeometry

Item {
    id: root

    default property alias contentData: clipContent.data
    readonly property alias contentItem: clipContent

    property bool active: false
    property bool revealActive: false
    required property rect body
    required property rect targetRect
    property real revealX: 0
    property real revealY: 0
    property real revealWidth: 0
    property real revealHeight: 0
    property real topOverflow: 0
    property real bottomOverflow: 0

    x: active ? body.x : (revealActive ? revealX : 0)
    y: (active ? body.y : (revealActive ? revealY : 0)) - topOverflow
    width: active ? body.width : (revealActive ? revealWidth : targetRect.width)
    height: (active ? body.height : (revealActive ? revealHeight : targetRect.height)) + topOverflow + bottomOverflow
    clip: active ? (body.width < targetRect.width || body.height < targetRect.height) : revealActive

    Item {
        id: clipContent
        x: -root.x
        y: -root.y
        width: root.targetRect.width
        height: root.targetRect.height
        opacity: root.active ? FluidGeometry.contentOpacity(root.body, root.targetRect) : 1
    }
}
