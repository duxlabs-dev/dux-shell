pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../../Common/ScreenCorners.js" as CornerLogic

PanelWindow {
    id: root

    required property var targetScreen
    required property var corner

    screen: targetScreen

    readonly property bool fullscreen: CompositorService.fullscreenToplevelOnScreen(targetScreen) || CompositorService.visibleNiriFullscreenToplevelOnScreen(targetScreen)

    visible: CornerLogic.modeVisible(SettingsData.screenCornerMode, fullscreen)

    WlrLayershell.namespace: "dms:screen-corners"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    color: "transparent"
    // Empty input region: corner wedges never take clicks or reserve screen edges.
    mask: Region { id: inputMask }

    implicitWidth: cornerWidget.implicitWidth
    implicitHeight: cornerWidget.implicitHeight

    readonly property var edges: CornerLogic.anchorsFor(corner)

    anchors { left: edges.left; top: edges.top; right: edges.right; bottom: edges.bottom }

    RoundCorner {
        id: cornerWidget
        anchors.fill: parent
        corner: root.corner
    }
}
