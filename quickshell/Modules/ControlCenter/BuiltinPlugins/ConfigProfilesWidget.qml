import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.ControlCenter
import qs.Modules.ControlCenter.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    readonly property var profiles: ConfigProfileService.profiles
    readonly property string activeProfileId: ConfigProfileService.activeProfileId
    readonly property string activeProfileName: ConfigProfileService.activeProfile?.name ?? ""

    ccWidgetIcon: "style"
    ccWidgetPrimaryText: I18n.tr("Profiles")
    ccWidgetSecondaryText: activeProfileName || (profiles.length ? I18n.tr("None active") : I18n.tr("No profiles"))
    ccWidgetIsActive: activeProfileId.length > 0

    Component.onCompleted: ConfigProfileService.ensureDefault()

    onCcWidgetToggled: cycleNext()

    function cycleNext() {
        if (profiles.length === 0 || (profiles.length < 2 && activeProfileId))
            return;
        const idx = profiles.findIndex(p => p.id === activeProfileId);
        ConfigProfileService.activate(profiles[(idx + 1) % profiles.length].id);
    }

    ccDetailContent: Component {
        Item {
            readonly property string title: I18n.tr("Profiles")
            readonly property Item headerActions: CcSettingsButton {
                settingsTab: "profiles"
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
                        Repeater {
                            model: root.profiles

                            CcListRow {
                                required property var modelData

                                iconName: "style"
                                title: modelData.name
                                active: modelData.id === root.activeProfileId
                                clickable: true
                                onClicked: ConfigProfileService.activate(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    ccExpandedContent: Component {
        CcTileActions {
            actions: root.profiles.map(profile => ({
                        text: profile.name,
                        icon: "style",
                        active: profile.id === root.activeProfileId,
                        trigger: () => ConfigProfileService.activate(profile.id)
                    }))
        }
    }
}
