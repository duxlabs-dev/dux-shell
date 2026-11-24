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
    // Forwards navigation keys to the menu while a compositor grab keeps the keyboard elsewhere.
    property bool forwardKeys: false
    readonly property bool open: menu.openState
    readonly property var visibleItems: (items || []).filter(item => item.visible !== false)

    signal closed

    function openAt(anchor, fromKeyboard) {
        const window = root.QsWindow.window;
        const pos = QmlUtils.screenPointOf(window, anchor, 0, 0);
        if (!pos)
            return;

        _anchor = anchor;
        const screen = window.screen;
        menu.targetScreen = screen;
        const x = pos.x;
        const y = pos.y;
        const menuX = I18n.isRtl ? x : x + anchor.width - menu.effectiveMenuWidth;
        const below = y + anchor.height + Theme.spacingXS;
        const menuY = below + menu.effectiveMenuHeight > screen.height - Theme.spacingS ? y - menu.effectiveMenuHeight - Theme.spacingXS : below;
        menu.open(screen, menuX, menuY, !!fromKeyboard);
        if (forwardKeys)
            root.forceActiveFocus();
    }

    function close() {
        menu.hide();
    }

    Keys.onPressed: event => {
        if (!root.forwardKeys || !root.open)
            return;
        switch (event.key) {
        case Qt.Key_Down:
            menu.selectNext();
            break;
        case Qt.Key_Up:
            menu.selectPrevious();
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            menu.activateSelected();
            break;
        case Qt.Key_Escape:
        case Qt.Key_Left:
            menu.hide();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    DContextMenu {
        id: menu
        layerNamespace: "dms:control-center-menu"
        minMenuWidth: CcMetrics.menuMinWidth
        keyboardNavigable: true
        transientSurfaceTracker: root.transientSurfaceTracker
        menuItems: root.visibleItems.map(item => item.type === "separator" ? {
                "type": "separator"
            } : ({
                    type: "item",
                    icon: item.iconName || "",
                    text: item.label || "",
                    trailingIcon: item.trailingIcon || "",
                    keepOpen: item.keepOpen === true,
                    enabled: item.enabled !== false,
                    isDestructive: item.destructive === true,
                    action: () => {
                        if (!item.keepOpen)
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
