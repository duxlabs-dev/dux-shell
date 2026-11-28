pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.FileBrowser
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/QmlUtils.js" as QmlUtils

Column {
    id: root

    property int columns: 1
    property real cellSpacing: Theme.spacingM
    property bool compact: false
    property var targetScreen: null
    property bool spinnerDue: false

    property var parentModal: null
    property string draggedId: ""

    function relayout() {
        if (profileList.draggingIndex < 0)
            profileList.layout();
    }

    function openPage(page, id, imported) {
        if (!id && !ConfigProfileService.screenshotTargetId && !ConfigProfileService.capturingId && !ConfigProfileService.draft?.thumbnail) {
            ConfigProfileService.discardDraft();
            SettingsUiState.dropConfigProfileEdits("");
        }
        ConfigProfileService.selectForSettings(id, imported);
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

    DReorderList {
        id: profileList

        width: root.width
        visible: ConfigProfileService.ready
        columns: root.columns
        spacing: root.cellSpacing
        Component.onCompleted: flickable = QmlUtils.findParentFlickable(root.parent)
        onDragStarted: index => root.draggedId = ConfigProfileService.profiles[index]?.id ?? ""
        onReordered: indices => {
            const profiles = ConfigProfileService.profiles;
            ConfigProfileService.setOrder(indices.map(i => profiles[i].id));
        }

        model: ScriptModel {
            values: ConfigProfileService.profiles
            objectProp: "id"
        }

        delegate: ProfileCard {
            required property var modelData

            reorderList: profileList
            compact: root.compact
            profile: ConfigProfileService.find(modelData.id) ?? modelData
            targetScreen: root.targetScreen
            onEditRequested: id => root.openPage("profile_edit", id)
            onMenuRequested: (x, y, keyboard) => {
                profileMenu.profile = profile;
                profileMenu.canReset = isActive && ConfigProfileService.canResetToApplied();
                const point = mapToItem(root, x, y);
                profileMenu.openAt(point.x, point.y);
                if (keyboard)
                    profileMenu.highlightEdge(false);
            }
        }
    }

    // A Repeater gives no signal when the ScriptModel moves delegates, so moves made elsewhere need a relayout.
    Connections {
        target: ConfigProfileService
        function onProfilesChanged() {
            if (profileList.draggingIndex >= 0 && ConfigProfileService.profiles[profileList.draggingIndex]?.id !== root.draggedId)
                profileList.cancel();
            Qt.callLater(root.relayout);
        }
    }

    FileMenu {
        id: profileMenu

        property var profile: null
        property bool canReset: false
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
            visible: profileMenu.isActive
            enabled: profileMenu.canReset
            iconName: "history"
            text: I18n.tr("Reset to when applied", "config profile menu: discard changes made since the profile was applied")
            onClicked: {
                profileMenu.close();
                ConfigProfileService.resetToApplied();
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
