pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

DContextMenu {
    id: root

    property var hiddenItems: []
    property var contextMenu: null
    property var parentScreen: null

    signal itemActivated(var item)

    layerNamespace: "dms:tray-overflow-menu"
    minMenuWidth: 0

    readonly property real iconSize: Theme.iconSizeSmall
    readonly property real itemSize: iconSize + Theme.spacingS
    readonly property real iconSpacing: Theme.spacingXXS
    readonly property int cols: Math.min(5, Math.max(1, hiddenItems.length))

    customContentWidth: cols * itemSize + (cols - 1) * iconSpacing + menuPadding * 2

    function openAt(targetX, targetY, screen, edge) {
        root.menuEdge = edge || "top";
        parentScreen = screen;
        let menuX = targetX;
        let menuY = targetY;

        switch (edge) {
        case "bottom":
            menuX = targetX - effectiveMenuWidth / 2;
            menuY = targetY - Theme.spacingXS;
            break;
        case "left":
            menuX = targetX + Theme.spacingXS;
            menuY = targetY;
            break;
        case "right":
            menuX = targetX - Theme.spacingXS;
            menuY = targetY;
            break;
        case "top":
        default:
            menuX = targetX - effectiveMenuWidth / 2;
            menuY = targetY + Theme.spacingXS;
            break;
        }

        root.open(screen, menuX, menuY, false);
        root.originX = targetX;
        root.originY = targetY;
    }

    customContent: Component {
        TrayOverflowGrid {
            items: root.hiddenItems
            customColumns: root.cols
            customIconSize: root.iconSize
            customItemSize: root.itemSize
            customSpacing: root.iconSpacing

            onItemClicked: (item, mouse, itemArea) => {
                if (!item)
                    return;
                const screen = root.parentScreen;

                if (mouse.button === Qt.RightButton) {
                    if (item.hasMenu && root.contextMenu) {
                        root.itemActivated(item);
                        root.hide();
                        root.contextMenu.openFor(item, root.originX, root.originY, screen, root.menuEdge);
                        return;
                    }
                    const gp = itemArea.mapToGlobal(mouse.x, mouse.y);
                    TrayMenuManager.callContextMenuFallback(item.id, gp.x, gp.y);
                    root.hide();
                    return;
                }

                if (!item.onlyMenu) {
                    item.activate();
                    root.hide();
                    return;
                }
                if (item.hasMenu && root.contextMenu) {
                    root.itemActivated(item);
                    root.hide();
                    root.contextMenu.openFor(item, root.originX, root.originY, screen, root.menuEdge);
                }
            }
        }
    }
}
