pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

// Edge strip to trigger launcher hover-reveal when free of panel bars and dock.
Variants {
    id: root

    model: ShellLayout.realScreens

    delegate: Loader {
        id: zoneLoader

        required property var modelData

        readonly property string emergeSide: SettingsData.frameLauncherEmergeSide || "bottom"
        readonly property bool eligible: SettingsData.frameEnabled && SettingsData.frameLauncherEdgeHover && Theme.isConnectedEffect && SettingsData.isScreenInPreferences(zoneLoader.modelData, SettingsData.frameScreenPreferences) && CompositorService.usesConnectedFrameChromeForScreen(zoneLoader.modelData) && !SettingsData.barOccupiesSide(zoneLoader.modelData, zoneLoader.emergeSide) && !SettingsData.dockOccupiesSide(zoneLoader.modelData, zoneLoader.emergeSide)

        active: eligible
        asynchronous: false

        sourceComponent: PanelWindow {
            id: zoneWindow

            readonly property bool vertical: zoneLoader.emergeSide === "left" || zoneLoader.emergeSide === "right"
            readonly property real triggerThickness: Math.max(6, SettingsData.frameThickness)
            readonly property bool launcherOpen: (PopoutService.dankLauncherV2Modal?.spotlightOpen ?? false) || (PopoutService.dankIslandRouter?.launcherOpen ?? false)
            property bool _openedForCurrentHover: false

            // Hot zone dimensions centered on the emerge edge to cover the launcher footprint.
            readonly property real _launcherBaseW: SettingsData.dankLauncherV2Size === "micro" ? 500 : (SettingsData.dankLauncherV2Size === "medium" ? 720 : (SettingsData.dankLauncherV2Size === "large" ? 860 : 620))
            readonly property real _launcherBaseH: SettingsData.dankLauncherV2Size === "micro" ? 480 : (SettingsData.dankLauncherV2Size === "medium" ? 720 : (SettingsData.dankLauncherV2Size === "large" ? 860 : 600))
            readonly property real screenW: zoneLoader.modelData?.width ?? 0
            readonly property real screenH: zoneLoader.modelData?.height ?? 0
            readonly property real spanW: Math.round(Math.min(_launcherBaseW, screenW - 100) * 1.1)
            readonly property real spanH: Math.round(Math.min(_launcherBaseH, screenH - 100) * 1.1)

            function requestLauncherOpen() {
                if (launcherOpen || _openedForCurrentHover)
                    return;
                _openedForCurrentHover = true;
                PopoutService.openDankLauncherV2(false, true);
            }

            screen: zoneLoader.modelData
            color: "transparent"

            WlrLayershell.namespace: "dms:frame-launcher-hover"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Anchor and center the hover zone alignment with the launcher.
            anchors {
                top: zoneLoader.emergeSide === "top" || zoneWindow.vertical
                bottom: zoneLoader.emergeSide === "bottom"
                left: zoneLoader.emergeSide === "left" || !zoneWindow.vertical
                right: zoneLoader.emergeSide === "right"
            }

            margins {
                left: zoneWindow.vertical ? 0 : Math.max(0, (zoneWindow.screenW - zoneWindow.spanW) / 2)
                top: zoneWindow.vertical ? Math.max(0, (zoneWindow.screenH - zoneWindow.spanH) / 2) : 0
            }

            implicitWidth: zoneWindow.vertical ? zoneWindow.triggerThickness : zoneWindow.spanW
            implicitHeight: zoneWindow.vertical ? zoneWindow.spanH : zoneWindow.triggerThickness

            MouseArea {
                id: edgeHoverArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                onContainsMouseChanged: {
                    if (containsMouse)
                        zoneWindow.requestLauncherOpen();
                    else
                        zoneWindow._openedForCurrentHover = false;
                }
                onPositionChanged: {
                    if (containsMouse)
                        zoneWindow.requestLauncherOpen();
                }
            }
        }
    }
}
