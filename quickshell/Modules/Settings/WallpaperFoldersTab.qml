pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Widgets

Item {
    id: root

    property var parentModal: null
    property bool pageActive: false

    property var suggestions: []
    property int suggestRequest: 0
    property string openFolder: ""
    readonly property bool connected: WallpaperLibraryService.connected
    readonly property bool outdated: DMSService.isConnected && DMSService.apiVersion > 0 && DMSService.apiVersion < WallpaperLibraryService.requiredApiVersion
    property var _frozenOrder: null
    readonly property var sortedFolders: {
        const list = WallpaperLibraryService.folders ?? [];
        if (root.openFolder !== "" && _frozenOrder) {
            const byPath = new Map(list.map(f => [f.path, f]));
            const ordered = [];
            for (const p of _frozenOrder) {
                const item = byPath.get(p);
                if (item) {
                    ordered.push(item);
                    byPath.delete(p);
                }
            }
            for (const item of byPath.values())
                ordered.push(item);
            return ordered;
        }
        const order = {
            "light": 1,
            "dark": 2
        };
        return list.slice().sort((a, b) => (order[a?.appearance] ?? 0) - (order[b?.appearance] ?? 0));
    }
    onOpenFolderChanged: _frozenOrder = openFolder !== "" ? sortedFolders.map(f => f.path) : null
    readonly property int folderCount: sortedFolders.length
    readonly property string selectedScreen: SettingsUiState.selectedWallpaperScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    readonly property string listedCurrent: WallpaperLibraryService.listedPath(SessionData.getMonitorWallpaper(selectedScreen))
    readonly property real thumbCellWidth: SettingsMetrics.contentMaxWidth / SettingsMetrics.wallpaperGridColumns

    function loadSuggestions() {
        if (!root.pageActive || !root.connected)
            return;
        const request = ++root.suggestRequest;
        WallpaperLibraryService.suggestFolders(paths => {
            if (request === root.suggestRequest)
                root.suggestions = paths;
        });
    }

    function browse() {
        folderBrowserLoader.active = true;
        (folderBrowserLoader.item as FileBrowserModal)?.open();
    }

    function openGrid(path, keyboard) {
        SettingsUiState.selectedWallpaperFolder = path;
        root.parentModal?.navigateTo("wallpaper_folder", keyboard);
    }

    function remove(path) {
        root.openFolder = "";
        WallpaperLibraryService.removeFolder(path);
    }

    onPageActiveChanged: loadSuggestions()
    onConnectedChanged: loadSuggestions()
    onFolderCountChanged: loadSuggestions()

    Ref {
        service: WallpaperLibraryService
        active: root.parentModal?.shouldBeVisible ?? false
    }

    SettingsPage {
        SettingsNoteRow {
            visible: !root.connected
            text: root.outdated ? I18n.tr("DMS server is outdated (API v%1, expected v%2)", "error toast, %1 is current api version, %2 is required version").arg(DMSService.apiVersion).arg(WallpaperLibraryService.requiredApiVersion) : I18n.tr("%1 not available", "%1 is a folder name").arg("DMS")
        }

        SettingsDeferred {
            SettingsCard {
                tab: "wallpaper"
                tags: ["folders", "directories", "library", "add", "browse"]
                settingKey: "wallpaperFolderAdd"
                iconName: "wallpaper"

                SettingsRow {
                    iconName: "create_new_folder"
                    title: I18n.tr("Add folder", "wallpaper folders page, row that adds a folder to the list")

                    DSplitButton {
                        id: addButton
                        text: I18n.tr("Browse")
                        iconName: "folder_open"
                        enabled: root.connected
                        expanded: suggestMenu.menuVisible
                        onClicked: root.browse()
                        onMenuClicked: {
                            if (!root.suggestions.length)
                                return;
                            suggestMenu.currentValue = "";
                            suggestMenu.openDropdownMenu();
                        }

                        DDropdown {
                            id: suggestMenu
                            showTrigger: false
                            popupAnchorItem: addButton.trailingButton
                            focusReturnTarget: addButton.trailingButton
                            alignPopupRight: !I18n.isRtl
                            options: root.suggestions
                            onValueChanged: value => {
                                if (value)
                                    WallpaperLibraryService.addFolder(value);
                            }
                        }

                        Binding {
                            target: addButton.trailingButton
                            property: "enabled"
                            value: root.connected && root.suggestions.length > 0
                        }
                    }
                }
            }
        }

        SettingsDeferred {
            when: root.folderCount > 0

            SettingsCard {
                tab: "wallpaper"
                tags: ["folders", "directories", "library"]
                settingKey: "wallpaperFolderList"
                title: I18n.tr("Folders", "wallpaper folders card title")

                Repeater {
                    // Count model: toggling a folder replaces the array and must not rebuild the open row
                    model: root.folderCount

                    SettingsFoldRow {
                        id: folderRow

                        required property int index
                        readonly property var folder: root.sortedFolders[index] ?? ({
                                "path": ""
                            })
                        readonly property bool unavailable: WallpaperLibraryService.missing.includes(folder.path)
                        readonly property string name: WallpaperLibraryService.folderName(folder.path)
                        readonly property var paths: open ? WallpaperLibraryService.folderItems(folder.path).map(item => item.path) : []

                        title: name
                        subtitle: unavailable ? I18n.tr("%1 not available", "%1 is a folder name").arg(name) : folder.path
                        subtitleColor: unavailable ? Theme.warning : supportingContentColor
                        iconName: unavailable ? "folder_off" : folder.hidden ? "visibility_off" : folder.appearance === "light" ? "light_mode" : folder.appearance === "dark" ? "dark_mode" : "folder"
                        open: root.openFolder === folder.path
                        onToggled: root.openFolder = open ? "" : folder.path

                        body: Loader {
                            width: parent.width
                            visible: active
                            active: folderRow.open

                            sourceComponent: SettingsGroup {
                                slotColor: SettingsMetrics.controlColor

                                SettingsToggleRow {
                                    iconName: "visibility"
                                    text: I18n.tr("Show", "wallpaper folder option")
                                    checked: !(folderRow.folder.hidden ?? false)
                                    onToggled: checked => WallpaperLibraryService.setFolderHidden(folderRow.folder.path, !checked)
                                }

                                SettingsToggleRow {
                                    iconName: "folder_copy"
                                    text: I18n.tr("Include subfolders", "wallpaper folder option")
                                    checked: folderRow.folder.recursive ?? false
                                    onToggled: checked => WallpaperLibraryService.setFolderRecursive(folderRow.folder.path, checked)
                                }

                                SettingsButtonGroupRow {
                                    iconName: "contrast"
                                    text: I18n.tr("Appearance", "wallpaper folder option: which light/dark mode the folder is used in")
                                    model: [I18n.tr("All", "wallpaper folder used in both light and dark mode"), I18n.tr("Light", "wallpaper folder used in light mode"), I18n.tr("Dark", "wallpaper folder used in dark mode")]
                                    values: ["", "light", "dark"]
                                    value: WallpaperLibraryService.normalizeAppearance(folderRow.folder.appearance)
                                    fallbackValue: ""
                                    onValueSelected: selected => WallpaperLibraryService.setFolderAppearance(folderRow.folder.path, selected)
                                }

                                SettingsRow {
                                    visible: folderRow.paths.length > 0

                                    body: Item {
                                        id: preview

                                        readonly property int columns: Math.max(1, Math.floor(width / root.thumbCellWidth))
                                        readonly property real cellWidth: Math.floor((width + Theme.spacingXS * 2) / columns)

                                        width: parent.width
                                        height: Math.round(cellWidth * SettingsMetrics.wallpaperThumbRatio)
                                        opacity: folderRow.folder.hidden ? SettingsMetrics.disabledOpacity : 1

                                        // Tiles inset their image by spacingXS; the row bleeds by the same so images meet the row edges
                                        Row {
                                            anchors.left: parent.left
                                            anchors.leftMargin: -Theme.spacingXS

                                            Repeater {
                                                model: folderRow.paths.slice(0, preview.columns)

                                                WallpaperThumbTile {
                                                    required property string modelData

                                                    width: preview.cellWidth
                                                    height: preview.height
                                                    path: modelData
                                                    selected: root.listedCurrent === modelData
                                                    onClicked: SessionData.applyWallpaperPick(root.selectedScreen, modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                SettingsRow {
                                    visible: !folderRow.unavailable && WallpaperLibraryService.loaded && folderRow.paths.length === 0
                                    title: I18n.tr("No wallpapers", "empty wallpaper folder")
                                    titleColor: Theme.surfaceVariantText
                                }

                                SettingsNavRow {
                                    visible: folderRow.paths.length > 0
                                    iconName: "grid_view"
                                    title: I18n.tr("Wallpapers", "wallpaper folders settings row")
                                    trailingBadge: String(folderRow.paths.length)
                                    onClicked: keyboard => root.openGrid(folderRow.folder.path, keyboard)
                                }

                                SettingsRow {
                                    DButton {
                                        variant: "tonal"
                                        danger: true
                                        iconName: "delete"
                                        text: I18n.tr("Remove", "remove wallpaper folder tooltip")
                                        onClicked: root.remove(folderRow.folder.path)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    LazyLoader {
        id: folderBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Choose wallpaper folder", "wallpaper folder file browser title")
            bucket: "wallpaper"
            mode: "openFolder"
            showHiddenFiles: true
            onAccepted: paths => WallpaperLibraryService.addFolder(paths[0])
        }
    }
}
