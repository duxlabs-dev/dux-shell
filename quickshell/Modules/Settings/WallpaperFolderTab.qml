pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.ControlCenter.Widgets
import qs.Modules.Settings.Widgets
import qs.Widgets

Item {
    id: root

    property var parentModal: null

    readonly property var folder: WallpaperLibraryService.folders.find(entry => entry.path === SettingsUiState.selectedWallpaperFolder) ?? null
    readonly property var entries: folder ? WallpaperLibraryService.folderItems(folder.path) : []
    readonly property var paths: entries.map(item => item.path)
    readonly property bool missing: folder !== null && WallpaperLibraryService.missing.includes(folder.path)
    readonly property string selectedScreen: SettingsUiState.selectedWallpaperScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    readonly property string currentWallpaper: SessionData.getMonitorWallpaper(selectedScreen)
    readonly property string listedCurrent: WallpaperLibraryService.listedPath(currentWallpaper)
    readonly property real thumbCellWidth: SettingsMetrics.contentMaxWidth / SettingsMetrics.wallpaperGridColumns
    readonly property real columnWidth: Math.min(SettingsMetrics.contentMaxWidth, width)

    function focusCurrent() {
        const index = root.paths.indexOf(root.listedCurrent);
        if (index >= 0)
            grid.currentIndex = index;
    }

    onListedCurrentChanged: focusCurrent()
    Component.onCompleted: focusCurrent()

    function pick(path) {
        if (path)
            SessionData.applyWallpaperPick(root.selectedScreen, path);
    }

    Ref {
        service: WallpaperLibraryService
        active: root.parentModal?.shouldBeVisible ?? false
    }

    DGridView {
        id: grid

        visible: root.folder !== null
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.columnWidth
        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / root.thumbCellWidth)))
        cellHeight: Math.round(cellWidth * SettingsMetrics.wallpaperThumbRatio)
        clip: true
        activeFocusOnTab: count > 0
        highlight: WallpaperThumbHighlight {
            visible: grid.activeFocus
        }
        footer: Item {
            height: SettingsMetrics.pagePaddingV
        }
        model: ScriptModel {
            values: root.paths
            // Emitted after the model applies the new paths, so the index lands on the updated grid.
            onValuesChanged: root.focusCurrent()
        }

        Keys.onSpacePressed: root.pick(root.paths[currentIndex])
        Keys.onEnterPressed: root.pick(root.paths[currentIndex])
        Keys.onReturnPressed: root.pick(root.paths[currentIndex])

        delegate: WallpaperThumbTile {
            required property string modelData
            required property int index

            readonly property var entry: root.entries[index] ?? null
            readonly property var sizeSource: entry && entry.variants ? entry.variants[0] : entry

            path: modelData
            selected: root.listedCurrent === modelData
            mismatched: entry !== null && !WallpaperLibraryService.fits(entry, root.selectedScreen)
            mismatchedOpacity: SettingsMetrics.disabledOpacity
            sizeText: sizeSource?.width ? sizeSource.width + "×" + sizeSource.height : ""
            opacity: root.folder?.hidden ? SettingsMetrics.disabledOpacity : 1
            onClicked: {
                grid.currentIndex = index;
                root.pick(modelData);
            }
        }
    }

    CcEmptyState {
        anchors.top: parent.top
        anchors.topMargin: SettingsMetrics.cardGap
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.folder === null || root.missing || (WallpaperLibraryService.loaded && root.paths.length === 0)
        iconName: "folder_off"
        title: root.missing ? I18n.tr("%1 not available", "%1 is a folder name").arg(WallpaperLibraryService.folderName(root.folder.path)) : I18n.tr("No wallpapers", "empty wallpaper folder")
    }
}
