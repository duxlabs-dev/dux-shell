pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    property bool pageActive: false

    property var suggestions: []
    property int suggestRequest: 0
    readonly property bool connected: WallpaperLibraryService.connected
    readonly property int folderCount: WallpaperLibraryService.folders.length

    function loadSuggestions() {
        if (!root.pageActive || !root.connected)
            return;
        const request = ++root.suggestRequest;
        WallpaperLibraryService.suggestFolders(paths => {
            if (request === root.suggestRequest)
                root.suggestions = paths;
        });
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
            text: I18n.tr("DMS service is not connected", "wallpaper folders page, shown when the DMS background process is unavailable")
        }

        SettingsCard {
            tab: "wallpaper"
            tags: ["folders", "directories", "library"]
            settingKey: "wallpaperFolderList"
            title: I18n.tr("Folders", "wallpaper folders card title")

            Repeater {
                // Count model: toggling a folder replaces the array and must not rebuild the focused row
                model: root.folderCount

                SettingsSplitRow {
                    id: folderRow

                    required property int index
                    readonly property var folder: WallpaperLibraryService.folders[index] ?? ({
                            "path": ""
                        })
                    readonly property bool unavailable: WallpaperLibraryService.missing.includes(folder.path)
                    readonly property string name: WallpaperLibraryService.folderName(folder.path)

                    title: name
                    subtitle: unavailable ? I18n.tr("%1 not available", "%1 is a folder name").arg(name) : folder.path
                    subtitleColor: unavailable ? Theme.warning : supportingContentColor
                    iconName: unavailable ? "folder_off" : folder.hidden ? "visibility_off" : "folder"
                    checked: !folder.hidden
                    onToggled: toggled => WallpaperLibraryService.setFolderHidden(folder.path, !toggled)
                    onNavigated: keyboard => {
                        SettingsUiState.selectedWallpaperFolder = folder.path;
                        root.parentModal?.navigateTo("wallpaper_folder", keyboard);
                    }
                }
            }
        }

        SettingsFabBar {
            DSplitButton {
                id: addButton
                text: I18n.tr("Add", "add a wallpaper folder button")
                iconName: "add"
                enabled: root.connected
                expanded: suggestMenu.menuVisible
                onClicked: {
                    folderBrowserLoader.active = true;
                    (folderBrowserLoader.item as FileBrowserModal)?.open();
                }
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
                    openUpwards: true
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
