import QtQuick

QtObject {
    id: root

    property string edge: "top"

    readonly property string orientation: isVertical ? "vertical" : "horizontal"
    readonly property bool isVertical: edge === "left" || edge === "right"
    readonly property bool isHorizontal: !isVertical

    function primarySize(item) {
        return isVertical ? item.height : item.width;
    }

    function crossSize(item) {
        return isVertical ? item.width : item.height;
    }

    function setPrimaryPos(item, value) {
        if (isVertical) {
            item.y = value;
        } else {
            item.x = value;
        }
    }

    function getPrimaryPos(item) {
        return isVertical ? item.y : item.x;
    }

    function primaryAnchor(anchors) {
        return isVertical ? anchors.verticalCenter : anchors.horizontalCenter;
    }

    function crossAnchor(anchors) {
        return isVertical ? anchors.horizontalCenter : anchors.verticalCenter;
    }

    function outerVisualEdge() {
        if (edge === "bottom")
            return "bottom";
        if (edge === "left")
            return "right";
        if (edge === "right")
            return "left";
        if (edge === "top")
            return "top";
        return "bottom";
    }

    signal axisEdgeChanged
    signal axisOrientationChanged
    signal changed  // Single coalesced signal

    onEdgeChanged: {
        axisEdgeChanged();
        axisOrientationChanged();
        changed();
    }
}
