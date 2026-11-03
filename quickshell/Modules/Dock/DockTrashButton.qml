import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root
    required property var options

    clip: false

    property var dockApps: null
    property var contextMenu: null
    property var parentDockScreen: null
    property real actualIconSize: 40
    readonly property real hoverAnimOffset: hoverBounce.offset

    DockHoverBounce {
        id: hoverBounce
        hovered: root.isHovered
        suppressed: mouseArea.pressed
        barHosted: root.dockApps?.barHosted ?? false
        position: root.options.position
        distance: root.actualIconSize
    }

    readonly property bool isHovered: mouseArea.containsMouse
    readonly property bool showTooltip: mouseArea.containsMouse
    readonly property string tooltipText: TrashService.isEmpty ? I18n.tr("Trash", "noun, trash can dock button tooltip and widget name") : (I18n.tr("Trash") + " (" + TrashService.count + ")")

    readonly property bool isVertical: root.options.position === SettingsData.Position.Left || root.options.position === SettingsData.Position.Right

    function activate() {
        TrashService.openTrash(root.options);
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            switch (mouse.button) {
            case Qt.LeftButton:
                TrashService.openTrash(root.options);
                break;
            case Qt.RightButton:
                if (contextMenu)
                    contextMenu.showForButton(root, root.height, parentDockScreen, dockApps);
                break;
            }
        }
    }

    Item {
        anchors.fill: parent

        transform: Translate {
            x: isVertical ? hoverAnimOffset : 0
            y: isVertical ? 0 : hoverAnimOffset
        }

        Item {
            anchors.centerIn: parent
            width: actualIconSize - 4
            height: actualIconSize - 4
            scale: root.options?.enlargeOnHover && root.isHovered ? (root.options?.enlargePercentage ?? 125) / 100 : 1

            readonly property string iconPath: Paths.resolveIconPath(TrashService.isEmpty ? "user-trash" : "user-trash-full")

            IconImage {
                id: trashIcon
                anchors.fill: parent
                source: parent.iconPath
                backer.sourceSize: Qt.size(parent.width * 2, parent.height * 2)
                smooth: true
                mipmap: true
                asynchronous: true
                visible: status === Image.Ready
            }

            DIcon {
                anchors.centerIn: parent
                visible: parent.iconPath === "" || trashIcon.status !== Image.Ready
                name: "delete"
                size: actualIconSize - 8
                color: TrashService.isEmpty ? Theme.surfaceText : Theme.primary
            }
        }
    }
}
