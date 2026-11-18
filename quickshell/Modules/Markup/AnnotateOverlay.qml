pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

// Live annotation: draws over the running desktop of one screen, so the marks show up in a screen share.
Scope {
    id: root

    property string screenName: ""
    // Clicks reach the windows beneath while the marks stay up.
    property bool passthrough: false
    readonly property var targetScreen: Quickshell.screens.find(s => s.name === screenName) ?? null

    signal dismissed

    function start() {
        screenName = CompositorService.getFocusedScreen()?.name ?? "";
        return screenName !== "";
    }

    function setPassthrough(on) {
        layer.commitText();
        passthrough = on;
    }

    onTargetScreenChanged: {
        if (screenName && !targetScreen)
            dismissed();
    }

    PanelWindow {
        id: win

        screen: root.targetScreen
        visible: root.targetScreen !== null
        color: "transparent"
        mask: root.passthrough ? toolbarMask : null

        WlrLayershell.namespace: "dms:annotate"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: root.passthrough ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Region {
            id: toolbarMask
            item: toolbar
        }

        Shortcut {
            sequences: ["Escape"]
            enabled: !layer.editingText
            onActivated: root.dismissed()
        }
        Shortcut {
            sequences: [StandardKey.Undo]
            onActivated: layer.undo()
        }
        Shortcut {
            sequences: [StandardKey.Redo, "Ctrl+Y"]
            onActivated: layer.redo()
        }

        AnnotationLayer {
            id: layer

            anchors.fill: parent
            enabled: !root.passthrough
        }

        Rectangle {
            id: toolbar

            x: (win.width - width) / 2
            y: win.height - height - Theme.spacingL
            width: toolbarRow.implicitWidth + Theme.spacingS * 2
            height: toolbarRow.implicitHeight + Theme.spacingS * 2
            radius: Theme.fullRadius(width, height)
            color: Theme.readableSurface
            // Shrinks to fit an output narrower than the tools.
            scale: Math.min(1, (win.width - Theme.spacingL * 2) / width)
            transformOrigin: Item.Bottom

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: mouse => mouse.accepted = true
            }

            Row {
                id: toolbarRow

                anchors.centerIn: parent
                spacing: Theme.spacingXS

                MarkupToolbar {
                    visible: !root.passthrough
                    target: layer
                }

                DActionButton {
                    visible: !root.passthrough
                    iconName: "delete_sweep"
                    iconSize: Theme.chipIconSize
                    iconColor: Theme.surfaceText
                    enabled: layer.shapes.length > 0
                    tooltipText: I18n.tr("Clear All")
                    onClicked: {
                        layer.commitText();
                        layer.commit([], null);
                    }
                }

                DActionButton {
                    iconName: "mouse"
                    iconSize: Theme.chipIconSize
                    iconColor: root.passthrough ? Theme.onPrimaryContainer : Theme.surfaceText
                    backgroundColor: root.passthrough ? Theme.primaryContainer : "transparent"
                    tooltipText: root.passthrough ? I18n.tr("Resume drawing", "live annotation, takes the pointer back to draw") : I18n.tr("Interact with windows", "live annotation, lets clicks through to the desktop")
                    onClicked: root.setPassthrough(!root.passthrough)
                }

                DDivider {
                    vertical: true
                    height: Theme.chipIconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                DActionButton {
                    iconName: "close"
                    iconSize: Theme.chipIconSize
                    iconColor: Theme.error
                    tooltipText: I18n.tr("Close")
                    onClicked: root.dismissed()
                }
            }
        }
    }
}
