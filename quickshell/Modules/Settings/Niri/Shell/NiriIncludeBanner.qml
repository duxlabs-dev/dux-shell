pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

// Announces an include the doctor added on its own (with a backup and Undo); it hides itself like the Keep banner.
Rectangle {
    id: root

    property string fragment: ""
    property var health: null

    function announce(fragment, health) {
        root.fragment = fragment;
        root.health = health;
        hideTimer.restart();
    }

    function dismiss() {
        hideTimer.stop();
        root.fragment = "";
        root.health = null;
    }

    // The Undo takes the include and the backup away; the toast only holds the announcement.
    function undo() {
        const health = root.health;
        root.dismiss();
        health?.undoFix();
    }

    visible: fragment !== ""
    opacity: fragment !== "" ? 1 : 0
    width: Math.min(520, (parent ? parent.width : 0) - Theme.spacingL * 2)
    height: visible ? toastColumn.implicitHeight + Theme.spacingL * 2 : 0
    radius: Theme.cornerRadiusL
    color: Theme.surfaceContainerHighest
    border.width: Theme.outlineWidth
    border.color: Theme.primaryContainer
    z: 100
    Accessible.role: Accessible.AlertMessage
    Accessible.name: toastTitle.text

    Behavior on opacity {
        enabled: !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.mediumDuration
            easing.type: Theme.standardEasing
        }
    }

    Timer {
        id: hideTimer
        interval: 10000
        onTriggered: root.dismiss()
    }

    Column {
        id: toastColumn

        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2

        // No anchors on the positioner's axis: a horizontal anchor inside a Row
        // breaks its layout; the title width leaves the button at the right edge.
        Row {
            width: parent.width
            spacing: Theme.spacingS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "add_circle"
                size: Theme.iconSizeMedium
                color: Theme.primary
            }

            StyledText {
                id: toastTitle
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Theme.iconSizeMedium - undoButton.width - Theme.spacingS * 3
                text: I18n.tr("%1 added", "niri page toast, %1 is the config file the doctor just included").arg(root.fragment)
                elide: Text.ElideMiddle
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightBold
                color: Theme.surfaceText
            }

            DButton {
                id: undoButton
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Undo")
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: root.undo()
            }
        }
    }
}
