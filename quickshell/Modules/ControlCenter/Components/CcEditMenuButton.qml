import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.DCommon.Widgets

DActionButton {
    id: root

    property bool canUndo: false
    property bool fixedHeight: false
    property bool heightModes: true
    property bool clearable: true
    property var extraItems: []
    // The docked panel has its own Undo button.
    property bool undoInMenu: true
    property var transientSurfaceTracker: null

    readonly property bool menuOpen: menu.open

    signal undoRequested
    signal resetRequested
    signal clearRequested
    signal heightModeRequested(bool fixed)

    buttonSize: Theme.iconButtonSize
    iconName: "more_horiz"
    iconSize: CcMetrics.iconBoxIconSize
    iconColor: Theme.onSecondaryContainer
    backgroundColor: Theme.secondaryContainer
    tooltipText: I18n.tr("More")
    onClicked: menu.openAt(root)

    function closeMenu() {
        menu.close();
    }

    CcMenu {
        id: menu

        transientSurfaceTracker: root.transientSurfaceTracker
        items: [
            {
                "iconName": "height",
                "label": I18n.tr("Auto height"),
                "visible": root.heightModes,
                "trailingIcon": root.fixedHeight ? "" : "check",
                "action": () => root.heightModeRequested(false)
            },
            {
                "iconName": "height",
                "label": I18n.tr("Fixed height"),
                "visible": root.heightModes,
                "trailingIcon": root.fixedHeight ? "check" : "",
                "action": () => root.heightModeRequested(true)
            },
            {
                "type": "separator",
                "visible": root.heightModes
            },
            {
                "iconName": "undo",
                "label": I18n.tr("Undo"),
                "visible": root.undoInMenu,
                "enabled": root.canUndo,
                "action": () => root.undoRequested()
            },
            {
                "iconName": "settings_backup_restore",
                "label": I18n.tr("Reset to default"),
                "action": () => root.resetRequested()
            },
            {
                "iconName": "clear_all",
                "label": I18n.tr("Clear All"),
                "visible": root.clearable,
                "destructive": true,
                "action": () => root.clearRequested()
            }
        ].concat(root.extraItems.some(item => item.visible !== false) ? [{ "type": "separator" }] : [], root.extraItems)
    }
}
