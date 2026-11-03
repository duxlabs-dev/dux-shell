import QtQuick
import Quickshell
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
            iconName: "layers"
            title: I18n.tr("Layers", "noun plural, dock settings card for overlay layer and fullscreen options")
            settingKey: "dockAdvanced"
            tags: ["dock", "advanced", "overlay", "fullscreen", "overview", "exclusive"]

            SettingsToggleRow {
                settingKey: "dockUseOverlayLayer"
                tags: ["dock", "fullscreen", "overlay", "layer"]
                text: I18n.tr("Use overlay layer")
                checked: dock.config?.useOverlayLayer ?? false
                onToggled: checked => dock.setOption("useOverlayLayer", checked)
            }

            SettingsToggleRow {
                settingKey: "dockShowOnFullscreen"
                tags: ["dock", "fullscreen", "overlay", "show", "visibility"]
                text: I18n.tr("Over fullscreen")
                description: I18n.tr("Keeps the dock showing over fullscreen windows", "dock over fullscreen toggle description")
                enabled: (dock.config?.useOverlayLayer ?? false) || Quickshell.screens.some(screen => CompositorService.framePeerSurfacesUseOverlayForScreen(screen) && SettingsData.dockConfigsForScreen(screen).some(config => config.id === dock.config?.id))
                checked: dock.config?.showOnFullscreen ?? false
                onToggled: checked => dock.setOption("showOnFullscreen", checked)
            }

            SettingsToggleRow {
                settingKey: "dockOpenOnOverview"
                tags: ["dock", "overview", "niri"]
                text: I18n.tr("Show on overview")
                visible: CompositorService.isNiri
                checked: dock.config?.openOnOverview ?? false
                onToggled: checked => dock.setOption("openOnOverview", checked)
            }

            SettingsSliderRow {
                settingKey: "dockExclusiveZone"
                tags: ["exclusive", "zone", "reserved", "offset"]
                resetStore: dock
                resetKeys: ["bottomGap"]
                text: I18n.tr("Exclusive zone offset")
                description: I18n.tr("Grows or shrinks the space windows keep clear", "bar and dock exclusive zone offset slider description")
                visible: dock.reservesSpace
                value: dock.config?.bottomGap ?? 0
                minimum: -100
                maximum: 100
                unit: "px"
                onSliderValueChanged: value => dock.setOption("bottomGap", value)
            }
        }

        SettingsCard {
            width: parent.width
            visible: dock.hasConfig
            iconName: "monitor"
            title: I18n.tr("Displays")
            settingKey: "dockAdvancedDisplays"
            tags: ["dock", "isolate", "monitor", "multi-monitor"]

            SettingsToggleRow {
                settingKey: "dockIsolateDisplays"
                tags: ["dock", "isolate", "monitor", "multi-monitor"]
                text: I18n.tr("Isolate displays")
                description: I18n.tr("Shows only windows from the dock's own display", "dock isolate displays toggle description")
                checked: dock.config?.isolateDisplays ?? false
                onToggled: checked => dock.setOption("isolateDisplays", checked)
            }

            SettingsToggleRow {
                settingKey: "dockRestoreSpecialWorkspaceOnClick"
                tags: ["dock", "hyprland", "special", "workspace", "restore"]
                text: I18n.tr("Restore special workspace")
                description: I18n.tr("Clicking a window in a special workspace opens that workspace", "dock restore special workspace toggle description")
                visible: CompositorService.isHyprland
                checked: dock.config?.restoreSpecialWorkspaceOnClick ?? false
                onToggled: checked => dock.setOption("restoreSpecialWorkspaceOnClick", checked)
            }
        }
    }
}
