pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Scope {
    id: root
    readonly property var log: Log.scoped("LockScreenDemo")

    property bool demoActive: false
    property bool greeterPreview: false

    function showDemo(greeter = false): void {
        log.debug("Showing lock screen demo", greeter ? "(greeter)" : "");
        greeterPreview = greeter;
        demoActive = true;
    }

    function hideDemo(): void {
        log.debug("Hiding lock screen demo");
        demoActive = false;
    }

    Variants {
        model: root.demoActive ? Quickshell.screens : []

        PanelWindow {
            id: demoWindow

            required property var modelData

            screen: modelData
            visible: true

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "dms:lock-demo"
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: PopoutManager.screenshotActive ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

            color: "transparent"

            LockScreenContent {
                anchors.fill: parent
                demoMode: true
                greeterPreview: root.greeterPreview
                screenName: demoWindow.screen?.name ?? ""
                onUnlockRequested: root.hideDemo()
            }
        }
    }
}
