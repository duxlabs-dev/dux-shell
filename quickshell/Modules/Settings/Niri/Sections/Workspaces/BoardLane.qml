pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Rectangle {
    id: root

    property BoardCard board: null
    property int laneIndex: 0
    property var lane: null
    property bool dragging: false
    property bool renaming: false

    readonly property var windows: lane?.windows ?? []
    readonly property bool active: lane?.active ?? false
    // A name from the user's own config.kdl cannot be renamed here: the page would write it a second time.
    readonly property bool renamable: !lane?.name || (board?.isOwned(lane.name) ?? false)

    implicitHeight: Math.max(Theme.iconButtonSize * 4, content.implicitHeight + Theme.spacingS * 2)
    height: implicitHeight
    radius: Theme.cornerRadiusM
    color: Theme.surface
    border.width: Theme.outlineWidthFocused
    // Drop and active share the primary border: one strong color per screen at most.
    border.color: drop.containsDrag || root.active ? Theme.primary : Theme.outlineVariant
    Accessible.role: Accessible.Grouping
    Accessible.name: I18n.tr("Workspace %1, %2 windows").arg(lane?.name || lane?.idx || "").arg(windows.length)

    DropArea {
        id: drop

        anchors.fill: parent
        keys: ["niri-window"]
        onDropped: event => {
            const source = event.source as BoardChip;
            if (!root.lane || !source?.window || source.window.workspace_id === root.lane.id)
                return;
            root.board.moveWindows([source.window.id], root.lane.id);
            event.accept();
        }
    }

    Column {
        id: content

        x: Theme.spacingS
        y: Theme.spacingS
        width: parent.width - Theme.spacingS * 2
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingXS

            Rectangle {
                id: badge

                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeSmall + Theme.spacingXS
                height: width
                radius: width / 2
                color: root.active ? Theme.primary : Theme.surfaceContainerHigh

                StyledText {
                    anchors.centerIn: parent
                    text: String(root.lane?.idx ?? "")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightBold
                    color: root.active ? Theme.onPrimary : Theme.surfaceText
                }
            }

            // Strong name as a button: the rename field only exists while renaming.
            Rectangle {
                id: nameButton

                anchors.verticalCenter: parent.verticalCenter
                visible: !root.renaming
                width: parent.width - badge.width - focusBadge.width - count.width - Theme.spacingXS * 3
                height: Theme.iconButtonSize - Theme.spacingS
                radius: Theme.cornerRadiusS
                color: "transparent"
                activeFocusOnTab: root.renamable
                Accessible.role: Accessible.Button
                Accessible.name: root.renamable ? I18n.tr("Rename workspace %1").arg(root.lane?.idx ?? "") : I18n.tr("Workspace %1").arg(root.lane?.name || root.lane?.output || "")
                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
                        return;
                    if (!root.renamable)
                        return;
                    root.renaming = true;
                    event.accepted = true;
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.surfaceText
                    opacity: nameMouse.pressed ? Theme.stateLayerPressed : nameMouse.containsMouse ? Theme.stateLayerHover : 0
                }

                Row {
                    x: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.spacingXS * 2
                    spacing: Theme.spacingXXS

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - pen.width - Theme.spacingXXS
                        text: root.lane?.name || root.lane?.output || ""
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    DIcon {
                        id: pen

                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.renamable && (nameMouse.containsMouse || nameButton.activeFocus)
                        name: "edit"
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                MouseArea {
                    id: nameMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.renamable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!root.renamable)
                            return;
                        root.renaming = true;
                    }
                }

                FocusRing {
                    anchors.margins: Theme.focusRingWidth / 2
                    radius: nameButton.radius
                }
            }

            DTextField {
                id: nameField

                anchors.verticalCenter: parent.verticalCenter
                visible: root.renaming
                width: parent.width - badge.width - focusBadge.width - count.width - Theme.spacingXS * 3
                text: root.lane?.name ?? ""
                placeholderText: root.lane?.output ?? ""
                maximumLength: 64
                backgroundColor: "transparent"
                // The mockup draws the lane name strong, including the output hint of an unnamed workspace.
                textColor: Theme.surfaceText
                placeholderColor: Theme.surfaceText
                font.weight: Theme.fontWeightBold
                Accessible.name: I18n.tr("Rename workspace %1").arg(root.lane?.idx ?? "")
                onEditingFinished: {
                    if (!root.lane || !root.board.renameLane(root.lane, nameField.text))
                        nameField.text = root.lane?.name ?? "";
                    root.renaming = false;
                }
                onVisibleChanged: {
                    if (!visible)
                        return;
                    forceActiveFocus();
                    selectAll();
                }
            }

            Rectangle {
                id: focusBadge

                anchors.verticalCenter: parent.verticalCenter
                visible: root.active
                width: focusRow.implicitWidth + Theme.spacingXS * 2
                height: Theme.iconSizeSmall + Theme.spacingXS
                radius: height / 2
                color: Theme.primaryContainer

                Row {
                    id: focusRow

                    anchors.centerIn: parent
                    spacing: Theme.spacingXXS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "center_focus_strong"
                        size: Theme.iconSizeSmall - Theme.spacingXXS
                        color: Theme.onPrimaryContainer
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Focus", "niri page workspaces, badge on the active lane")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.onPrimaryContainer
                    }
                }
            }

            StyledText {
                id: count

                anchors.verticalCenter: parent.verticalCenter
                text: String(root.windows.length)
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        StyledText {
            width: parent.width
            visible: root.windows.length === 0
            horizontalAlignment: Text.AlignHCenter
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM
            wrapMode: Text.WordWrap
            text: I18n.tr("Empty. Drop a window here")
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }

        Repeater {
            model: root.windows.length

            BoardChip {
                id: chipItem

                required property int index

                width: content.width
                window: root.windows[chipItem.index] ?? null
                onDraggingChanged: root.dragging = chipItem.dragging
                onStep: dir => {
                    const target = root.board.lanes[root.laneIndex + dir];
                    if (target && chipItem.window)
                        root.board.moveWindows([chipItem.window.id], target.id);
                }
                onCloseRequested: {
                    if (chipItem.window)
                        root.board.closeWindows([chipItem.window.id]);
                }
            }
        }
    }
}
