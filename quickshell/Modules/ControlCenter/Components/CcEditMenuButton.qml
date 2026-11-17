import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.DCommon.Widgets

DActionButton {
    id: root

    property bool canUndo: false
    property bool fixedHeight: false
    // The docked panel has its own Undo button.
    property bool undoInMenu: true
    property var transientSurfaceTracker: null

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

    CcMenu {
        id: menu

        transientSurfaceTracker: root.transientSurfaceTracker
        items: [
            {
                "iconName": "height",
                "label": I18n.tr("Auto height"),
                "trailingIcon": root.fixedHeight ? "" : "check",
                "action": () => root.heightModeRequested(false)
            },
            {
                "iconName": "height",
                "label": I18n.tr("Fixed height"),
                "trailingIcon": root.fixedHeight ? "check" : "",
                "action": () => root.heightModeRequested(true)
            },
            { "type": "separator" },
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
                "destructive": true,
                "action": () => root.clearRequested()
            }
        ]
    }
}
