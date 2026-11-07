pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import qs.Common
import qs.Modules.Plugins

// The real lock widgets laid out at screen size and scaled down. Demo mode keeps them inert and the
// thumb's MouseArea above takes all clicks; disabling them instead would grey them out.
Item {
    id: root

    required property var screen
    property bool active: true

    readonly property real screenWidth: screen?.width ?? 1
    readonly property real screenHeight: screen?.height ?? 1

    Rectangle {
        anchors.fill: parent
        color: Theme.screenOffColor
        opacity: Theme.lockScreenScrimAlpha
    }

    Loader {
        active: root.active && root.screen !== null && root.width > 0

        sourceComponent: Item {
            id: host

            readonly property bool demoMode: true
            readonly property bool greeterPreview: false
            readonly property var pam: null
            readonly property bool unlocking: false
            readonly property string pamState: ""
            readonly property string passwordBuffer: ""
            readonly property bool inputRevealed: false
            property Item authWidget: null

            signal authFailed

            function contentColor(mode, custom) {
                switch (mode) {
                case "primary":
                    return Theme.primary;
                case "secondary":
                    return Theme.secondary;
                case "custom":
                    return custom;
                }
                return Theme.lockScreenContentColor;
            }

            function setInputRevealed(revealed) {
            }

            function passwordEdited(text) {
            }

            function showPowerMenu() {
            }

            width: root.screenWidth
            height: root.screenHeight
            scale: root.width / root.screenWidth
            transformOrigin: Item.TopLeft

            // Render into a thumbnail-sized texture instead of a screen-sized one.
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.ceil(root.width * Screen.devicePixelRatio), Math.ceil(root.height * Screen.devicePixelRatio))

            WidgetEditLayer {
                anchors.fill: parent
                focus: false
                screenName: root.screen.name
                lockScreen: true
                lockHost: host
                preview: true
            }
        }
    }
}
