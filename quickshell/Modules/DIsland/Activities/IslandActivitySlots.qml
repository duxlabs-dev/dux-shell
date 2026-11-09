pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import "../../../Common/IslandActivities.js" as Activities

Item {
    id: root
    required property var controller
    required property string position
    property color foreground: Theme.surfaceText
    readonly property var entries: controller.stableActivities.filter(entry => entry.position === position)
    readonly property bool vertical: controller.isVertical
    readonly property bool occupied: slotModel.count > 0
    readonly property bool activityColors: SettingsData.islandSetting(controller.barConfig, "islandActivityColors") && !SettingsData.islandSetting(controller.barConfig, "islandHighContrast")
    readonly property real endPadding: slotModel.count ? Theme.spacingM : 0
    implicitWidth: vertical ? controller.compactFaceThickness : layout.implicitWidth + endPadding
    implicitHeight: vertical ? layout.implicitHeight + endPadding : controller.compactFaceThickness

    function updateLength() {
        controller.setStableSlotLength(position, slotModel.count ? (vertical ? implicitHeight : implicitWidth) : 0);
    }
    function indexOf(key) {
        for (let i = 0; i < slotModel.count; i++) {
            if (slotModel.get(i).entryKey === key)
                return i;
        }
        return -1;
    }
    function syncEntries() {
        if (!slotModel)
            return;
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            const key = JSON.stringify([entry.source, entry.id]);
            const index = indexOf(key);
            const payload = JSON.stringify(entry);
            if (index < 0) {
                slotModel.append({entryKey: key, payload: payload});
                if (slotModel.count - 1 !== i)
                    slotModel.move(slotModel.count - 1, i, 1);
            } else {
                if (slotModel.get(index).payload !== payload)
                    slotModel.setProperty(index, "payload", payload);
                if (index !== i)
                    slotModel.move(index, i, 1);
            }
        }
        updateLength();
    }
    function removeRetiredSlot(key) {
        if (entries.some(entry => JSON.stringify([entry.source, entry.id]) === key))
            return;
        const index = indexOf(key);
        if (index >= 0)
            slotModel.remove(index);
        updateLength();
    }
    onImplicitWidthChanged: updateLength()
    onImplicitHeightChanged: updateLength()
    onEntriesChanged: syncEntries()
    Component.onCompleted: syncEntries()
    Component.onDestruction: controller.setStableSlotLength(position, 0)

    ListModel {
        id: slotModel
    }

    Grid {
        id: layout
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, repeater.count)
        spacing: Theme.spacingS

        Repeater {
            id: repeater
            model: slotModel

            FadePresence {
                id: slot
                required property string entryKey
                required property string payload
                shown: root.entries.some(entry => JSON.stringify([entry.source, entry.id]) === entryKey)
                onOpacityChanged: {
                    if (!shown && opacity <= 0.001) {
                        const key = entryKey;
                        Qt.callLater(() => root.removeRetiredSlot(key));
                    }
                }
                // Like the home slots: aiming at a click target must not peek the dashboard.
                readonly property bool hoverCounted: slotButton.hovered && enabled
                onHoverCountedChanged: hoverCounted ? root.controller.slotHoverEntered() : root.controller.slotHoverExited()
                Component.onDestruction: {
                    if (hoverCounted)
                        root.controller.slotHoverExited();
                }
                width: root.vertical ? root.controller.compactFaceThickness : Math.min(root.controller.stableSlotMaxLength, face.measuredLength)
                height: root.controller.compactFaceThickness
                Behavior on x {
                    NumberAnimation {
                        duration: SettingsData.reduceMotion ? 0 : Theme.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: SettingsData.reduceMotion ? 0 : Theme.shortDuration
                        easing.type: Easing.OutCubic
                    }
                }

                StyledButton {
                    id: slotButton
                    anchors.fill: parent
                    padding: 0
                    radius: Theme.cornerRadius
                    color: hovered || pressed ? Theme.surfaceTextHover : "transparent"
                    Accessible.name: face.activity?.title ?? ""
                    Accessible.description: face.activity?.subtitle ?? ""
                    onPressed: root.controller.hoverOpenTimer.stop()
                    onClicked: root.controller.openStableEntry(face.activity, true)
                    onPressAndHold: root.controller.expandLiveEntry(face.activity, true)

                    FocusRing {
                        visible: slotButton.visualFocus
                    }

                    contentItem: LiveActivityFace {
                        id: face
                        controller: root.controller
                        activity: root.entries.find(entry => Activities.identity(entry) === slot.entryKey) ?? JSON.parse(slot.payload)
                        foreground: root.activityColors && activity?.foreground ? root.controller.roleForeground(activity.foreground) : root.foreground
                        stable: true
                        trackSize: false
                    }
                }
            }
        }
    }
}
