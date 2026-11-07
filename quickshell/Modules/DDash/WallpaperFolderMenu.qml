pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Item {
    id: root

    property var transientSurfaceTracker: null
    property Item anchorItem: null
    readonly property bool open: menu.openState
    readonly property int maxPathLength: 48

    signal browseRequested
    signal settingsRequested

    function openAt(anchor, fromKeyboard) {
        const window = root.QsWindow.window as QsWindow;
        const pos = QmlUtils.screenPointOf(window, anchor, 0, 0);
        if (!pos)
            return;

        anchorItem = anchor;
        menu.targetScreen = window.screen;
        const menuX = I18n.isRtl ? pos.x : pos.x + anchor.width - menu.effectiveMenuWidth;
        menu.open(window.screen, menuX, pos.y - Theme.spacingXS, fromKeyboard);
        root.forceActiveFocus();
    }

    function close() {
        menu.hide();
    }

    function shortPath(path) {
        return path.length > maxPathLength ? "…" + path.slice(-maxPathLength) : path;
    }

    // Hyprland's focus grab keeps the keyboard on the Dash window, so the menu's own handler never sees these.
    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Down:
            menu.selectNext();
            event.accepted = true;
            return;
        case Qt.Key_Up:
            menu.selectPrevious();
            event.accepted = true;
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            menu.activateSelected();
            event.accepted = true;
            return;
        case Qt.Key_Escape:
        case Qt.Key_Left:
            menu.hide();
            event.accepted = true;
            return;
        }
    }

    DContextMenu {
        id: menu

        layerNamespace: "dms:wallpaper-folder-menu"
        menuEdge: "bottom"
        keyboardNavigable: true
        itemFontSize: Theme.fontSizeMedium
        transientSurfaceTracker: root.transientSurfaceTracker
        menuItems: {
            const actions = [
                {
                    "type": "item",
                    "icon": "image_search",
                    "text": I18n.tr("Browse", "wallpaper folder menu option"),
                    "action": () => {
                        menu.hide();
                        root.browseRequested();
                    }
                },
                {
                    "type": "item",
                    "icon": "settings",
                    "text": I18n.tr("Settings", "wallpaper folder menu option"),
                    "action": () => {
                        menu.hide();
                        root.settingsRequested();
                    }
                }
            ];
            if (!WallpaperLibraryService.enabled)
                return actions;

            const names = WallpaperLibraryService.folders.map(folder => WallpaperLibraryService.folderName(folder.path));
            const folderRows = WallpaperLibraryService.visibleFolders.map(folder => {
                const name = WallpaperLibraryService.folderName(folder.path);
                return {
                    "type": "item",
                    "icon": "folder",
                    "text": names.indexOf(name) === names.lastIndexOf(name) ? name : root.shortPath(folder.path),
                    "trailingIcon": WallpaperLibraryService.selection.includes(folder.path) ? "check" : "",
                    "keepOpen": true,
                    "action": () => WallpaperLibraryService.toggleSelected(folder.path)
                };
            });
            const separator = {
                "type": "separator"
            };
            return [
                {
                    "type": "item",
                    "icon": "wallpaper",
                    "text": I18n.tr("All", "wallpaper folder menu option"),
                    "trailingIcon": WallpaperLibraryService.filtering ? "" : "check",
                    "keepOpen": true,
                    "action": () => WallpaperLibraryService.clearSelection()
                },
                separator
            ].concat(folderRows, folderRows.length > 0 ? [separator] : [], actions);
        }

        onOpenStateChanged: {
            if (openState)
                return;
            if (root.anchorItem?.visible && root.anchorItem.enabled)
                root.anchorItem.forceActiveFocus();
            root.anchorItem = null;
        }
    }
}
