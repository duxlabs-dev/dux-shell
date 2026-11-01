import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Modules.Plugins

Scope {
    Variants {
        model: DesktopWidgetRegistry.editing ? Quickshell.screens : []

        PanelWindow {
            id: editorWindow

            required property var modelData

            screen: modelData
            visible: true

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "dms:desktop-widget-editor"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: PopoutManager.screenshotActive ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

            color: "transparent"

            FocusScope {
                anchors.fill: parent
                focus: !PopoutManager.screenshotActive

                Keys.onPressed: event => {
                    if (PopoutManager.screenshotActive) {
                        event.accepted = false;
                        return;
                    }
                    if (widgetLayer.handleKey(event))
                        event.accepted = true;
                }
                Keys.onEscapePressed: event => {
                    if (PopoutManager.screenshotActive) {
                        event.accepted = false;
                        return;
                    }
                    overlay.dismiss();
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.backdropColor
                    opacity: Theme.scrimAlpha
                }

                WidgetEditLayer {
                    id: widgetLayer
                    anchors.fill: parent
                    screenName: editorWindow.screen?.name ?? ""
                    editMode: true
                    bottomInset: overlay.fabReserved
                    onOptionsRequested: instanceId => overlay.showOptions(instanceId)
                }

                WidgetEditorOverlay {
                    id: overlay
                    anchors.fill: parent
                    editLayer: widgetLayer
                    onFinished: DesktopWidgetRegistry.editing = false
                }
            }
        }
    }
}
