pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modals.FileBrowser
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    // Mirrors screenshot.GetOutputDir in core.
    readonly property string defaultDir: Paths.shortenHome(Quickshell.env("DMS_SCREENSHOT_DIR") || Paths.strip(Paths.pictures) + "/Screenshots")

    function setDir(path: string) {
        SettingsData.set("screenshotDir", Paths.shortenHome(path.trim()));
    }

    SettingsPage {
        SettingsCard {
            tab: "screenshot"
            tags: ["screenshot", "save", "file", "folder", "directory", "format"]
            settingKey: "screenshotSaving"
            title: I18n.tr("Saving", "screenshot settings card title, where and how captures are written to disk")
            iconName: "save"

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "save", "file", "disk"]
                settingKey: "screenshotSaveFile"
                text: I18n.tr("Save to file", "screenshot settings toggle, write each capture to the save folder")
                checked: SettingsData.screenshotSaveFile
                enabled: !checked || SettingsData.screenshotClipboard
                onToggled: checked => SettingsData.set("screenshotSaveFile", checked)
            }

            SettingsTextFieldRow {
                tab: "screenshot"
                tags: ["screenshot", "folder", "directory", "path", "location"]
                settingKey: "screenshotDir"
                text: I18n.tr("Folder", "noun, screenshot settings label for the save directory")
                enabled: SettingsData.screenshotSaveFile
                placeholderText: root.defaultDir
                alwaysFloatLabel: true
                // The row's reset writes the field and breaks a plain value binding.
                readonly property string savedDir: SettingsData.screenshotDir
                value: savedDir
                onSavedDirChanged: value = savedDir
                onEditingFinished: value => root.setDir(value)

                actions: DActionButton {
                    iconName: "folder_open"
                    tooltipText: I18n.tr("Browse")
                    Accessible.name: I18n.tr("Browse")
                    enabled: SettingsData.screenshotSaveFile
                    onClicked: {
                        folderBrowserLoader.active = true;
                        (folderBrowserLoader.item as FileBrowserModal)?.open();
                    }
                }
            }

            SettingsDropdownRow {
                tab: "screenshot"
                tags: ["screenshot", "format", "png", "jpeg", "jpg", "ppm"]
                settingKey: "screenshotFormat"
                text: I18n.tr("Format", "noun, screenshot image file format setting label")
                options: ["PNG", "JPEG", "PPM"]
                optionValues: ["png", "jpg", "ppm"]
                currentValue: SettingsData.screenshotFormat
                onValueChanged: value => SettingsData.set("screenshotFormat", value)
            }

            SettingsSliderRow {
                tab: "screenshot"
                tags: ["screenshot", "jpeg", "jpg", "quality", "compression"]
                settingKey: "screenshotQuality"
                text: I18n.tr("Quality", "screenshot JPEG quality slider label")
                visible: SettingsData.screenshotFormat === "jpg"
                value: SettingsData.screenshotQuality
                minimum: 1
                maximum: 100
                unit: "%"
                onSliderValueChanged: value => SettingsData.set("screenshotQuality", value)
            }
        }

        SettingsCard {
            tab: "screenshot"
            tags: ["screenshot", "clipboard", "notification", "copy"]
            settingKey: "screenshotAfterCapture"
            title: I18n.tr("After capture", "screenshot settings card title, what happens once a screenshot is taken")
            iconName: "task_alt"

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "clipboard", "copy"]
                settingKey: "screenshotClipboard"
                text: I18n.tr("Copy to clipboard")
                checked: SettingsData.screenshotClipboard
                enabled: !checked || SettingsData.screenshotSaveFile
                onToggled: checked => SettingsData.set("screenshotClipboard", checked)
            }

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "clipboard", "file", "path", "terminal", "uri"]
                settingKey: "screenshotClipboardFile"
                text: I18n.tr("Copy as file", "screenshot settings toggle, copy the saved file instead of only the image")
                description: I18n.tr("Terminals and file managers paste the saved file", "screenshot settings description for copying the saved file")
                checked: SettingsData.screenshotClipboardFile
                enabled: SettingsData.screenshotClipboard && SettingsData.screenshotSaveFile
                onToggled: checked => SettingsData.set("screenshotClipboardFile", checked)
            }

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "notification", "notify", "popup"]
                settingKey: "screenshotNotify"
                text: I18n.tr("Show notification", "screenshot settings toggle, show a notification after each capture")
                checked: SettingsData.screenshotNotify
                onToggled: checked => SettingsData.set("screenshotNotify", checked)
            }
        }

        SettingsCard {
            tab: "screenshot"
            tags: ["screenshot", "capture", "cursor", "region", "selector"]
            settingKey: "screenshotCapture"
            title: I18n.tr("Capture", "screenshot settings card title, how screenshots are taken")
            iconName: "screenshot_region"

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "cursor", "pointer", "mouse"]
                settingKey: "screenshotCursor"
                text: I18n.tr("Include cursor", "screenshot settings toggle, draw the mouse pointer into captures")
                checked: SettingsData.screenshotCursor
                onToggled: checked => SettingsData.set("screenshotCursor", checked)
            }

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "region", "confirm", "enter", "release"]
                settingKey: "screenshotConfirmRegion"
                text: I18n.tr("Confirm region", "screenshot settings toggle, require Enter or Space before capturing a selected region")
                description: I18n.tr("Press Enter or Space to capture. Off captures when the mouse is released.", "screenshot settings description for the confirm region toggle")
                checked: SettingsData.screenshotConfirmRegion
                onToggled: checked => SettingsData.set("screenshotConfirmRegion", checked)
            }

            SettingsToggleRow {
                tab: "screenshot"
                tags: ["screenshot", "annotate", "draw", "markup", "editor", "arrow", "text", "highlight"]
                settingKey: "screenshotAnnotate"
                text: I18n.tr("Annotate region captures", "screenshot settings toggle, open the drawing editor on a selected region before it is saved")
                description: I18n.tr("Draw, highlight and add text on a region before it is saved", "screenshot settings description for the annotate toggle")
                checked: SettingsData.screenshotAnnotate
                onToggled: checked => SettingsData.set("screenshotAnnotate", checked)
            }

            SettingsDropdownRow {
                tab: "screenshot"
                tags: ["screenshot", "hud", "hints", "keybinds", "shortcuts", "overlay"]
                settingKey: "screenshotHud"
                text: I18n.tr("Shortcut hints", "screenshot settings dropdown, size of the key hints shown while selecting a region")
                options: [I18n.tr("Auto", "screenshot shortcut hints option, size follows the display scale"), I18n.tr("Off", "screenshot shortcut hints option, hide the hints"), "1×", "2×", "3×", "4×"]
                optionValues: ["auto", "off", "1", "2", "3", "4"]
                currentValue: SettingsData.screenshotHud
                onValueChanged: value => SettingsData.set("screenshotHud", value)
            }

            SettingsSliderRow {
                tab: "screenshot"
                tags: ["screenshot", "scroll", "scrolling", "interval", "long", "tall"]
                settingKey: "screenshotScrollInterval"
                text: I18n.tr("Scroll capture interval", "screenshot settings slider, time between frames while capturing a scrolling region")
                description: I18n.tr("Lower keeps up with faster scrolling but uses more CPU", "screenshot settings description for the scroll capture interval")
                value: SettingsData.screenshotScrollInterval
                minimum: 30
                maximum: 1000
                step: 5
                unit: "ms"
                onSliderValueChanged: value => SettingsData.set("screenshotScrollInterval", value)
            }

            SettingsNavRow {
                tab: "screenshot"
                tags: ["screenshot", "keybinds", "shortcuts", "bind", "hotkey", "print screen"]
                settingKey: "screenshotShortcuts"
                visible: KeybindsService.available
                iconName: "keyboard_command_key"
                title: I18n.tr("Keyboard shortcuts")
                hint: I18n.tr("Bind keys to region, screen, window and scroll captures", "screenshot settings row that opens the keyboard shortcuts page filtered to screenshot binds")
                onClicked: root.parentModal?.showKeybindsSearch("screenshot")
            }
        }
    }

    LazyLoader {
        id: folderBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            browserTitle: I18n.tr("Choose screenshot folder", "screenshot folder file browser title")
            bucket: "screenshot"
            mode: "openFolder"
            startPath: Paths.expandTilde(SettingsData.screenshotDir || root.defaultDir)
            onAccepted: paths => root.setDir(paths[0])
        }
    }
}
