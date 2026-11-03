import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.DCommon.Widgets

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: identifyWindow

        required property var modelData
        readonly property var outputData: DisplayConfigState.allOutputs[screen.name]
        readonly property string displayName: DisplayConfigState.getOutputDisplayName(outputData, screen.name)

        screen: modelData
        visible: true
        color: "transparent"

        WlrLayershell.namespace: "dms:monitor-identify"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {}

        Item {
            anchors.fill: parent
            opacity: 0

            Component.onCompleted: opacity = 1

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.expressiveDurations.expressiveEffects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                }
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.primary
                border.width: 4
            }

            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: identifyLabel.implicitWidth + Theme.spacingL * 2
                height: identifyLabel.implicitHeight + Theme.spacingS * 2
                color: Theme.primary
                bottomLeftRadius: Theme.cornerRadius
                bottomRightRadius: Theme.cornerRadius

                StyledText {
                    id: identifyLabel
                    anchors.centerIn: parent
                    text: {
                        const phys = DisplayConfigState.getPhysicalSize(identifyWindow.outputData);
                        const res = phys.w + "x" + phys.h;
                        if (identifyWindow.displayName === identifyWindow.screen.name)
                            return identifyWindow.displayName + "  •  " + res;
                        return identifyWindow.displayName + "  (" + identifyWindow.screen.name + ")  •  " + res;
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.primaryText
                }
            }
        }
    }
}
