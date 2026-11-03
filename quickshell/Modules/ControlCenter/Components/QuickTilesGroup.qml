pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.DCommon.Widgets
import "../utils/widgets.js" as WidgetUtils

Item {
    id: root

    property var widgetData: ({})
    property var widgetDef: null
    property var host: null
    property bool live: true
    property bool interactive: true
    property real columns: 4
    property real rows: 1
    property bool compact: false

    readonly property string groupId: widgetData?.instanceId ?? ""
    // Not `bare`: the grid's tile loader writes that name into any tile that has it.
    readonly property bool membersBare: widgetData?.background === false
    readonly property real gap: membersBare ? 0 : CcMetrics.quickTileGap
    readonly property bool editMode: host?.editMode ?? false
    readonly property var members: WidgetUtils.groupMembers(SettingsData.controlCenterWidgets || [], groupId).filter(member => !!host?.model?.componentForWidget(member.widget))
    readonly property bool receiving: groupId !== "" && host?.hoverGroup === groupId
    // Members keep their own input in edit mode so they can be dragged out instead of moving the group.
    readonly property Item passthrough: memberRow
    readonly property real bodyRadius: CcMetrics.pillRadius(width, Math.min(height, CcMetrics.tileHeight))
    readonly property bool memberDragging: liftedIndex >= 0

    property int liftedIndex: -1
    property real liftedWidth: 0
    property point liftPoint: Qt.point(0, 0)
    property int dropSlot: -1
    readonly property int incomingSlot: receiving ? slotAt(mapFromItem(null, host.dragScenePoint.x, host.dragScenePoint.y).x) : -1
    readonly property int gapSlot: liftedIndex >= 0 ? dropSlot : incomingSlot
    readonly property real gapWidth: liftedIndex >= 0 ? liftedWidth : (membersBare ? CcMetrics.quickBareWidth : CcMetrics.iconBoxSize)

    width: parent?.width ?? 0
    height: parent?.height ?? 0
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function others() {
        const items = [];
        for (let i = 0; i < memberRepeater.count; i++) {
            const item = memberRepeater.itemAt(i);
            if (item && item.modelData.index !== liftedIndex)
                items.push(item);
        }
        return items;
    }

    // Measured against the row as it sits without a gap, so opening the gap cannot move the target.
    function slotAt(x) {
        const items = others();
        const total = items.reduce((sum, item) => sum + item.ownWidth + gap, 0) - gap;
        const along = I18n.isRtl ? width - x : x;
        let start = (width - total) / 2;
        for (let k = 0; k < items.length; k++) {
            if (along < start + items[k].ownWidth / 2)
                return k;
            start += items[k].ownWidth + gap;
        }
        return items.length;
    }

    function savedIndexAtSlot(slot) {
        return others()[slot]?.modelData.index ?? -1;
    }

    Component.onDestruction: {
        if (liftedIndex >= 0)
            host.memberDragging = false;
    }

    function lift(member, scenePoint) {
        liftedWidth = member.ownWidth;
        liftedIndex = member.modelData.index;
        host.memberDragging = true;
        moveLifted(member, scenePoint);
    }

    function moveLifted(member, scenePoint) {
        const point = mapFromItem(null, scenePoint.x, scenePoint.y);
        liftPoint = Qt.point(point.x - member.grabOffset.x, point.y - member.grabOffset.y);
        if (contains(point)) {
            dropSlot = slotAt(point.x);
            host.clearExternal();
            return;
        }
        dropSlot = -1;
        const size = WidgetUtils.clampSize(member.modelData.widget, host.columns, host.maximumRows);
        const gridPoint = host.mapFromItem(null, scenePoint.x, scenePoint.y);
        host.previewExternal({
            "id": member.modelData.widget.id,
            "w": size.w,
            "h": size.h
        }, gridPoint.x - host.cellWidth * size.w / 2, gridPoint.y - host.slotLayout.rowUnit * size.h / 2);
    }

    function drop(member) {
        const savedIndex = member.modelData.index;
        const slot = dropSlot;
        const before = savedIndexAtSlot(slot);
        const position = members.findIndex(other => other.index === savedIndex);
        const unchanged = before === (members[position + 1]?.index ?? -1);
        liftedIndex = -1;
        dropSlot = -1;
        host.memberDragging = false;
        if (slot >= 0) {
            host.clearExternal();
            if (!unchanged)
                Qt.callLater(() => WidgetUtils.moveToGroup(savedIndex, groupId, before));
            return;
        }
        if (!host.externalItem)
            return;
        const placed = host.committedItems();
        const cell = placed.pop();
        const widgets = WidgetUtils.placeFromGroup(host.withHidden(placed), savedIndex, cell.col, cell.row);
        Qt.callLater(() => {
            WidgetUtils.setLayout(widgets);
            host.cancelInteraction();
        });
    }

    Rectangle {
        anchors.fill: parent
        radius: root.bodyRadius
        color: root.receiving ? Theme.withAlpha(Theme.primary, Theme.stateLayerDrag) : "transparent"
        visible: root.editMode
    }

    StyledText {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        text: I18n.tr("Drag small tiles in to group them", "control center quick tiles widget description")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        visible: root.editMode && root.members.length === 0 && root.gapSlot < 0
    }

    Row {
        id: memberRow

        // Leaves the bottom corners to the edit chrome's resize grip.
        readonly property real cornerSize: Theme.minimumTouchTargetSize / 2

        // Every member carries its trailing gap, which sits on the far side in RTL.
        x: (root.width - Math.max(0, implicitWidth - root.gap)) / 2 - (I18n.isRtl ? root.gap : 0)
        anchors.verticalCenter: parent.verticalCenter
        height: CcMetrics.iconBoxSize
        containmentMask: QtObject {
            function contains(point: point): bool {
                if (point.x < 0 || point.y < 0 || point.x >= memberRow.width || point.y >= memberRow.height)
                    return false;
                const local = memberRow.mapToItem(root, point.x, point.y);
                return local.y < root.height - memberRow.cornerSize || (local.x >= memberRow.cornerSize && local.x < root.width - memberRow.cornerSize);
            }
        }

        Repeater {
            id: memberRepeater

            model: root.members

            Item {
                id: member

                required property var modelData
                required property int index
                readonly property bool lifted: root.liftedIndex === modelData.index
                readonly property int position: index - (root.liftedIndex >= 0 && index > root.members.findIndex(other => other.index === root.liftedIndex) ? 1 : 0)
                readonly property bool gapBefore: !lifted && root.gapSlot === position
                readonly property real ownWidth: loader.item?.quickWidth ?? CcMetrics.iconBoxSize
                property point grabOffset: Qt.point(0, 0)

                width: (gapBefore ? root.gapWidth + root.gap : 0) + (lifted ? 0 : ownWidth + root.gap)
                height: memberRow.height
                z: lifted ? 1 : 0

                Behavior on width {
                    enabled: CcMetrics.animationsEnabled && (root.memberDragging || root.receiving)
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                    }
                }

                Rectangle {
                    x: I18n.isRtl ? member.ownWidth + root.gap * 2 : 0
                    width: root.gapWidth
                    height: parent.height
                    radius: Theme.fullRadius(width, height)
                    color: Theme.withAlpha(Theme.primary, Theme.stateLayerDrag)
                    visible: member.gapBefore
                }

                Item {
                    id: body

                    x: {
                        if (member.lifted)
                            return root.liftPoint.x - memberRow.x - member.x;
                        if (I18n.isRtl)
                            return root.gap;
                        return member.gapBefore ? root.gapWidth + root.gap : 0;
                    }
                    y: member.lifted ? root.liftPoint.y - memberRow.y : 0
                    width: member.ownWidth
                    height: memberRow.height

                    Behavior on x {
                        enabled: CcMetrics.animationsEnabled && !member.lifted
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    CcTileLoader {
                        id: loader

                        anchors.fill: parent
                        grid: root.host
                        widgetData: member.modelData.widget
                        savedIndex: member.modelData.index
                        compact: true
                        small: true
                        bare: root.membersBare
                    }

                    DragHandler {
                        id: drag

                        target: null
                        enabled: root.editMode
                        cursorShape: Qt.ClosedHandCursor
                        onActiveChanged: {
                            if (active) {
                                member.grabOffset = centroid.pressPosition;
                                root.lift(member, centroid.scenePosition);
                                return;
                            }
                            if (member.lifted)
                                root.drop(member);
                        }
                        onCentroidChanged: {
                            if (active)
                                root.moveLifted(member, centroid.scenePosition);
                        }
                    }

                    HoverHandler {
                        enabled: root.editMode
                        cursorShape: member.lifted ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    }
                }
            }
        }

        Item {
            width: root.gapSlot >= 0 && root.gapSlot === root.members.length - (root.liftedIndex >= 0 ? 1 : 0) ? root.gapWidth + root.gap : 0
            height: memberRow.height

            Rectangle {
                x: I18n.isRtl ? root.gap : 0
                width: root.gapWidth
                height: parent.height
                radius: Theme.fullRadius(width, height)
                color: Theme.withAlpha(Theme.primary, Theme.stateLayerDrag)
                visible: parent.width > 0
            }
        }
    }
}
