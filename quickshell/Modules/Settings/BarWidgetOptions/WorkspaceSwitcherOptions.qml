pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Settings
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    readonly property bool showApps: page.value("showWorkspaceApps")
    readonly property var indicatorStyleChoices: [
        {
            "key": "pills",
            "label": I18n.tr("Pills", "workspace indicator style")
        },
        {
            "key": "dots",
            "label": I18n.tr("Dots", "workspace indicator style")
        },
        {
            "key": "lines",
            "label": I18n.tr("Lines", "workspace indicator style")
        },
        {
            "key": "cards",
            "label": I18n.tr("Cards", "workspace indicator style")
        }
    ]
    property real draftRoundness: -1
    readonly property real indicatorRoundness: {
        const stored = page.value("workspaceIndicatorRoundness");
        return stored >= 0 ? stored : Math.round(Math.min(1, Theme.shapeScale) * 100);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        title: I18n.tr("General")
        settingKey: "workspaceSettings"

        SettingsRow {
            resetStore: root.page
            resetKeys: ["workspaceIndicatorStyle"]
            tags: ["workspace", "style", "pills", "dots", "circles", "lines", "cards"]
            title: I18n.tr("Style")

            body: SettingsLayoutPicker {
                indicatorStyle: true
                indicatorRoundness: root.draftRoundness >= 0 ? root.draftRoundness : root.page.value("workspaceIndicatorRoundness")
                indicatorCompact: root.page.value("workspaceIndicatorCompact")
                choices: root.indicatorStyleChoices
                selectedKey: root.page.value("workspaceIndicatorStyle")
                onSelected: key => root.page.set("workspaceIndicatorStyle", key)
            }
        }

        SettingsToggleRow {
            tags: ["workspace", "compact", "small", "size", "dense"]
            text: I18n.tr("Compact")
            checked: root.page.value("workspaceIndicatorCompact")
            onToggled: checked => root.page.set("workspaceIndicatorCompact", checked)
        }

        SettingsToggleSliderRow {
            resetStore: root.page
            tags: ["workspace", "corner", "radius", "rounded", "square", "circle", "override", "roundness"]
            text: I18n.tr("Override", "verb, toggle to override the global setting for this item")
            checked: root.page.value("workspaceIndicatorRoundness") >= 0
            value: root.indicatorRoundness
            minimum: 0
            maximum: 100
            unit: ""
            onToggled: checked => root.page.set("workspaceIndicatorRoundness", checked ? root.indicatorRoundness : -1)
            onSliderValueChanged: newValue => root.draftRoundness = newValue
            onSliderDragFinished: finalValue => {
                root.page.set("workspaceIndicatorRoundness", finalValue);
                root.draftRoundness = -1;
            }
        }

        SettingsToggleRow {
            text: I18n.tr("Index numbers")
            checked: root.page.value("showWorkspaceIndex")
            onToggled: checked => root.page.set("showWorkspaceIndex", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Names", "toggle to show workspace names")
            checked: root.page.value("showWorkspaceName")
            onToggled: checked => root.page.set("showWorkspaceName", checked)
        }

        SettingsToggleCard {
            title: I18n.tr("Show apps")
            visible: CompositorService.supportsWorkspaces
            enabled: !CompositorService.isAqueous || (AqueousService.available && Quickshell.env("DMS_FORCE_EXTWS") !== "1")
            checked: root.showApps
            onToggled: checked => root.page.set("showWorkspaceApps", checked)

            SettingsSliderRow {
                resetStore: root.page
                resetKeys: ["maxWorkspaceIcons"]
                text: I18n.tr("Max apps to show")
                unit: ""
                value: root.page.value("maxWorkspaceIcons")
                minimum: 1
                maximum: 10
                onSliderValueChanged: newValue => root.page.set("maxWorkspaceIcons", newValue)
            }

            SettingsSliderRow {
                resetStore: root.page
                resetKeys: ["workspaceAppIconSizeOffset"]
                text: I18n.tr("Icon size")
                value: root.page.value("workspaceAppIconSizeOffset")
                minimum: 0
                maximum: 10
                unit: "px"
                onSliderValueChanged: newValue => root.page.set("workspaceAppIconSizeOffset", newValue)
            }
        }

        SettingsToggleRow {
            text: I18n.tr("Show occupied only")
            visible: CompositorService.supportsWorkspaces
            enabled: !CompositorService.isAqueous || (AqueousService.available && Quickshell.env("DMS_FORCE_EXTWS") !== "1")
            checked: root.page.value("showOccupiedWorkspacesOnly")
            onToggled: checked => root.page.set("showOccupiedWorkspacesOnly", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show scratchpads", "workspace switcher toggle, special workspaces as entries")
            description: I18n.tr("Special workspaces appear last; click to show or hide", "workspace switcher show scratchpads toggle description")
            visible: CompositorService.isHyprland
            checked: root.page.value("showSpecialWorkspaces")
            onToggled: checked => root.page.set("showSpecialWorkspaces", checked)
        }
    }

    WorkspaceAppearanceCard {
        store: root.page.store
    }

    SettingsCard {
        title: I18n.tr("Advanced")
        settingKey: "workspaceAdvanced"
        collapsible: true
        expanded: false

        SettingsToggleSliderRow {
            resetStore: root.page
            valueKeys: ["workspacePaddingCount"]
            text: I18n.tr("Minimum workspaces", "workspace switcher slider label")
            description: CompositorService.supportsPersistentWorkspaces ? I18n.tr("Workspaces up to the count are always shown and can be opened", "workspace switcher minimum workspaces description on compositors with persistent workspaces") : I18n.tr("Empty placeholders fill the switcher up to the count", "workspace switcher minimum workspaces description")
            checked: root.page.value("showWorkspacePadding")
            unit: ""
            value: root.page.value("workspacePaddingCount")
            minimum: 2
            maximum: 10
            onToggled: checked => root.page.set("showWorkspacePadding", checked)
            onSliderValueChanged: newValue => root.page.set("workspacePaddingCount", newValue)
        }

        SettingsToggleRow {
            enabled: root.showApps
            text: I18n.tr("Group apps")
            checked: root.page.value("groupWorkspaceApps")
            onToggled: checked => root.page.set("groupWorkspaceApps", checked)
        }

        SettingsToggleRow {
            enabled: root.showApps && root.page.value("groupWorkspaceApps")
            text: I18n.tr("Group on active workspace")
            checked: root.page.value("groupActiveWorkspaceApps")
            onToggled: checked => root.page.set("groupActiveWorkspaceApps", checked)
        }

        SettingsToggleRow {
            enabled: root.showApps
            text: I18n.tr("Highlight focused app")
            checked: root.page.value("workspaceActiveAppHighlightEnabled")
            onToggled: checked => root.page.set("workspaceActiveAppHighlightEnabled", checked)
        }

        SettingsToggleRow {
            enabled: root.showApps
            text: I18n.tr("Don't dim unfocused apps", "workspace switcher toggle: show icons of unfocused apps at full opacity")
            checked: root.page.value("workspaceUnfocusedAppsFullOpacity")
            onToggled: checked => root.page.set("workspaceUnfocusedAppsFullOpacity", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Follow display focus")
            description: I18n.tr("Lists workspaces from whichever display has focus", "workspace switcher follow display focus toggle description")
            visible: CompositorService.supportsWorkspaceFollowFocus
            checked: root.page.value("workspaceFollowFocus")
            onToggled: checked => root.page.set("workspaceFollowFocus", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Reverse scroll direction")
            visible: CompositorService.supportsWorkspaces
            checked: root.page.value("reverseScrolling")
            onToggled: checked => root.page.set("reverseScrolling", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Drag to reorder")
            visible: CompositorService.isNiri
            checked: root.page.value("workspaceDragReorder")
            onToggled: checked => root.page.set("workspaceDragReorder", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show all tags")
            visible: CompositorService.isMango
            checked: root.page.value("dwlShowAllTags")
            onToggled: checked => root.page.set("dwlShowAllTags", checked)
        }
    }
}
