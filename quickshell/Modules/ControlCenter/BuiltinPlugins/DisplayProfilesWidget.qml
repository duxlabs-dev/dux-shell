import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.Plugins
import qs.Modules.Settings.DisplayConfig

PluginComponent {
    id: root

    readonly property var allProfiles: DisplayConfigState.validatedProfiles || ({})
    readonly property var profiles: {
        const result = [];
        for (const id in allProfiles) {
            if (allProfiles[id].name)
                result.push({
                    id: id,
                    name: allProfiles[id].name
                });
        }
        return result;
    }
    readonly property bool autoMode: SettingsData.displayProfileAutoSelect
    readonly property string activeProfileId: SessionData.getActiveDisplayProfile(CompositorService.compositor)
    readonly property var activeProfile: allProfiles[activeProfileId] || null
    readonly property string activeProfileName: activeProfile?.name ?? ""
    readonly property string displayProfileLabel: {
        if (autoMode)
            return I18n.tr("Auto");
        if (activeProfileName.length > 0)
            return activeProfileName;
        if (profiles.length === 0)
            return I18n.tr("No profiles");
        return I18n.tr("None active");
    }

    ccWidgetIcon: "monitor"
    ccWidgetPrimaryText: I18n.tr("Display")
    ccWidgetSecondaryText: displayProfileLabel
    ccWidgetIsActive: autoMode || activeProfileId.length > 0

    onCcWidgetToggled: cycleNext()

    function setAutoMode(enabled) {
        SettingsData.displayProfileAutoSelect = enabled;
        if (!enabled)
            SessionData.setActiveDisplayProfile(CompositorService.compositor, "");
        SettingsData.saveSettings();
        if (enabled)
            DisplayConfigState.applyAutoConfig();
    }

    function cycleNext() {
        if (autoMode || profiles.length < 2)
            return;
        const idx = profiles.findIndex(p => p.id === activeProfileId);
        const next = profiles[(idx + 1) % profiles.length];
        DisplayConfigState.activateProfile(next.id);
    }

    ccDetailContent: Component {
        Item {
            id: detailRoot

            readonly property string title: I18n.tr("Display Profiles")
            readonly property Item headerActions: CcSettingsButton {
                settingsTab: "displays"
            }

            DFlickable {
                anchors.fill: parent
                contentHeight: detailColumn.height
                clip: true

                Column {
                    id: detailColumn
                    width: parent.width
                    spacing: CcMetrics.detailContentGap

                    CcGroup {
                        CcToggleRow {
                            text: I18n.tr("Auto")
                            description: root.autoMode ? I18n.tr("Auto mode is on. Manual profile selection is disabled.") : ""
                            checked: root.autoMode
                            onToggled: checked => root.setAutoMode(checked)
                        }
                    }

                    CcEmptyState {
                        visible: root.profiles.length === 0
                        iconName: "monitor"
                        title: I18n.tr("No display profiles found. Create them in Settings > Displays.")
                    }

                    CcGroup {
                        visible: root.profiles.length > 0

                        Repeater {
                            model: root.profiles

                            CcListRow {
                                required property var modelData

                                iconName: "monitor"
                                title: modelData.name
                                active: modelData.id === root.activeProfileId && !root.autoMode
                                enabled: !root.autoMode
                                clickable: true
                                onClicked: DisplayConfigState.activateProfile(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DIcon {
                name: "monitor"
                color: Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.displayProfileLabel
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS
            DIcon {
                name: "monitor"
                color: Theme.primary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.displayProfileLabel
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
    ccExpandedContent: Component {
        CcTileActions {
            actions: [
                {
                    text: I18n.tr("Auto"),
                    icon: "auto_mode",
                    toggle: true,
                    active: root.autoMode,
                    trigger: () => root.setAutoMode(!root.autoMode)
                }
            ].concat(root.profiles.map(profile => ({
                        text: profile.name,
                        icon: "monitor",
                        active: !root.autoMode && profile.id === root.activeProfileId,
                        enabled: !root.autoMode,
                        trigger: () => DisplayConfigState.activateProfile(profile.id)
                    })))
        }
    }
}
