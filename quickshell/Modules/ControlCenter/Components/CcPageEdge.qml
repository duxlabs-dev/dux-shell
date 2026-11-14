pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.ControlCenter

Item {
    id: root

    property int count: 1
    property int currentIndex: 0
    property real gutter: 0
    property bool dragActive: false
    property int armedDirection: 0

    signal carryRequested(int direction)

    function hasNeighbor(direction: int): bool {
        const page = currentIndex + direction;
        return direction !== 0 && page >= 0 && page < count;
    }

    function directionAt(x: real): int {
        const reach = Theme.minimumTouchTargetSize - gutter;
        if (x < reach)
            return I18n.isRtl ? 1 : -1;
        if (x > width - reach)
            return I18n.isRtl ? -1 : 1;
        return 0;
    }

    // A null point is a drag something else claims (trash, group), which never arms a carry.
    function updateDrag(scenePoint) {
        if (!dragActive || !scenePoint) {
            armedDirection = 0;
            return;
        }
        const point = mapFromItem(null, scenePoint.x, scenePoint.y);
        const direction = point.y >= 0 && point.y <= height ? directionAt(point.x) : 0;
        armedDirection = hasNeighbor(direction) ? direction : 0;
    }

    onDragActiveChanged: {
        if (!dragActive)
            armedDirection = 0;
    }

    onArmedDirectionChanged: {
        if (armedDirection === 0) {
            hold.stop();
            return;
        }
        hold.restart();
    }

    Timer {
        id: hold

        interval: CcMetrics.pageCarryHoldMs
        onTriggered: {
            const direction = root.armedDirection;
            // Cleared first, so the next drag update at this edge arms a fresh hold on the new page.
            root.armedDirection = 0;
            if (root.hasNeighbor(direction))
                root.carryRequested(direction);
        }
    }

    Repeater {
        model: [-1, 1]

        Rectangle {
            id: rail

            required property int modelData
            readonly property int direction: modelData
            readonly property bool leftSide: (direction < 0) !== I18n.isRtl
            readonly property bool shown: root.dragActive && root.hasNeighbor(direction)
            readonly property bool armed: root.armedDirection === direction
            property real fill: 0

            x: leftSide ? -(root.gutter + width) / 2 : root.width + (root.gutter - width) / 2
            width: root.gutter / 2
            height: root.height
            radius: Theme.fullRadius(width, height)
            color: Theme.withAlpha(Theme.primary, Theme.stateLayerHover)
            opacity: shown ? 1 : 0
            visible: opacity > 0

            onArmedChanged: {
                if (armed && CcMetrics.animationsEnabled) {
                    fillAnimation.restart();
                    return;
                }
                fillAnimation.stop();
                fill = armed ? 1 : 0;
            }

            Behavior on opacity {
                enabled: CcMetrics.animationsEnabled
                NumberAnimation {
                    duration: Theme.expressiveDurations.expressiveEffects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }

            NumberAnimation {
                id: fillAnimation

                target: rail
                property: "fill"
                from: 0
                to: 1
                duration: CcMetrics.pageCarryHoldMs
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.height * rail.fill
                radius: Theme.fullRadius(width, height)
                color: Theme.withAlpha(Theme.primary, Theme.stateLayerDrag)
            }

            DIcon {
                anchors.centerIn: parent
                name: rail.leftSide ? "chevron_left" : "chevron_right"
                size: root.gutter
                color: Theme.primary
            }
        }
    }
}
