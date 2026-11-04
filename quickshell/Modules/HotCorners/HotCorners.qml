pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

// niri only runs Overview from a corner, so DMS puts a 1 px surface in each other active corner.
Variants {
    model: Quickshell.screens

    delegate: Scope {
        id: screenScope

        required property ShellScreen modelData

        Variants {
            model: HotCornerService.zonesFor(screenScope.modelData.name)

            delegate: PanelWindow {
                id: zone

                required property string modelData
                readonly property bool top: modelData.startsWith("top")
                readonly property bool left: modelData.endsWith("left")

                screen: screenScope.modelData
                visible: true
                color: "transparent"
                implicitWidth: 1
                implicitHeight: 1

                WlrLayershell.namespace: "dms:hot-corner"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: zone.top
                    bottom: !zone.top
                    left: zone.left
                    right: !zone.left
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: HotCornerService.trigger(screenScope.modelData.name, zone.modelData)
                }
            }
        }
    }
}
