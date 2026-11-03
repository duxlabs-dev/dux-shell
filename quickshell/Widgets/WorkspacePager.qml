pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Page-control style workspace strip: a dot per workspace, the focused one stretched into a pill.
Item {
    id: root

    required property var model
    property bool vertical: false
    property real dotSize: Theme.spacingS
    property real activeLength: dotSize * 2.5
    property real gap: Theme.spacingXS
    property color activeColor: Theme.primary
    property color occupiedColor: Theme.surfaceTextMedium
    property color emptyColor: Theme.surfaceTextAlpha
    property color urgentColor: Theme.error
    property bool animated: !SettingsData.reduceMotion

    implicitWidth: strip.implicitWidth
    implicitHeight: strip.implicitHeight

    function indexAt(x, y) {
        let closest = -1;
        let closestDist = Infinity;
        for (let i = 0; i < dots.count; i++) {
            const item = dots.itemAt(i);
            if (!item || root.model.isPlaceholder(root.model.workspaceList[i]))
                continue;
            const center = item.mapToItem(root, item.width / 2, item.height / 2);
            const dist = root.vertical ? Math.abs(y - center.y) : Math.abs(x - center.x);
            if (dist < closestDist) {
                closestDist = dist;
                closest = i;
            }
        }
        return closest;
    }

    function entryAt(x, y) {
        const index = indexAt(x, y);
        return index < 0 ? null : root.model.workspaceList[index];
    }

    Grid {
        id: strip

        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, dots.count)
        spacing: root.gap
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Repeater {
            id: dots

            model: ScriptModel {
                values: root.model.workspaceList
            }

            Rectangle {
                id: dot

                required property var modelData

                readonly property var record: root.model.recordOf(modelData)
                readonly property bool placeholder: root.model.isPlaceholder(modelData)
                readonly property bool active: root.model.isActive(modelData)
                readonly property bool occupied: root.model.isOccupied(modelData)
                readonly property bool urgent: !placeholder && root.model.useNativeWorkspaces && CompositorService.workspaceUrgent(record, CompositorService.loadWorkspaceUrgent(record))
                readonly property real length: active ? root.activeLength : root.dotSize

                width: root.vertical ? root.dotSize : length
                height: root.vertical ? length : root.dotSize
                radius: root.dotSize / 2
                color: active ? root.activeColor : urgent ? root.urgentColor : occupied ? root.occupiedColor : root.emptyColor

                Behavior on width {
                    enabled: root.animated && !root.vertical
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Behavior on height {
                    enabled: root.animated && root.vertical
                    NumberAnimation {
                        duration: Theme.mediumDuration
                        easing.type: Theme.standardEasing
                    }
                }

                Behavior on color {
                    enabled: root.animated
                    ColorAnimation {
                        duration: Theme.shortDuration
                    }
                }
            }
        }
    }
}
