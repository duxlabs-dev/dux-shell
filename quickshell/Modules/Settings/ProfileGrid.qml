pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.FileBrowser
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property int columns: 1
    property real cellSpacing: Theme.spacingM
    property bool compact: false
    property var targetScreen: null
    property bool spinnerDue: false

    property var parentModal: null

    function openPage(page, id, imported) {
        SettingsUiState.selectedConfigProfileId = id;
        SettingsUiState.selectedConfigProfileImported = !!imported;
        SettingsUiState.selectedWidgetTitle = ConfigProfileService.find(id)?.name ?? I18n.tr("New profile");
        parentModal?.navigateTo(page);
    }

    Timer {
        interval: SettingsMetrics.pageSpinnerDelay
        running: !ConfigProfileService.ready
        onTriggered: root.spinnerDue = true
    }

    Item {
        width: root.width
        height: Theme.iconSizeLarge * 2
        visible: !ConfigProfileService.ready

        DSpinner {
            anchors.centerIn: parent
            visible: root.spinnerDue
        }
    }

    Grid {
        id: grid
        readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns

        width: root.width
        visible: ConfigProfileService.ready
        columns: root.columns
        columnSpacing: root.cellSpacing
        rowSpacing: root.cellSpacing

        Repeater {
            model: ConfigProfileService.profiles

            ProfileCard {
                required property var modelData

                width: grid.cellWidth
                compact: root.compact
                profile: modelData
                targetScreen: root.targetScreen
                onEditRequested: id => root.openPage("profile_edit", id)
                onMenuRequested: (x, y, keyboard) => {
                    profileMenu.profile = modelData;
                    const point = mapToItem(root, x, y);
                    profileMenu.openAt(point.x, point.y);
                    if (keyboard)
                        profileMenu.highlightEdge(false);
                }
            }
        }
    }

    FileMenu {
        id: profileMenu

        property var profile: null
        readonly property bool isActive: profile?.id === ConfigProfileService.activeProfileId

        anchorItem: root

        FileMenuItem {
            visible: !profileMenu.isActive
            iconName: "check_circle"
            text: I18n.tr("Apply")
            onClicked: {
                profileMenu.close();
                ConfigProfileService.activate(profileMenu.profile.id);
            }
        }

        FileMenuItem {
            iconName: "rule"
            text: I18n.tr("Partial apply", "config profile menu: open Compare to apply only some groups")
            onClicked: {
                profileMenu.close();
                root.openPage("profile_inspect", profileMenu.profile.id);
            }
        }

        FileMenuItem {
            iconName: "edit"
            text: I18n.tr("Edit")
            onClicked: {
                profileMenu.close();
                root.openPage("profile_edit", profileMenu.profile.id);
            }
        }

        FileMenuItem {
            iconName: "delete"
            danger: true
            text: I18n.tr("Delete")
            onClicked: {
                profileMenu.close();
                const profile = profileMenu.profile;
                deleteConfirm.request(profile, () => ConfigProfileService.deleteProfile(profile.id));
            }
        }
    }

    ProfileDeleteConfirm {
        id: deleteConfirm
    }
}
