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

    readonly property bool perMonitor: SessionData.perMonitorWallpaper
    readonly property string selectedScreen: SettingsUiState.selectedWallpaperScreen || firstScreenName()
    readonly property var monitorSettings: {
        SessionData.monitorCyclingSettings;
        return SessionData.getMonitorCyclingSettings(selectedScreen);
    }
    readonly property bool enabled: perMonitor ? monitorSettings.enabled : SessionData.wallpaperCyclingEnabled
    readonly property bool random: perMonitor ? monitorSettings.random : SessionData.wallpaperCyclingRandom
    readonly property bool recursive: perMonitor ? monitorSettings.recursive : SessionData.wallpaperCyclingRecursive
    readonly property bool onLogin: perMonitor ? monitorSettings.onLogin : SessionData.wallpaperCyclingOnLogin
    readonly property string mode: perMonitor ? monitorSettings.mode : SessionData.wallpaperCyclingMode
    readonly property int interval: perMonitor ? monitorSettings.interval : SessionData.wallpaperCyclingInterval
    readonly property string time: perMonitor ? monitorSettings.time : SessionData.wallpaperCyclingTime
    readonly property string folderPath: perMonitor ? monitorSettings.folderPath : SessionData.wallpaperCyclingFolderPath
    readonly property string currentWallpaper: {
        SessionData.monitorWallpapers;
        return perMonitor ? SessionData.getMonitorWallpaper(selectedScreen) : SessionData.wallpaperPath;
    }
    readonly property bool canCycle: currentWallpaper !== "" && !currentWallpaper.startsWith("#") && !currentWallpaper.startsWith("we")
    readonly property string wallpaperFolder: folderPath || (canCycle ? currentWallpaper.substring(0, currentWallpaper.lastIndexOf("/")) : "")
    readonly property int timeHour: parseInt(time.split(":")[0]) || 0
    readonly property int timeMinute: parseInt(time.split(":")[1]) || 0

    readonly property var intervalValues: [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 300, 900, 1800, 3600, 5400, 7200, 10800, 14400, 21600, 28800, 43200]
    readonly property var intervalOptions: intervalValues.map(seconds => I18n.duration(seconds))

    function firstScreenName() {
        const screens = Quickshell.screens;
        return screens.length > 0 ? screens[0].name : "";
    }

    function screenNames() {
        const names = [];
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            names.push(SettingsData.getScreenDisplayName(screens[i]));
        return names;
    }

    function screenForDisplayName(value) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (SettingsData.getScreenDisplayName(screens[i]) === value)
                return screens[i].name;
        }
        return "";
    }

    function displayNameForScreen(name) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name)
                return SettingsData.getScreenDisplayName(screens[i]);
        }
        return I18n.tr("No displays");
    }

    function setEnabled(value) {
        if (perMonitor) {
            SessionData.setMonitorCyclingEnabled(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingEnabled(value);
    }

    function setRandom(value) {
        if (perMonitor) {
            SessionData.setMonitorCyclingRandom(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingRandom(value);
    }

    function setRecursive(value) {
        if (perMonitor) {
            SessionData.setMonitorCyclingRecursive(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingRecursive(value);
    }

    function setOnLogin(value) {
        if (perMonitor) {
            SessionData.setMonitorCyclingOnLogin(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingOnLogin(value);
    }

    function setMode(value) {
        if (perMonitor) {
            SessionData.setMonitorCyclingMode(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingMode(value);
    }

    function setInterval(value) {
        if (perMonitor) {
            SessionData.setMonitorCyclingInterval(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingInterval(value);
    }

    function setTime(hour, minute) {
        const value = (hour < 10 ? "0" : "") + hour + ":" + (minute < 10 ? "0" : "") + minute;
        if (perMonitor) {
            SessionData.setMonitorCyclingTime(selectedScreen, value);
            return;
        }
        SessionData.setWallpaperCyclingTime(value);
    }

    function cycle(previous) {
        if (perMonitor) {
            if (previous)
                WallpaperCyclingService.cyclePrevForMonitor(selectedScreen);
            else
                WallpaperCyclingService.cycleNextForMonitor(selectedScreen);
            return;
        }
        if (previous)
            WallpaperCyclingService.cyclePrevManually();
        else
            WallpaperCyclingService.cycleNextManually();
    }

    SettingsPage {
        SettingsCard {
            tab: "wallpaper"
            tags: ["cycling", "automatic", "rotate", "slideshow", "folder", "interval", "random", "shuffle", "time", "daily"]
            settingKey: "wallpaperCycling"

            SettingsDropdownRow {
                tab: "wallpaper"
                tags: ["monitor", "display", "screen"]
                visible: root.perMonitor
                text: I18n.tr("Display")
                currentValue: root.displayNameForScreen(root.selectedScreen)
                options: root.screenNames()
                onValueChanged: value => SettingsUiState.selectedWallpaperScreen = root.screenForDisplayName(value)
            }

            SettingsRow {
                title: root.canCycle ? root.currentWallpaper.split("/").pop() : I18n.tr("No wallpaper selected")
                subtitle: root.wallpaperFolder
                enabled: root.canCycle

                DActionButton {
                    buttonSize: Theme.iconButtonSize
                    iconName: "skip_previous"
                    iconSize: Theme.iconSizeMedium
                    iconColor: Theme.surfaceText
                    backgroundColor: SettingsMetrics.controlSurface
                    enabled: root.canCycle
                    Accessible.name: I18n.tr("Previous")
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.cycle(true)
                }

                DActionButton {
                    buttonSize: Theme.iconButtonSize
                    iconName: "skip_next"
                    iconSize: Theme.iconSizeMedium
                    iconColor: Theme.surfaceText
                    backgroundColor: SettingsMetrics.controlSurface
                    enabled: root.canCycle
                    Accessible.name: I18n.tr("Next")
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.cycle(false)
                }
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["cycling", "automatic", "rotate", "slideshow"]
                settingKey: "wallpaperCyclingEnabled"
                text: I18n.tr("Automatic cycling")
                checked: root.enabled
                onToggled: toggled => root.setEnabled(toggled)
            }

            SettingsRow {
                tab: "wallpaper"
                tags: ["cycling", "folder", "directory"]
                settingKey: "wallpaperCyclingFolder"
                title: I18n.tr("Folder")
                subtitle: root.folderPath || I18n.tr("Use desktop wallpaper")

                DButton {
                    text: I18n.tr("Browse")
                    horizontalPadding: Theme.spacingL
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        folderBrowserLoader.active = true;
                        if (folderBrowserLoader.item)
                            folderBrowserLoader.item.open();
                    }
                }
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["cycling", "subfolders", "recursive", "directories", "folders"]
                settingKey: "wallpaperCyclingRecursive"
                text: I18n.tr("Include subfolders")
                checked: root.recursive
                onToggled: toggled => root.setRecursive(toggled)
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["cycling", "automatic", "random", "shuffle"]
                settingKey: "wallpaperCyclingRandom"
                text: I18n.tr("Random order")
                checked: root.random
                onToggled: toggled => root.setRandom(toggled)
            }

            SettingsToggleRow {
                tab: "wallpaper"
                tags: ["cycling", "automatic", "login", "startup", "boot"]
                settingKey: "wallpaperCyclingOnLogin"
                text: I18n.tr("Change on login")
                checked: root.onLogin
                onToggled: toggled => root.setOnLogin(toggled)
            }

            SettingsButtonGroupRow {
                tab: "wallpaper"
                tags: ["cycling", "mode", "interval", "time", "daily"]
                settingKey: "wallpaperCyclingMode"
                text: I18n.tr("Mode", "noun, setting label, e.g. wallpaper cycling mode, wifi mode, display mode")
                model: [I18n.tr("Interval", "wallpaper cycling mode tab"), I18n.tr("Time", "wallpaper cycling mode tab")]
                currentIndex: root.mode === "time" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    root.setMode(index === 1 ? "time" : "interval");
                }
            }

            SettingsDropdownRow {
                tab: "wallpaper"
                tags: ["interval", "cycling", "time", "frequency"]
                settingKey: "wallpaperCyclingInterval"
                visible: root.mode !== "time"
                text: I18n.tr("Interval")
                options: root.intervalOptions
                currentValue: {
                    const index = root.intervalValues.indexOf(root.interval);
                    return index >= 0 ? root.intervalOptions[index] : I18n.duration(300);
                }
                onValueChanged: value => {
                    const index = root.intervalOptions.indexOf(value);
                    if (index >= 0)
                        root.setInterval(root.intervalValues[index]);
                }
            }

            SettingsTimeRow {
                visible: root.mode === "time"
                showEnd: false
                is24Hour: SettingsData.use24HourClock
                startTitle: I18n.tr("Daily", "adverb, wallpaper changes every day at a set time", true)
                startHour: root.timeHour
                startMinute: root.timeMinute
                onStartChanged: (hour, minute) => root.setTime(hour, minute)
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
            onAccepted: paths => WallpaperCyclingService.cycleFromFolder(root.perMonitor ? root.selectedScreen : "", paths[0])
        }
    }
}
