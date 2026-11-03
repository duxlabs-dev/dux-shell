pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.DBar
import qs.Services

Item {
    id: host

    required property var frameWindow
    required property var targetScreen

    readonly property string screenName: targetScreen ? targetScreen.name : ""

    readonly property var barSlots: ShellLayout.frameKeys(targetScreen)

    ScriptModel {
        id: slotModel
        values: host.barSlots
    }

    Repeater {
        model: slotModel

        delegate: Item {
            id: slot

            required property var modelData

            readonly property var layoutInstance: ShellLayout.instance(modelData)
            readonly property string edge: layoutInstance?.edge ?? "top"
            readonly property string barId: JSON.parse(modelData)[1]
            readonly property var dankBarItem: BarWidgetService.dankBarItems[slot.barId] ?? null
            readonly property var slotBarConfig: dankBarItem?.barConfig ?? SettingsData.getBarConfig(slot.barId)
            readonly property int rowThickness: layoutInstance?.rowThickness ?? 0
            readonly property int rowOffset: layoutInstance?.rowOffset ?? 0

            x: {
                switch (edge) {
                case "left":
                    return rowOffset;
                case "right":
                    return host.frameWindow._windowRegionWidth - rowOffset - rowThickness;
                default:
                    return 0;
                }
            }
            y: {
                switch (edge) {
                case "top":
                    return rowOffset;
                case "bottom":
                    return host.frameWindow._windowRegionHeight - rowOffset - rowThickness;
                default:
                    return 0;
                }
            }
            width: (edge === "left" || edge === "right") ? rowThickness : host.frameWindow._windowRegionWidth
            height: (edge === "top" || edge === "bottom") ? rowThickness : host.frameWindow._windowRegionHeight

            Loader {
                anchors.fill: parent
                active: slot.dankBarItem !== null && slot.slotBarConfig !== null

                sourceComponent: DBarBody {
                    hostWindow: host.frameWindow
                    modelData: host.targetScreen
                    rootWindow: slot.dankBarItem
                    barConfig: slot.slotBarConfig
                    hostOffsetX: slot.x
                    hostOffsetY: slot.y
                    leftWidgetsModel: slot.dankBarItem?.leftWidgetsModel ?? null
                    centerWidgetsModel: slot.dankBarItem?.centerWidgetsModel ?? null
                    rightWidgetsModel: slot.dankBarItem?.rightWidgetsModel ?? null

                    property string registeredScreen: ""
                    property string registeredBar: ""
                    Component.onCompleted: {
                        registeredScreen = host.screenName;
                        registeredBar = slot.barId;
                        BarWidgetService.registerFrameBar(registeredScreen, registeredBar, this);
                    }
                    Component.onDestruction: BarWidgetService.unregisterFrameBar(registeredScreen, registeredBar, this)
                }
            }
        }
    }
}
