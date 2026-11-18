import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DockContextMenuBase {
    id: root

    property var dockApps: null

    layerNamespace: "dms:dock-trash-context-menu"

    function showForButton(button, dockHeight, dockScreen, parentDockApps) {
        dockApps = parentDockApps || null;
        options = parentDockApps?.options ?? ({});
        show(button, dockHeight, dockScreen);
    }

    DockTrashMenuItem {
        width: parent.width
        iconName: "folder_open"
        text: I18n.tr("Open Trash")
        onTriggered: {
            TrashService.openTrash(root.options);
            root.close();
        }
    }

    DockTrashMenuItem {
        width: parent.width
        iconName: "delete_forever"
        isDestructive: true
        enabled: !TrashService.isEmpty
        text: TrashService.isEmpty ? I18n.tr("Empty Trash") : I18n.tr("Empty Trash (%1)", "verb, dock trash menu action, %1 is the item count").arg(TrashService.count)
        onTriggered: {
            TrashService.requestEmptyTrash();
            root.close();
        }
    }

    DDivider {
        color: Theme.outlineHeavy
    }

    DockTrashMenuItem {
        width: parent.width
        iconName: "settings"
        text: I18n.tr("Settings")
        onTriggered: {
            SettingsSearchService.navigateToSection("dockTrash");
            PopoutService.openSettingsWithTab("dock_widgets");
            root.close();
        }
    }
}
