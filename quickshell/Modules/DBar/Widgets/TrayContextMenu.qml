pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

DContextMenu {
    id: root

    property var trayItem: null
    property var bar: null
    readonly property var menuHandle: trayItem?.menu ?? null

    layerNamespace: "dms:tray-context-menu"
    customContentWidth: Theme.fieldDefaultWidth

    onOpenStateChanged: {
        const screenName = root.targetScreen?.name;
        if (!screenName)
            return;
        if (openState) {
            TrayMenuManager.registerMenu(screenName, { close: () => root.hide() });
            customContentItem?.clearState?.();
        } else {
            TrayMenuManager.unregisterMenu(screenName);
            customContentItem?.clearState?.();
        }
    }

    Component.onDestruction: {
        if (openState && root.targetScreen?.name)
            TrayMenuManager.unregisterMenu(root.targetScreen.name);
    }

    onBackdropRightClicked: root.hide()

    function openFor(item, targetX, targetY, screen, edgeOrBottom) {
        let edge = "top";
        if (typeof edgeOrBottom === "string")
            edge = edgeOrBottom;
        else if (edgeOrBottom === true)
            edge = "bottom";
        root.menuEdge = edge;
        trayItem = item;
        const h = item?.menu ?? null;
        if (h && typeof h.updateLayout === "function")
            h.updateLayout();

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
        customContentItem?.clearState?.();
    }

    Timer {
        id: pendingActionCloseTimer
        interval: 80
        repeat: false
        onTriggered: root.hide()
    }

    customContent: Component {
        TrayMenuContent {
            id: contentRoot
            width: root.customContentWidth
            trayItem: root.trayItem
            menuHandle: root.menuHandle
            bar: root.bar
            onCloseRequested: root.hide()
            onActionTriggered: pendingActionCloseTimer.restart()
        }
    }
}
