pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter
import qs.Widgets
import "../../../Common/QmlUtils.js" as QmlUtils

Item {
    id: root

    property var items: []
    property var transientSurfaceTracker: null
    property Item _anchor: null
    readonly property bool open: menu.openState
    readonly property var visibleItems: (items || []).filter(item => item.visible !== false)

    signal closed

    function openAt(anchor) {
        const window = root.QsWindow.window;
        const pos = QmlUtils.screenPointOf(window, anchor, 0, 0);
        if (!pos)
            return;

        _anchor = anchor;
        const screen = window.screen;
        const x = pos.x;
        const y = pos.y;
        const menuX = I18n.isRtl ? x : x + anchor.width - menu.effectiveMenuWidth;
        const below = y + anchor.height + Theme.spacingXS;
        const menuY = below + menu.effectiveMenuHeight > screen.height - Theme.spacingS ? y - menu.effectiveMenuHeight - Theme.spacingXS : below;
        menu.open(screen, menuX, menuY, false);
    }

    function close() {
        menu.hide();
    }

    DContextMenu {
        id: menu
        layerNamespace: "dms:control-center-menu"
        minMenuWidth: CcMetrics.menuMinWidth
        keyboardNavigable: true
        transientSurfaceTracker: root.transientSurfaceTracker
        menuItems: root.visibleItems.map(item => ({
                    type: "item",
                    icon: item.iconName || "",
                    text: item.label || "",
                    enabled: item.enabled !== false,
                    isDestructive: item.destructive === true,
                    action: () => {
                        menu.hide();
                        if (typeof item.action === "function")
                            item.action();
                    }
                }))

        onOpenStateChanged: {
            if (openState)
                return;
            root.closed();
            if (root._anchor?.visible && root._anchor.enabled)
                root._anchor.forceActiveFocus();
            root._anchor = null;
        }
    }
}
