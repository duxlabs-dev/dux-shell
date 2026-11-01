import QtQuick
import qs.Common
import qs.DCommon.Widgets

// The slot keeps its place in the lane while the chip inside follows the pointer.
Item {
    id: root

    property var window: null
    // Hover/focus reveals the actions; keyboard focus also shows the Alt hint.
    readonly property bool dragging: dragger.active
    readonly property bool actsExposed: chipHover.hovered || root.activeFocus
        || actPrev.activeFocus || actNext.activeFocus || actClose.activeFocus

    signal step(int dir)
    signal closeRequested()

    implicitHeight: Theme.iconButtonSize
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: I18n.tr("%1: %2. Alt+Left or Alt+Right to move").arg(window?.app_id ?? "").arg(window?.title ?? "")
    Keys.onPressed: event => {
        if (!(event.modifiers & Qt.AltModifier))
            return;
        if (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right)
            return;
        event.accepted = true;
        root.step(event.key === Qt.Key_Right ? 1 : -1);
    }

    Rectangle {
        id: chip

        width: root.width
        height: root.height
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        opacity: root.dragging ? 0.7 : 1
        border.width: root.activeFocus || chipHover.hovered ? Theme.outlineWidth : 0
        border.color: root.activeFocus ? Theme.primary : Theme.outlineVariant
        Drag.active: dragger.active
        Drag.keys: ["niri-window"]
        Drag.source: root
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        DragHandler {
            id: dragger
            cursorShape: Qt.ClosedHandCursor
            onActiveChanged: {
                if (active)
                    return;
                chip.Drag.drop();
                chip.x = 0;
                chip.y = 0;
            }
        }

        HoverHandler {
            id: chipHover
            cursorShape: Qt.OpenHandCursor
        }

        Row {
            x: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.spacingS * 2
            spacing: Theme.spacingS

            Rectangle {
                id: dot
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeSmall + Theme.spacingXS
                height: width
                radius: Theme.cornerRadiusS
                color: Theme.surfaceContainerHighest

                StyledText {
                    anchors.centerIn: parent
                    text: (root.window?.app_id ?? "?").charAt(0).toUpperCase()
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightBold
                    color: Theme.surfaceText
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - dot.width - acts.width - Theme.spacingS * 2
                text: root.window?.title || root.window?.app_id || ""
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }

            Row {
                id: acts
                anchors.verticalCenter: parent.verticalCenter
                visible: root.actsExposed
                spacing: Theme.spacingXXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.activeFocus
                    text: I18n.tr("Alt+Left / Right", "niri page workspaces, keyboard hint on a focused window chip")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                DActionButton {
                    id: actPrev
                    iconName: "keyboard_arrow_left"
                    tooltipText: I18n.tr("Move to previous lane", "niri page workspaces, window chip action")
                    onClicked: root.step(-1)
                }

                DActionButton {
                    id: actNext
                    iconName: "keyboard_arrow_right"
                    tooltipText: I18n.tr("Move to next lane", "niri page workspaces, window chip action")
                    onClicked: root.step(1)
                }

                DActionButton {
                    id: actClose
                    iconName: "close"
                    tooltipText: I18n.tr("Close window", "niri page workspaces, window chip action")
                    onClicked: root.closeRequested()
                }
            }
        }
    }
}
