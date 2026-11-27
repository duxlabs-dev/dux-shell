pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../Common/Format.js" as Format

PanelWindow {
    id: root

    property int remainingSeconds: 0

    // the surface holds the keyboard on every screen, so each way out hides it before it asks the service for anything
    function updateRemaining() {
        remainingSeconds = Math.max(0, Math.ceil((BreakReminderService.breakEndsAt - Date.now()) / 1000));
        if (remainingSeconds <= 0)
            visible = false;
    }

    function skip() {
        visible = false;
        BreakReminderService.skip();
    }

    function snooze() {
        visible = false;
        BreakReminderService.snooze();
    }

    color: Theme.surface

    WlrLayershell.namespace: "dms:break-reminder"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    Component.onCompleted: {
        updateRemaining();
        keyScope.forceActiveFocus();
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.updateRemaining()
    }

    FocusScope {
        id: keyScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.skip()

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingL

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "self_improvement"
                size: Theme.fontSizeDisplayLarge
                color: Theme.primary
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: BreakReminderService.kind === "long" ? I18n.tr("Long break", "break reminder overlay title") : I18n.tr("Short break", "break reminder overlay title")
                font.pixelSize: Theme.fontSizeXXLarge
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            NumericText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Format.formatDuration(root.remainingSeconds)
                font.pixelSize: Theme.fontSizeDisplayLarge
                font.weight: Theme.fontWeightBold
                font.features: {
                    "tnum": 1
                }
                color: Theme.primary
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS

                DButton {
                    variant: "tonal"
                    iconName: "snooze"
                    text: I18n.tr("Snooze", "break reminder action, delay the break by a few minutes")
                    onClicked: root.snooze()
                }

                DButton {
                    variant: "tonal"
                    iconName: "skip_next"
                    text: I18n.tr("Skip")
                    onClicked: root.skip()
                }
            }
        }
    }
}
