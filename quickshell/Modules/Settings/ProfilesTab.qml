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

    readonly property var screenInfo: parentModal?.screen ?? Quickshell.screens[0] ?? null

    Component.onCompleted: ConfigProfileService.ensureDefault()

    Connections {
        target: ConfigProfileService
        function onProfileImported(id) {
            grid.openPage("profile_edit", id, true);
        }
    }

    SettingsPage {
        SettingsCard {
            tab: "profiles"
            settingKey: "configProfilePicker"
            iconName: "tune"
            title: I18n.tr("Behavior", "settings card title: config profile picker options")

            SettingsDropdownRow {
                readonly property var views: ["carousel", "grid", "dash"]
                readonly property bool inIsland: PopoutService.dashRoutesToIsland("profiles", root.screenInfo)
                readonly property var labels: [I18n.tr("Carousel", "config profile picker view"), I18n.tr("Grid", "config profile picker view"), inIsland ? I18n.tr("Island", "config profile picker view: opens in the island") : I18n.tr("Dashboard", "config profile picker view: opens in the dashboard")]

                tab: "profiles"
                tags: ["picker", "switcher", "carousel", "grid", "island", "dashboard", "dash", "keybind"]
                settingKey: "configProfilePickerView"
                text: I18n.tr("Profile picker", "settings row: how the config profile picker shows profiles")
                options: labels
                currentValue: labels[Math.max(0, views.indexOf(SettingsData.configProfilePickerView))]
                onValueChanged: value => SettingsData.set("configProfilePickerView", views[labels.indexOf(value)])
            }

            SettingsDropdownRow {
                readonly property var values: ["wallpaper", "none", "random"].concat(SessionData.availableWallpaperTransitions.filter(t => t !== "none"))
                readonly property var labels: values.map(v => v === "wallpaper" ? I18n.tr("Follow wallpaper", "config profile switch transition option: use the wallpaper transition and its duration") : SessionData.transitionLabel(v))

                tab: "profiles"
                tags: ["transition", "effect", "animation", "switch", "fade"]
                settingKey: "configProfileSwitchTransition"
                text: I18n.tr("Transition", "noun, wallpaper change animation setting label")
                options: labels
                currentValue: labels[Math.max(0, values.indexOf(SettingsData.configProfileSwitchTransition))]
                onValueChanged: value => SettingsData.set("configProfileSwitchTransition", values[labels.indexOf(value)])
            }

            SettingsSliderRow {
                tab: "profiles"
                tags: ["transition", "duration", "animation", "switch", "speed"]
                settingKey: "configProfileSwitchDuration"
                text: I18n.tr("Transition duration", "config profile switch transition length setting")
                visible: SettingsData.configProfileSwitchTransition !== "wallpaper" && SettingsData.configProfileSwitchTransition !== "none"
                minimum: 250
                maximum: 3000
                step: 50
                unit: "ms"
                value: SettingsData.configProfileSwitchDuration
                onSliderDragFinished: v => SettingsData.set("configProfileSwitchDuration", v)
            }

            SettingsShortcutRow {
                parentModal: root.parentModal
                ipcTarget: "config-profile"
                action: "spawn dms ipc call config-profile toggle"
                search: "config-profile"
            }
        }

        ProfileGrid {
            id: grid
            width: parent?.width ?? 0
            columns: width >= Theme.mediumBreakpoint ? 3 : width >= Theme.smallBreakpoint ? 2 : 1
            targetScreen: root.screenInfo
            parentModal: root.parentModal
        }

        SettingsFabBar {
            shown: ConfigProfileService.ready

            DFab {
                text: I18n.tr("Import")
                iconName: "download"
                colorRole: "secondaryContainer"
                onClicked: {
                    importBrowserLoader.active = true;
                    (importBrowserLoader.item as FileBrowserModal)?.open();
                }
            }

            DFab {
                text: I18n.tr("New profile")
                iconName: "add"
                onClicked: grid.openPage("profile_edit", "")
            }
        }
    }

    LazyLoader {
        id: importBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            bucket: "profile_export"
            browserTitle: I18n.tr("Import")
            filters: ["*.tar.gz"]
            onAccepted: paths => ConfigProfileService.importProfile(paths[0])
        }
    }
}
