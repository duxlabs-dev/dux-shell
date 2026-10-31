import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets
import qs.Services

PanelWindow {
    id: root

    property var modelData: CompositorService.getFocusedScreen()
    readonly property real shadowBuffer: 5
    readonly property real dpr: modelData ? CompositorService.getScreenScale(modelData) : 1

    WlrLayershell.namespace: "dms:profile-capture"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 0

    Component.onCompleted: KeyboardFocus.registerGrabPeerWindow(root)
    Component.onDestruction: KeyboardFocus.unregisterGrabPeerWindow(root)

    screen: modelData
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.margins.bottom: Math.max(0, Theme.snap(Theme.spacingL - shadowBuffer, dpr))

    implicitHeight: Theme.px(pill.height + shadowBuffer * 2, dpr)

    mask: Region {
        item: pill
    }

    Rectangle {
        id: pill

        x: Theme.snap((root.width - width) / 2, root.dpr)
        y: root.shadowBuffer
        width: content.width + Theme.spacingM * 2
        height: content.height + Theme.spacingS * 2
        radius: height / 2
        color: Theme.readableSurface

        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel3
            fallbackOffset: 6
            targetRadius: pill.radius
            targetColor: pill.color
            shadowOpacity: Theme.elevationLevel3 && Theme.elevationLevel3.alpha !== undefined ? Theme.elevationLevel3.alpha : 0.3
            shadowEnabled: Theme.elevationEnabled
        }

        Row {
            id: content

            anchors.centerIn: parent
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "photo_camera"
                color: Theme.surfaceText
            }

            DButton {
                text: I18n.tr("Cancel")
                backgroundColor: "transparent"
                textColor: Theme.surfaceText
                onClicked: ConfigProfileService.cancelScreenshot()
            }

            DButton {
                text: I18n.tr("Take screenshot", "config profile image: take a screenshot of the current screen")
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: ConfigProfileService.captureScreenshot()
            }
        }
    }
}
