import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null

    DockSelectionState {
        id: dock
    }

    SettingsPage {
        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "display_settings"
            title: I18n.tr("Displays")
            settingKey: "dockDisplays"
            tags: ["dock", "display", "monitor", "screen"]

            SettingsDisplayPicker {
                displayPreferences: dock.screenPreferences
                emptyMeansAll: false
                preferencesHandler: preferences => dock.setOption("screenPreferences", preferences)
            }

            SettingsToggleRow {
                text: I18n.tr("Show on last display")
                checked: dock.config?.showOnLastDisplay ?? true
                onToggled: checked => dock.setOption("showOnLastDisplay", checked)
            }
        }

        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "view_compact"
            title: I18n.tr("Layout")
            settingKey: "dockLayout"
            tags: ["dock", "layout", "compact", "taskbar", "alignment"]

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["mode"]
                text: I18n.tr("Style")
                model: [I18n.tr("Compact", "adjective, dock style option, also notification compact mode toggle"), I18n.tr("Taskbar", "dock style option, alternative to compact")]
                currentIndex: dock.config?.mode === "taskbar" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    dock.setOption("mode", index === 1 ? "taskbar" : "compact");
                }
            }

            SettingsButtonGroupRow {
                resetStore: dock
                resetKeys: ["taskbarAlign"]
                readonly property var alignments: ["start", "center", "end"]

                text: I18n.tr("Alignment", "row label, where taskbar dock items align")
                enabled: dock.config?.mode === "taskbar"
                model: dock.isVertical ? [I18n.tr("Top"), I18n.tr("Center", "noun, taskbar dock alignment option between start and end"), I18n.tr("Bottom")] : [I18n.tr("Left"), I18n.tr("Center"), I18n.tr("Right")]
                currentIndex: Math.max(0, alignments.indexOf(dock.config?.taskbarAlign ?? "center"))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    dock.setOption("taskbarAlign", alignments[index]);
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: dock.hasConfig && dock.config.enabled
            iconName: "visibility_off"
            title: I18n.tr("Visibility")
            settingKey: "dockAutoHideCard"
            tags: ["dock", "autohide", "hide", "hover"]

            SettingsToggleRow {
                settingKey: "dockAutoHide"
                tags: ["dock", "autohide", "hide", "hover"]
                text: I18n.tr("Auto-hide")
                checked: dock.config?.autoHide ?? false
                onToggled: checked => {
                    if (checked && dock.config.smartAutoHide)
                        dock.setOption("smartAutoHide", false);
                    dock.setOption("autoHide", checked);
                }
            }

            SettingsToggleRow {
                settingKey: "dockSmartAutoHide"
                tags: ["dock", "smart", "autohide", "windows", "overlap", "intelligent", "floating"]
                text: I18n.tr("Smart auto-hide")
                description: I18n.tr("Hides only while a window overlaps the dock", "dock smart auto-hide toggle description")
                visible: CompositorService.supportsSmartDock
                checked: dock.config?.smartAutoHide ?? false
                onToggled: checked => {
                    if (checked && dock.config.autoHide)
                        dock.setOption("autoHide", false);
                    dock.setOption("smartAutoHide", checked);
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: dock.hasConfig && dock.config.enabled
            iconName: "edit"
            title: I18n.tr("Edit mode")
            settingKey: "dockEditMode"
            tags: ["dock", "edit", "widgets", "right-click", "arrange"]

            SettingsRow {
                title: I18n.tr("Arrange dock items", "dock settings row title for entering dock edit mode")
                subtitle: I18n.tr("Enter edit mode on the dock to rearrange or remove items", "dock settings row description for the edit mode button")

                DankButton {
                    text: I18n.tr("Edit widgets")
                    iconName: "edit"
                    buttonHeight: Theme.buttonHeightS
                    onClicked: BarWidgetService.dockEditRequested(dock.selectedDockId)
                }
            }

            SettingsToggleRow {
                settingKey: "dockShowEditWidgetsInContextMenu"
                resetStore: dock
                resetKeys: ["showEditWidgetsInContextMenu"]
                tags: ["dock", "edit", "widgets", "context", "menu"]
                text: I18n.tr("Show Edit widgets in app context menu", "dock setting to show or hide the Edit widgets action in an app's context menu")
                checked: dock.config?.showEditWidgetsInContextMenu ?? true
                onToggled: checked => dock.setOption("showEditWidgetsInContextMenu", checked)
            }

            SettingsToggleRow {
                settingKey: "dockEditOnRightClick"
                tags: ["dock", "edit", "right-click", "context"]
                text: I18n.tr("Right-click empty space to edit")
                checked: dock.config?.editOnRightClick ?? false
                onToggled: checked => dock.setOption("editOnRightClick", checked)
            }
        }
    }
}
