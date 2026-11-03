import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

SettingsCard {
    id: root

    iconName: "palette"
    title: I18n.tr("Appearance")
    settingKey: "workspaceAppearance"
    tags: ["workspace", "focused", "color", "custom"]
    collapsible: true
    expanded: false

    property var store: null

    readonly property var colorLabels: ({
            "surfaceText": I18n.tr("Surface Text", "workspace color option"),
            "primary": I18n.tr("Primary", "workspace color option"),
            "primaryContainer": I18n.tr("Primary Container", "workspace color option"),
            "secondary": I18n.tr("Secondary", "workspace color option"),
            "sec": I18n.tr("Secondary", "workspace color option"),
            "secondaryContainer": I18n.tr("Secondary Container", "workspace color option"),
            "tertiary": I18n.tr("Tertiary", "workspace color option"),
            "tertiaryContainer": I18n.tr("Tertiary Container", "workspace color option"),
            "s": I18n.tr("Surface", "workspace color option"),
            "sc": I18n.tr("Surface Container", "workspace color option"),
            "sch": I18n.tr("Surface High", "workspace color option"),
            "schh": I18n.tr("Surface Highest", "workspace color option"),
            "none": I18n.tr("None", "workspace color option"),
            "custom": I18n.tr("Custom", "workspace color option")
        })

    function colorOptions(values, defaultLabel) {
        return values.map(value => ({
                    "value": value,
                    "label": value === "default" ? defaultLabel : colorLabels[value]
                }));
    }

    readonly property var focusedColorOptions: colorOptions(["default", "primaryContainer", "secondary", "secondaryContainer", "tertiary", "tertiaryContainer", "s", "sc", "sch", "schh", "none", "custom"], I18n.tr("Primary", "workspace color option"))
    readonly property var occupiedColorOptions: colorOptions(["none", "primary", "primaryContainer", "sec", "secondaryContainer", "tertiary", "tertiaryContainer", "s", "sc", "sch", "schh", "custom"])
    readonly property var unfocusedColorOptions: colorOptions(["default", "surfaceText", "primary", "secondary", "tertiary", "s", "sc", "sch", "schh", "custom"], I18n.tr("Default", "workspace color option"))
    readonly property var urgentColorOptions: colorOptions(["default", "primary", "primaryContainer", "secondary", "secondaryContainer", "tertiary", "tertiaryContainer", "s", "sc", "sch", "custom"], I18n.tr("Error", "workspace color option"))
    readonly property var borderColorOptions: colorOptions(["surfaceText", "primary", "primaryContainer", "secondary", "secondaryContainer", "tertiary", "tertiaryContainer", "custom"])

    function isFocusedAppearanceSection(section) {
        return ["workspaceAppearance", "workspaceIcons", "workspaceColorMode", "workspaceOccupiedColorMode", "workspaceUnfocusedColorMode", "workspaceUrgentColorMode", "workspaceFocusedBorderEnabled", "workspaceFocusedBorderColor", "workspaceFocusedBorderThickness"].includes(section);
    }

    SettingsRow {
        body: Item {
            width: parent.width
            height: workspaceTabBar.height + Theme.spacingM

            DTabBar {
                id: workspaceTabBar
                width: parent.width
                tabHeight: 44
                showIcons: false
                model: [({
                            "text": I18n.tr("Focused display", "workspace appearance tab")
                        }), ({
                            "text": I18n.tr("Unfocused displays", "workspace appearance tab")
                        })]
                onTabClicked: index => currentIndex = index
                Component.onCompleted: Qt.callLater(updateIndicator)

                Connections {
                    target: SettingsSearchService

                    function onTargetSectionChanged() {
                        const section = SettingsSearchService.targetSection;
                        if (!section)
                            return;

                        if (section.startsWith("workspaceUnfocusedMonitor")) {
                            root.expanded = true;
                            workspaceTabBar.currentIndex = 1;
                        } else if (root.isFocusedAppearanceSection(section)) {
                            root.expanded = true;
                            workspaceTabBar.currentIndex = 0;
                        } else {
                            return;
                        }

                        Qt.callLater(workspaceTabBar.updateIndicator);
                    }
                }
            }
        }
    }

    WorkspaceAppearanceColorOptions {
        visible: workspaceTabBar.currentIndex === 0
        store: root.store
        focusedColorOptions: root.focusedColorOptions
        occupiedColorOptions: root.occupiedColorOptions
        unfocusedColorOptions: root.unfocusedColorOptions
        urgentColorOptions: root.urgentColorOptions
        occupiedColorVisible: CompositorService.supportsWorkspaces
        urgentColorVisible: CompositorService.supportsWorkspaceUrgency
        focusedColorModeKey: "workspaceColorMode"
        focusedCustomColorKey: "workspaceFocusedCustomColor"
        occupiedColorModeKey: "workspaceOccupiedColorMode"
        occupiedCustomColorKey: "workspaceOccupiedCustomColor"
        unfocusedColorModeKey: "workspaceUnfocusedColorMode"
        unfocusedCustomColorKey: "workspaceUnfocusedCustomColor"
        urgentColorModeKey: "workspaceUrgentColorMode"
        urgentCustomColorKey: "workspaceUrgentCustomColor"
    }

    SettingsToggleRow {
        visible: workspaceTabBar.currentIndex === 0
        settingKey: "workspaceFocusedBorderEnabled"
        tags: ["workspace", "border", "outline", "focused", "ring"]
        text: I18n.tr("Focused border")
        checked: root.store.get("workspaceFocusedBorderEnabled")
        onToggled: checked => root.store.set("workspaceFocusedBorderEnabled", checked)
    }

    WorkspaceAppearanceBorderFields {
        store: root.store
        visible: (workspaceTabBar.currentIndex === 0) && (root.store.get("workspaceFocusedBorderEnabled"))
        borderColorOptions: root.borderColorOptions
        borderColorKey: "workspaceFocusedBorderColor"
        borderCustomColorKey: "workspaceFocusedBorderCustomColor"
        borderThicknessKey: "workspaceFocusedBorderThickness"
    }

    SettingsRow {
        visible: (workspaceTabBar.currentIndex === 1) && (!BarWidgetService.focusedScreenDetectionSupported)
        body: StyledText {
            width: parent.width
            text: I18n.tr("Separate appearance for unfocused displays is not supported on this compositor.")
            wrapMode: Text.WordWrap
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    SettingsToggleRow {
        visible: (workspaceTabBar.currentIndex === 1) && (BarWidgetService.focusedScreenDetectionSupported)
        settingKey: "workspaceUnfocusedMonitorSeparateAppearance"
        tags: ["workspace", "unfocused", "monitor", "display", "separate", "color"]
        text: I18n.tr("Separate appearance")
        checked: root.store.get("workspaceUnfocusedMonitorSeparateAppearance")
        onToggled: checked => root.store.set("workspaceUnfocusedMonitorSeparateAppearance", checked)
    }

    WorkspaceAppearanceColorOptions {
        enabled: root.store.get("workspaceUnfocusedMonitorSeparateAppearance")
        visible: (workspaceTabBar.currentIndex === 1) && (BarWidgetService.focusedScreenDetectionSupported)
        store: root.store
        focusedColorOptions: root.focusedColorOptions
        occupiedColorOptions: root.occupiedColorOptions
        unfocusedColorOptions: root.unfocusedColorOptions
        urgentColorOptions: root.urgentColorOptions
        occupiedColorVisible: CompositorService.supportsWorkspaces
        urgentColorVisible: CompositorService.supportsWorkspaceUrgency
        extraTags: ["unfocused", "monitor", "display"]
        focusedColorModeKey: "workspaceUnfocusedMonitorColorMode"
        focusedCustomColorKey: "workspaceUnfocusedMonitorFocusedCustomColor"
        occupiedColorModeKey: "workspaceUnfocusedMonitorOccupiedColorMode"
        occupiedCustomColorKey: "workspaceUnfocusedMonitorOccupiedCustomColor"
        unfocusedColorModeKey: "workspaceUnfocusedMonitorUnfocusedColorMode"
        unfocusedCustomColorKey: "workspaceUnfocusedMonitorUnfocusedCustomColor"
        urgentColorModeKey: "workspaceUnfocusedMonitorUrgentColorMode"
        urgentCustomColorKey: "workspaceUnfocusedMonitorUrgentCustomColor"
    }

    SettingsToggleRow {
        enabled: root.store.get("workspaceUnfocusedMonitorSeparateAppearance")
        visible: (workspaceTabBar.currentIndex === 1) && (BarWidgetService.focusedScreenDetectionSupported)
        settingKey: "workspaceUnfocusedMonitorBorderEnabled"
        tags: ["workspace", "border", "outline", "focused", "ring", "unfocused", "monitor", "display"]
        text: I18n.tr("Focused border")
        checked: root.store.get("workspaceUnfocusedMonitorBorderEnabled")
        onToggled: checked => root.store.set("workspaceUnfocusedMonitorBorderEnabled", checked)
    }

    WorkspaceAppearanceBorderFields {
        enabled: root.store.get("workspaceUnfocusedMonitorSeparateAppearance")
        store: root.store
        visible: (workspaceTabBar.currentIndex === 1) && ((BarWidgetService.focusedScreenDetectionSupported) && (root.store.get("workspaceUnfocusedMonitorBorderEnabled")))
        borderColorOptions: root.borderColorOptions
        extraTags: ["unfocused", "monitor", "display"]
        borderColorKey: "workspaceUnfocusedMonitorBorderColor"
        borderCustomColorKey: "workspaceUnfocusedMonitorBorderCustomColor"
        borderThicknessKey: "workspaceUnfocusedMonitorBorderThickness"
    }

    readonly property var namedWorkspaces: NiriService.getNamedWorkspaces().concat(CompositorService.specialWorkspaceNames)

    SettingsRow {
        visible: root.namedWorkspaces.length > 0
        settingKey: "workspaceIcons"
        tags: ["workspace", "icon", "named", "scratchpad", "special"]
        title: I18n.tr("Icons")
        subtitle: I18n.tr("Named workspaces and scratchpads", "workspace appearance row subtitle")
    }

    Repeater {
        model: root.namedWorkspaces

        SettingsRow {
            required property string modelData

            title: modelData

            DIconPicker {
                id: iconPicker
                anchors.verticalCenter: parent.verticalCenter

                Component.onCompleted: {
                    const iconData = SettingsData.getWorkspaceNameIcon(modelData);
                    if (iconData)
                        setIcon(iconData.value, iconData.type);
                }

                onIconSelected: (iconName, iconType) => {
                    SettingsData.setWorkspaceNameIcon(modelData, {
                        "type": iconType,
                        "value": iconName
                    });
                    setIcon(iconName, iconType);
                }

                Connections {
                    target: SettingsData
                    function onWorkspaceIconsUpdated() {
                        const iconData = SettingsData.getWorkspaceNameIcon(modelData);
                        if (iconData) {
                            iconPicker.setIcon(iconData.value, iconData.type);
                            return;
                        }
                        iconPicker.setIcon("", "icon");
                    }
                }
            }

            DActionButton {
                buttonSize: Theme.iconButtonSize
                iconName: "close"
                Accessible.name: I18n.tr("Remove")
                iconSize: Theme.iconSizeMedium
                iconColor: Theme.error
                anchors.verticalCenter: parent.verticalCenter
                onClicked: SettingsData.removeWorkspaceNameIcon(modelData)
            }
        }
    }
}
