import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: dankBarTab

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null
    BarSelectionState {
        id: bar
    }

    readonly property bool selectedIslandEnabled: bar.selectedBarIsIsland && (bar.selectedBarConfig?.enabled ?? false)
    readonly property string clickThroughHint: I18n.tr("Disabled by Click through", "bar hover popouts card, Click through is the Advanced toggle name")
    readonly property bool selectedIslandFree: bar.selectedBarIsIsland && SettingsData.islandFreePlacement(bar.selectedBarConfig)
    readonly property bool selectedIslandOverlay: bar.selectedBarIsIsland && bar.islandSetting("islandFloating") && !selectedIslandFree
    readonly property bool selectedIslandDocked: bar.selectedBarIsIsland && !selectedIslandFree
    readonly property bool popupGapsZeroed: SettingsData.barUsesConnectedFrameStyle(bar.selectedBarConfig) && !(bar.selectedBarConfig?.useOverlayLayer ?? false)
    readonly property int placementIndex: !bar.islandSetting("islandFloating") ? 0 : (bar.islandSetting("islandPlacement") === "free" ? 2 : 1)

    function setBarScreenPreferences(barId, prefs) {
        SettingsData.updateBarConfig(barId, {
            screenPreferences: prefs
        });
        bar.notifyHorizontalBarChange();
    }

    function setBarShowOnLastDisplay(barId, value) {
        SettingsData.updateBarConfig(barId, value ? {
            showOnLastDisplay: true,
            hideOnLastDisplay: false
        } : {
            showOnLastDisplay: false
        });
        if (Quickshell.screens.length === 1)
            bar.notifyHorizontalBarChange();
    }

    function setBarHideOnLastDisplay(barId, value) {
        SettingsData.updateBarConfig(barId, value ? {
            hideOnLastDisplay: true,
            showOnLastDisplay: false
        } : {
            hideOnLastDisplay: false
        });
        if (Quickshell.screens.length === 1)
            bar.notifyHorizontalBarChange();
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            iconName: "vertical_align_center"
            title: I18n.tr("Position")
            settingKey: "barPosition"
            visible: bar.selectedBarConfig?.enabled

            SettingsRow {
                iconName: "info"
                iconColor: Theme.surfaceVariantText
                visible: bar.islandShadowedScreenCount > 0
                title: I18n.tr("%1 position", "bar info row title, %1 is the bar edge name").arg(bar.positionLabel(bar.selectedBarConfig?.position ?? SettingsData.Position.Top))
                subtitle: I18n.tr("The Island holds this edge on a display this bar covers, so the bar stays hidden there")
            }

            SettingsButtonGroupRow {
                settingKey: "islandFreeOrientation"
                tags: ["island", "free", "orientation", "horizontal", "vertical"]
                visible: dankBarTab.selectedIslandFree
                text: I18n.tr("Orientation", "island settings: horizontal or vertical row for a free island")
                model: [I18n.tr("Horizontal", "island settings: free island orientation"), I18n.tr("Vertical", "island settings: free island orientation")]
                currentIndex: SettingsData.islandVertical(bar.selectedBarConfig) ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        position: index === 1 ? SettingsData.Position.Left : SettingsData.Position.Top
                    });
                }
            }

            SettingsLayoutPicker {
                edgePlacement: true
                visible: !dankBarTab.selectedIslandFree
                choices: [SettingsData.Position.Top, SettingsData.Position.Bottom, SettingsData.Position.Left, SettingsData.Position.Right].map(position => ({
                            key: String(position),
                            label: bar.positionLabel(position),
                            enabled: bar.positionChoices.includes(position)
                        }))
                selectedKey: String(bar.selectedBarConfig?.position ?? SettingsData.Position.Top)
                onSelected: key => {
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        position: Number(key)
                    });
                    bar.notifyHorizontalBarChange();
                }
            }

            SettingsButtonGroupRow {
                settingKey: "islandPlacement"
                tags: ["island", "placement", "docked", "overlay", "floating", "float", "free", "anywhere", "edge", "drag", "exclusive", "reserve"]
                visible: bar.selectedBarIsIsland
                resetStore: bar
                resetKeys: ["islandFloating", "islandPlacement"]
                text: I18n.tr("Placement", "island settings: docked, overlay or floating placement row")
                model: [I18n.tr("Docked", "island settings: island reserves its edge strip"), I18n.tr("Overlay", "island settings: island floats over windows along its edge without reserving space"), I18n.tr("Floating", "island settings: island can be dragged anywhere on the display")]
                currentIndex: dankBarTab.placementIndex
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    const patch = {
                        islandFloating: index > 0
                    };
                    if (index > 0)
                        patch.islandPlacement = index === 2 ? "free" : "edge";
                    SettingsData.updateBarConfig(bar.selectedBarId, patch);
                    bar.notifyHorizontalBarChange();
                }
            }

            SettingsRow {
                settingKey: "islandNotch"
                tags: ["island", "notch", "pill", "shape", "style", "flush", "attached", "edge", "corners", "macbook"]
                title: I18n.tr("Style")
                visible: dankBarTab.selectedIslandDocked
                resetStore: bar
                resetKeys: ["islandNotch"]

                body: SettingsLayoutPicker {
                    islandShape: true
                    choices: [
                        {
                            key: "pill",
                            label: I18n.tr("Pill")
                        },
                        {
                            key: "notch",
                            label: I18n.tr("Notch", "island style option, the island is fused to the screen edge like a notch")
                        }
                    ]
                    selectedKey: bar.islandSetting("islandNotch") ? "notch" : "pill"
                    onSelected: key => bar.apply("islandNotch", key === "notch")
                }
            }

            SettingsRow {
                visible: dankBarTab.selectedIslandFree
                body: StyledText {
                    width: parent.width
                    text: I18n.tr("Drag to move, click to open activities", "island settings: free placement hint")
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }
            }

            SettingsSliderRow {
                settingKey: "islandFreeEdgeMargin"
                tags: ["island", "free", "edge", "margin", "gap"]
                visible: dankBarTab.selectedIslandFree
                resetStore: bar
                resetKeys: ["islandFreeEdgeMargin"]
                text: I18n.tr("Edge margin", "island settings: gap kept from the display edge")
                unit: "px"
                minimum: 0
                maximum: 64
                step: 1
                value: bar.islandSetting("islandFreeEdgeMargin")
                onSliderDragFinished: value => bar.apply("islandFreeEdgeMargin", value)
            }

            SettingsSliderRow {
                settingKey: "islandOuterGap"
                tags: ["island", "placement", "gap", "top", "margin"]
                visible: dankBarTab.selectedIslandDocked && !bar.islandSetting("islandNotch")
                resetStore: bar
                resetKeys: ["islandOuterGap"]
                text: I18n.tr("Outer gap", "island settings: gap between screen edge and island")
                unit: "px"
                minimum: 0
                maximum: 48
                step: 1
                value: bar.islandSetting("islandOuterGap")
                onSliderDragFinished: value => bar.apply("islandOuterGap", value)
            }

            SettingsSliderRow {
                settingKey: "islandAlongOffset"
                tags: ["island", "placement", "horizontal", "vertical", "offset", "center"]
                visible: dankBarTab.selectedIslandDocked
                resetStore: bar
                resetKeys: ["islandAlongOffset"]
                text: bar.selectedBarIsVertical ? I18n.tr("Vertical offset", "island settings: vertical offset slider") : I18n.tr("Horizontal offset", "island settings: horizontal offset slider")
                unit: "px"
                minimum: -600
                maximum: 600
                step: 1
                value: bar.islandSetting("islandAlongOffset")
                onSliderDragFinished: value => bar.apply("islandAlongOffset", value)
            }

            SettingsSliderRow {
                settingKey: "islandReserveThickness"
                tags: ["island", "placement", "reservation", "exclusive", "height", "width", "thickness"]
                visible: dankBarTab.selectedIslandDocked
                resetStore: bar
                resetKeys: ["islandReserveThickness"]
                text: bar.selectedBarIsVertical ? I18n.tr("Reserved width", "island settings: reserved strip width slider") : I18n.tr("Reserved height", "island settings: reserved strip height slider")
                unit: "px"
                minimum: 24
                maximum: 128
                step: 1
                value: bar.islandSetting("islandReserveThickness")
                enabled: !bar.islandSetting("islandFloating")
                onSliderDragFinished: value => bar.apply("islandReserveThickness", value)
            }
        }

        SettingsCard {
            iconName: "display_settings"
            title: I18n.tr("Displays")
            settingKey: "barDisplay"
            collapsible: true
            expanded: true
            visible: bar.selectedBarConfig?.enabled

            SettingsDisplayPicker {
                displayPreferences: bar.selectedBarConfig?.screenPreferences || ["all"]
                emptyMeansAll: false
                allowEmpty: true
                showLastDisplay: true
                showOnLastDisplay: bar.selectedBarConfig?.showOnLastDisplay ?? true
                allowHideOnLastDisplay: true
                hideOnLastDisplay: bar.selectedBarConfig?.hideOnLastDisplay ?? false
                preferencesHandler: prefs => dankBarTab.setBarScreenPreferences(bar.selectedBarId, prefs)
                onLastDisplayToggled: checked => dankBarTab.setBarShowOnLastDisplay(bar.selectedBarId, checked)
                onHideOnLastDisplayToggled: checked => dankBarTab.setBarHideOnLastDisplay(bar.selectedBarId, checked)
            }
        }

        SettingsCard {
            iconName: "visibility"
            title: I18n.tr("Visibility", "settings card title for bar or dock show and hide behavior")
            settingKey: "barVisibility"
            collapsible: true
            expanded: false
            visible: (bar.selectedBarConfig?.enabled ?? false) && (!bar.selectedBarIsIsland || dankBarTab.selectedIslandOverlay)

            SettingsRow {
                iconName: "info"
                iconColor: Theme.surfaceVariantText
                visible: bar.islandShadowsSelectedBar
                title: I18n.tr("Bar visibility")
                subtitle: I18n.tr("The Island holds this edge on a display this bar covers, so the bar stays hidden there")
            }

            SettingsToggleSliderRow {
                resetStore: bar
                settingKey: "barAutoHide"
                tags: ["autohide", "auto-hide", "reveal", "intellihide", "delay", "hide"]
                visible: !bar.islandShadowsSelectedBar && (!bar.selectedBarIsIsland || dankBarTab.selectedIslandOverlay)
                text: I18n.tr("Auto-hide", "toggle to automatically hide the bar or dock")
                valueKeys: ["autoHideDelay"]
                checked: bar.selectedBarConfig?.autoHide ?? false
                value: bar.selectedBarConfig?.autoHideDelay ?? 250
                minimum: 0
                maximum: 2000
                unit: "ms"
                onToggled: toggled => {
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        autoHide: toggled
                    });
                    bar.notifyHorizontalBarChange();
                }
                onSliderDragFinished: newValue => SettingsData.updateBarConfig(bar.selectedBarId, {
                        autoHideDelay: newValue
                    })
            }

            SettingsToggleRow {
                settingKey: "barAutoHideStrict"
                visible: (bar.selectedBarConfig?.autoHide ?? false) && !bar.islandShadowsSelectedBar && (!bar.selectedBarIsIsland || dankBarTab.selectedIslandOverlay)
                tags: ["autohide", "strict", "popout"]
                text: I18n.tr("Strict auto-hide", "Dank bar setting: hide the bar when the pointer leaves even if a menu or bar popover is still open")
                description: I18n.tr("Hides even while a bar popout or menu is open", "bar strict auto-hide toggle description")
                checked: bar.selectedBarConfig?.autoHideStrict ?? false
                onToggled: toggled => {
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        autoHideStrict: toggled
                    });
                    bar.notifyHorizontalBarChange();
                }
            }

            SettingsToggleRow {
                settingKey: "barHideWhenWindowsOpen"
                tags: ["hide", "windows", "empty", "workspace"]
                visible: (bar.selectedBarConfig?.autoHide ?? false) && !bar.islandShadowsSelectedBar && (!bar.selectedBarIsIsland || dankBarTab.selectedIslandOverlay) && CompositorService.supportsBarAutoHideReveal
                text: I18n.tr("Hide when windows open")
                description: I18n.tr("Stays visible while the workspace has no windows", "bar hide when windows open toggle description")
                checked: bar.selectedBarConfig?.showOnWindowsOpen ?? false
                onToggled: toggled => SettingsData.updateBarConfig(bar.selectedBarId, {
                        showOnWindowsOpen: toggled
                    })
            }

            SettingsToggleRow {
                settingKey: "barOpenOnOverview"
                tags: ["bar", "overview", "niri", "show"]
                visible: CompositorService.supportsNativeOverview && !bar.islandOwnsSelectedBarTop && !bar.selectedBarFrameStyled
                text: I18n.tr("Show on overview")
                checked: bar.selectedBarConfig?.openOnOverview ?? false
                onToggled: toggled => SettingsData.updateBarConfig(bar.selectedBarId, {
                        openOnOverview: toggled
                    })
            }

            SettingsToggleRow {
                settingKey: "barManualVisibility"
                tags: ["manual", "show", "hide", "ipc", "toggle"]
                visible: !bar.islandOwnsSelectedBarTop
                text: I18n.tr("Manual show/hide")
                description: I18n.tr("Off keeps the bar hidden until turned back on or shown over IPC", "bar manual visibility toggle description")
                checked: bar.selectedBarConfig?.visible ?? true
                onToggled: toggled => {
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        visible: toggled
                    });
                    bar.notifyHorizontalBarChange();
                }
            }
        }

        IslandBehaviorCard {
            store: bar.islandStore
            docked: dankBarTab.selectedIslandDocked
            visible: dankBarTab.selectedIslandEnabled
        }

        IslandNotificationsCard {
            store: bar.islandStore
            visible: dankBarTab.selectedIslandEnabled
        }

        SettingsCard {
            iconName: "border_outer"
            title: I18n.tr("Frame")
            settingKey: "frameEnabled"
            tags: ["frame", "mode", "bar", "overview", "connected", "separate", "displays"]
            visible: SettingsData.frameEnabled

            SettingsButtonGroupRow {
                settingKey: "frameModeSelector"
                tags: ["frame", "mode", "connected", "separate", "popout", "flush", "float"]
                resetKeys: ["frameMode"]
                text: I18n.tr("Surfaces")
                model: [I18n.tr("Separate", "adjective, frame surfaces mode option, opposite of connected"), I18n.tr("Connected")]
                currentIndex: SettingsData.frameMode === "connected" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    switch (index) {
                    case 1:
                        SettingsData.set("frameMode", "connected");
                        break;
                    default:
                        SettingsData.set("frameMode", "separate");
                        break;
                    }
                }
            }

            SettingsToggleRow {
                settingKey: "frameShowOnOverview"
                tags: ["frame", "overview", "show", "hide", "niri"]
                text: I18n.tr("Show on overview")
                visible: CompositorService.supportsNativeOverview
                checked: SettingsData.frameShowOnOverview
                onToggled: checked => SettingsData.set("frameShowOnOverview", checked)
            }

            SettingsToggleRow {
                settingKey: "frameCloseGaps"
                tags: ["frame", "connected", "gap", "edge", "curves", "arcs", "expose", "popout", "notification"]
                visible: SettingsData.frameMode === "connected"
                text: I18n.tr("Expose the arcs")
                checked: !SettingsData.frameCloseGaps
                onToggled: checked => SettingsData.set("frameCloseGaps", !checked)
            }

            SettingsButtonGroupRow {
                settingKey: "frameLauncherEmergeSide"
                tags: ["frame", "connected", "launcher", "modal", "emerge", "direction", "bottom", "top"]
                visible: SettingsData.frameMode === "connected"
                text: I18n.tr("Launcher emerge side")
                model: [I18n.tr("Bottom"), I18n.tr("Top")]
                currentIndex: SettingsData.frameLauncherEmergeSide === "top" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("frameLauncherEmergeSide", index === 1 ? "top" : "bottom");
                }
            }

            SettingsToggleRow {
                settingKey: "frameLauncherArcExtender"
                tags: ["frame", "connected", "launcher", "arc", "extender", "center"]
                visible: SettingsData.frameMode === "connected"
                text: I18n.tr("Arc extender")
                checked: SettingsData.frameLauncherArcExtender
                onToggled: checked => SettingsData.set("frameLauncherArcExtender", checked)
            }

            SettingsToggleRow {
                settingKey: "frameLauncherEdgeHover"
                tags: ["frame", "connected", "launcher", "hover", "edge", "reveal"]
                visible: SettingsData.frameMode === "connected"
                text: I18n.tr("Edge hover reveal")
                description: I18n.tr("Pointer at the launcher edge opens it, unless a bar or dock is there", "frame launcher edge hover toggle description")
                checked: SettingsData.frameLauncherEdgeHover
                onToggled: checked => SettingsData.set("frameLauncherEdgeHover", checked)
            }

            SettingsDisplayPicker {
                displayPreferences: SettingsData.frameScreenPreferences
                preferencesHandler: prefs => SettingsData.set("frameScreenPreferences", prefs)
            }
        }

        SettingsToggleCard {
            settingKey: "hoverPopouts"
            tags: ["bar", "hover", "popout", "reveal", "widget", "delay"]
            iconName: "touch_app"
            title: I18n.tr("Hover popouts")
            description: enabled ? "" : root.clickThroughHint
            visible: bar.selectedBarConfig?.enabled ?? false
            enabled: !(bar.selectedBarConfig?.clickThrough ?? false)
            opacity: (bar.selectedBarConfig?.clickThrough ?? false) ? 0.5 : 1.0
            checked: bar.selectedBarConfig?.hoverPopouts ?? false
            onToggled: checked => SettingsData.updateBarConfig(bar.selectedBarId, {
                    hoverPopouts: checked
                })

            SettingsSliderRow {
                visible: bar.selectedBarConfig?.hoverPopouts ?? false
                text: I18n.tr("Open delay")
                resetStore: bar
                resetKeys: ["hoverPopoutDelay"]
                value: bar.selectedBarConfig?.hoverPopoutDelay ?? 150
                minimum: 0
                maximum: 1000
                unit: "ms"
                onSliderDragFinished: newValue => {
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        hoverPopoutDelay: newValue
                    });
                }
            }
        }

        SettingsToggleCard {
            id: scrollCard
            iconName: "mouse"
            settingKey: "barScrollWheel"
            tags: ["scroll", "wheel", "workspace", "focus", "window", "axis"]
            title: I18n.tr("Scroll wheel")
            visible: (bar.selectedBarConfig?.enabled ?? false) && !bar.selectedBarIsIsland
            checked: bar.selectedBarConfig?.scrollEnabled ?? true
            onToggled: checked => SettingsData.updateBarConfig(bar.selectedBarId, {
                    scrollEnabled: checked
                })

            readonly property var behaviors: CompositorService.canStepWindowFocus ? ["none", "workspace", "focusWindow"] : ["none", "workspace"]
            readonly property var behaviorLabels: CompositorService.canStepWindowFocus ? [I18n.tr("None"), I18n.tr("Workspace"), I18n.tr("Focus window")] : [I18n.tr("None"), I18n.tr("Workspace")]

            SettingsButtonGroupRow {
                text: I18n.tr("Y axis")
                resetStore: bar
                resetKeys: ["scrollYBehavior"]
                model: scrollCard.behaviorLabels
                buttonPadding: Theme.spacingS
                minButtonWidth: 44
                textSize: Theme.fontSizeSmall
                currentIndex: Math.max(0, scrollCard.behaviors.indexOf(bar.selectedBarConfig?.scrollYBehavior || "workspace"))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        scrollYBehavior: scrollCard.behaviors[index]
                    });
                }
            }

            SettingsButtonGroupRow {
                text: I18n.tr("X axis")
                resetStore: bar
                resetKeys: ["scrollXBehavior"]
                model: scrollCard.behaviorLabels
                buttonPadding: Theme.spacingS
                minButtonWidth: 44
                textSize: Theme.fontSizeSmall
                currentIndex: Math.max(0, scrollCard.behaviors.indexOf(bar.selectedBarConfig?.scrollXBehavior || "focusWindow"))
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        scrollXBehavior: scrollCard.behaviors[index]
                    });
                }
            }
        }

        SettingsCard {
            iconName: "mouse"
            title: I18n.tr("Click actions")
            settingKey: "barMouseClickAction"
            tags: ["bar", "click", "middle", "right", "mouse", "control center", "launcher", "settings"]
            visible: (bar.selectedBarConfig?.enabled ?? false) && !bar.selectedBarIsIsland

            SettingsToggleRow {
                text: I18n.tr("Follow mouse")
                description: I18n.tr("The Control Center opens at the cursor instead of its widget", "bar click action follow mouse description")
                settingKey: "barClickActionFollowMouse"
                visible: bar.selectedBarConfig?.middleClickAction === "control-center" || bar.selectedBarConfig?.rightClickAction === "control-center"
                tags: ["bar", "click", "mouse", "cursor", "position", "anchor", "popout"]
                checked: bar.selectedBarConfig?.clickActionFollowMouse ?? false
                onToggled: checked => SettingsData.updateBarConfig(bar.selectedBarId, {
                        clickActionFollowMouse: checked
                    })
            }

            SettingsDropdownRow {
                text: I18n.tr("Middle click")
                description: I18n.tr("Choose what middle-clicking empty bar space does")
                settingKey: "barMiddleClickAction"
                tags: ["bar", "middle", "click", "mouse", "control center", "launcher", "settings", "close"]
                resetStore: bar
                resetKeys: ["middleClickAction"]
                options: [I18n.tr("None", "bar click action"), I18n.tr("Toggle Control Center", "bar click action"), I18n.tr("Toggle Launcher", "bar click action"), I18n.tr("Close Active Window", "bar click action"), I18n.tr("Toggle Settings", "bar click action")]
                dropdownWidth: Theme.smallBreakpoint / 2
                currentValue: {
                    switch (bar.selectedBarConfig?.middleClickAction ?? "none") {
                    case "control-center":
                        return options[1];
                    case "spotlight":
                        return options[2];
                    case "close-window":
                        return options[3];
                    case "settings":
                        return options[4];
                    default:
                        return options[0];
                    }
                }
                onValueChanged: value => {
                    const actions = ["none", "control-center", "spotlight", "close-window", "settings"];
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        middleClickAction: actions[options.indexOf(value)] ?? "none"
                    });
                }
            }

            SettingsDropdownRow {
                text: I18n.tr("Right click")
                description: I18n.tr("Choose what right-clicking empty bar space does")
                settingKey: "barRightClickAction"
                tags: ["bar", "right", "click", "mouse", "control center", "launcher", "settings", "close"]
                resetStore: bar
                resetKeys: ["rightClickAction"]
                options: [I18n.tr("None", "bar click action"), I18n.tr("Toggle Control Center", "bar click action"), I18n.tr("Toggle Launcher", "bar click action"), I18n.tr("Close Active Window", "bar click action"), I18n.tr("Toggle Settings", "bar click action")]
                dropdownWidth: Theme.smallBreakpoint / 2
                currentValue: {
                    switch (bar.selectedBarConfig?.rightClickAction ?? "none") {
                    case "control-center":
                        return options[1];
                    case "spotlight":
                        return options[2];
                    case "close-window":
                        return options[3];
                    case "settings":
                        return options[4];
                    default:
                        return options[0];
                    }
                }
                onValueChanged: value => {
                    const actions = ["none", "control-center", "spotlight", "close-window", "settings"];
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        rightClickAction: actions[options.indexOf(value)] ?? "none"
                    });
                }
            }
        }

        SettingsCard {
            iconName: "tune"
            title: I18n.tr("Advanced")
            settingKey: "barAdvanced"
            tags: ["bar", "advanced", "overlay", "layer", "click", "through", "maximize", "island", "spring", "motion", "exclusive", "zone", "popup", "gaps"]
            collapsible: true
            expanded: false
            visible: bar.selectedBarConfig?.enabled ?? false

            SettingsToggleRow {
                settingKey: "barClickThrough"
                tags: ["clickthrough", "click", "through", "mouse", "input", "mask", "passthrough"]
                visible: !bar.islandOwnsSelectedBarTop
                text: I18n.tr("Click through")
                description: I18n.tr("Clicks on empty bar space reach the windows below", "bar click through toggle description")
                checked: bar.selectedBarConfig?.clickThrough ?? false
                onToggled: toggled => SettingsData.updateBarConfig(bar.selectedBarId, {
                        clickThrough: toggled
                    })
            }

            SettingsToggleRow {
                settingKey: "barUseOverlayLayer"
                tags: ["bar", "fullscreen", "overlay", "layer"]
                visible: !bar.islandOwnsSelectedBarTop && !(bar.selectedBarFrameStyled && !SettingsData.connectedFrameModeActive)
                text: I18n.tr("Use overlay layer")
                checked: bar.selectedBarConfig?.useOverlayLayer ?? false
                onToggled: toggled => {
                    SettingsData.updateBarConfig(bar.selectedBarId, {
                        useOverlayLayer: toggled
                    });
                    bar.notifyHorizontalBarChange();
                }
            }

            SettingsToggleRow {
                settingKey: "barHideOnFullscreen"
                resetStore: bar
                resetKeys: ["hideOnFullscreen"]
                tags: ["bar", "fullscreen", "hide", "visibility"]
                visible: CompositorService.isNiri && !bar.islandOwnsSelectedBarTop && (bar.selectedBarConfig?.useOverlayLayer ?? false)
                text: I18n.tr("Hide bar on fullscreen", "bar visibility toggle")
                description: I18n.tr("Slide the bar away over fullscreen applications. Move the pointer to the screen edge to reveal it.", "bar fullscreen auto-hide description")
                checked: bar.selectedBarConfig?.hideOnFullscreen ?? false
                onToggled: toggled => SettingsData.updateBarConfig(bar.selectedBarId, {
                        hideOnFullscreen: toggled
                    })
            }

            SettingsToggleRow {
                settingKey: "islandUseOverlayLayer"
                tags: ["island", "fullscreen", "overlay", "layer"]
                visible: bar.selectedBarIsIsland && !bar.selectedBarFrameStyled
                text: I18n.tr("Use overlay layer")
                checked: bar.islandSetting("islandUseOverlayLayer")
                onToggled: checked => bar.apply("islandUseOverlayLayer", checked)
            }

            SettingsControlledBy {
                visible: bar.selectedBarFrameStyled && (bar.selectedBarIsIsland || (!bar.islandOwnsSelectedBarTop && !SettingsData.connectedFrameModeActive))
                parentModal: dankBarTab.parentModal
                section: "frameBorder"
                settingLabel: I18n.tr("Use overlay layer")
                reason: I18n.tr("Disabled by Frame Mode")
            }

            SettingsToggleRow {
                settingKey: "barMaximizeDetection"
                tags: ["maximize", "gaps", "border", "fullscreen"]
                visible: CompositorService.supportsBarAutoHideReveal && !bar.selectedBarFrameStyled
                text: I18n.tr("Maximize detection")
                description: I18n.tr("Drops bar gaps and rounding while a window is maximized", "bar maximize detection toggle description")
                checked: bar.selectedBarConfig?.maximizeDetection ?? true
                onToggled: toggled => SettingsData.updateBarConfig(bar.selectedBarId, {
                        maximizeDetection: toggled
                    })
            }

            SettingsControlledBy {
                visible: CompositorService.supportsBarAutoHideReveal && bar.selectedBarFrameStyled
                parentModal: dankBarTab.parentModal
                section: "frameBorder"
                settingLabel: I18n.tr("Maximize detection")
                reason: I18n.tr("Disabled by Frame Mode")
            }

            SettingsSliderRow {
                settingKey: "barExclusiveZone"
                tags: ["exclusive", "zone", "reserved", "offset"]
                visible: !bar.islandOwnsSelectedBarTop && !bar.selectedBarFrameStyled
                text: I18n.tr("Exclusive zone offset")
                description: I18n.tr("Grows or shrinks the space windows keep clear", "bar and dock exclusive zone offset slider description")
                resetStore: bar
                resetKeys: ["bottomGap"]
                value: bar.selectedBarConfig?.bottomGap ?? 0
                minimum: -50
                maximum: 50
                unit: "px"
                onSliderDragFinished: finalValue => SettingsData.updateBarConfig(bar.selectedBarId, {
                        bottomGap: finalValue
                    })
            }

            SettingsToggleRow {
                text: I18n.tr("Auto popup gaps")
                description: I18n.tr("Gap between the bar and its popouts follows edge spacing", "bar auto popup gaps toggle description")
                tags: ["popup", "gaps", "auto"]
                visible: !dankBarTab.popupGapsZeroed
                checked: bar.selectedBarConfig?.popupGapsAuto ?? true
                onToggled: checked => SettingsData.updateBarConfig(bar.selectedBarId, {
                        popupGapsAuto: checked
                    })
            }

            SettingsSliderRow {
                visible: !dankBarTab.popupGapsZeroed && !(bar.selectedBarConfig?.popupGapsAuto ?? true)
                text: I18n.tr("Gap size")
                tags: ["popup", "gaps", "size"]
                resetStore: bar
                resetKeys: ["popupGapsManual"]
                unit: "px"
                value: bar.selectedBarConfig?.popupGapsManual ?? 4
                minimum: 0
                maximum: 50
                onSliderDragFinished: finalValue => SettingsData.updateBarConfig(bar.selectedBarId, {
                        popupGapsManual: finalValue
                    })
            }
        }

        IslandMotionCard {
            store: bar.islandStore
            visible: dankBarTab.selectedIslandEnabled
        }
    }
}
