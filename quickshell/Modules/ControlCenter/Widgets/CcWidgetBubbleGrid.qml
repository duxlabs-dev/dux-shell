pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter

Grid {
    id: grid

    property var entries: []
    property bool roundAll: true
    property real bubbleSize: CcMetrics.previewSize
    property bool draggable: false
    property Item fallbackFocus: null
    property int refocusIndex: -1

    signal chosen(string widgetId)
    signal dragStarted(string widgetId, point scenePoint)
    signal dragMoved(string widgetId, point scenePoint)
    signal dragEnded(string widgetId, bool canceled)
    signal itemFocused(Item item)

    columns: Math.max(1, Math.floor((width + columnSpacing) / (bubbleSize + columnSpacing)))
    columnSpacing: Theme.spacingM
    rowSpacing: Theme.spacingL

    Repeater {
        id: repeater

        model: grid.entries

        // Adding rebuilds the list and destroys the focused bubble, so the keyboard moves to its replacement.
        onModelChanged: {
            const index = grid.refocusIndex;
            grid.refocusIndex = -1;
            if (index < 0)
                return;
            (repeater.itemAt(Math.min(index, repeater.count - 1)) ?? grid.fallbackFocus)?.forceActiveFocus(Qt.TabFocusReason);
        }

        CcWidgetBubble {
            id: bubble

            required property var modelData
            required property int index

            entry: modelData
            bubbleSize: grid.bubbleSize
            draggable: grid.draggable
            roundAll: grid.roundAll
            canStep: (dx, dy) => {
                const target = index + dx + dy * grid.columns;
                return target >= 0 && target < repeater.count;
            }
            width: (grid.width - grid.columnSpacing * (grid.columns - 1)) / grid.columns
            onClicked: {
                grid.refocusIndex = bubble.activeFocus ? index : -1;
                grid.chosen(modelData.id);
            }
            onDragStarted: scenePoint => grid.dragStarted(modelData.id, scenePoint)
            onDragMoved: scenePoint => grid.dragMoved(modelData.id, scenePoint)
            onDragEnded: canceled => grid.dragEnded(modelData.id, canceled)
            onActiveFocusChanged: {
                if (activeFocus)
                    grid.itemFocused(bubble);
            }
            onStep: (dx, dy) => {
                repeater.itemAt(index + dx + dy * grid.columns)?.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }
}
