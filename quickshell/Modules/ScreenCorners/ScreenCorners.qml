pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Variants {
    model: ShellLayout.realScreens

    delegate: PanelWindow {
        id: win

        required property var modelData

        readonly property bool frameOnScreen: FrameTransitionState.effectiveFrameEnabled && SettingsData.isScreenInPreferences(modelData, SettingsData.frameScreenPreferences)
        readonly property bool fullscreenOnScreen: !SettingsData.screenCornersOverFullscreen && (CompositorService.fullscreenToplevelOnScreen(modelData) || CompositorService.visibleNiriFullscreenToplevelOnScreen(modelData))

        screen: modelData
        visible: !frameOnScreen && !fullscreenOnScreen
        color: "transparent"
        mask: Region {}

        WlrLayershell.namespace: "dms:screen-corners"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        ScreenCornerShape {}
    }
}
