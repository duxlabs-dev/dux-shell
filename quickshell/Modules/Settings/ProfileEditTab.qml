pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/settings/ConfigProfiles.js" as Profiles

Item {
    id: root

    property var parentModal: null
    property bool pageActive: true

    readonly property string profileId: SettingsUiState.selectedConfigProfileId
    property bool leaving: false
    property var frozenProfile: null
    readonly property var profile: leaving ? frozenProfile : ConfigProfileService.find(profileId)
    readonly property bool isNew: profile === null

    property string pendingName: ""
    property var pendingGroups: Profiles.GROUPS.slice()
    property var expandedCategories: []
    property bool pendingSync: true
    property bool nameInvalid: false
    readonly property bool dirty: !!profile && (pendingName.trim() !== profile.name || pendingSync !== !!profile.sync || pendingGroups.length !== profile.groups.length || pendingGroups.some(g => !profile.groups.includes(g)))

    property string heldImageId: ""
    readonly property string imageId: isNew ? heldImageId : profileId
    readonly property var imageOwner: isNew ? (ConfigProfileService.draft ?? ConfigProfileService.find(heldImageId)) : profile

    // A pending screenshot and its draft survive closing Settings, so the user can set up the screen without it.
    function _release() {
        if (!heldImageId || (ConfigProfileService.screenshotTargetId === heldImageId && !(parentModal?.shouldBeVisible ?? false)))
            return;
        if (ConfigProfileService.screenshotTargetId === heldImageId)
            ConfigProfileService.cancelScreenshot();
        if (ConfigProfileService.draft?.id === heldImageId)
            ConfigProfileService.discardDraft();
    }

    function _reset() {
        const kept = isNew ? (ConfigProfileService.draft?.id ?? "") : profileId;
        if (heldImageId !== kept)
            _release();
        leaving = false;
        frozenProfile = null;
        heldImageId = isNew ? (ConfigProfileService.draft?.id || ConfigProfileService.startDraft()) : profileId;
        const p = profile;
        pendingName = p?.name ?? "";
        pendingGroups = p ? p.groups.slice() : Profiles.GROUPS.slice();
        expandedCategories = [];
        pendingSync = p ? !!p.sync : true;
        nameInvalid = false;
        nameField.text = pendingName;
    }

    function _setGroups(groups, on) {
        const next = Profiles.GROUPS.filter(g => groups.includes(g) ? on : pendingGroups.includes(g));
        if (next.length)
            pendingGroups = next;
        else
            ToastService.showWarning(I18n.tr("At least one group must remain selected", "config profile editor: shown when the user turns off the last settings group"));
    }


    function _toggleExpanded(id) {
        expandedCategories = expandedCategories.includes(id) ? expandedCategories.filter(c => c !== id) : expandedCategories.concat(id);
    }

    function _submit() {
        const name = pendingName.trim();
        if (!name) {
            nameInvalid = true;
            nameField.forceActiveFocus();
            return;
        }
        const ok = isNew ? ConfigProfileService.createProfile(name, pendingGroups, pendingSync) !== "" : ConfigProfileService.updateProfile(profileId, name, pendingGroups, pendingSync);
        if (ok)
            parentModal?.goBack();
        else if (!isNew)
            ToastService.showError(I18n.tr("Failed to save profile"));
    }

    function _updateFromCurrent() {
        if (!ConfigProfileService.updateFromCurrent(profileId))
            ToastService.showError(I18n.tr("Failed to save profile"));
    }

    function _deleteConfirmed() {
        frozenProfile = profile;
        leaving = true;
        if (ConfigProfileService.deleteProfile(profileId))
            parentModal?.goBack();
        else
            leaving = false;
    }

    function _openBrowser() {
        imageBrowserLoader.active = true;
        (imageBrowserLoader.item as FileBrowserModal)?.open();
    }

    function _openExport() {
        exportBrowserLoader.active = true;
        const b = exportBrowserLoader.item as FileBrowserModal;
        if (!b)
            return;
        const base = (profile?.name ?? "").replace(/[\/\\:*?"<>|\x00-\x1f]+/g, "_").trim().replace(/^\.+/, "");
        b.defaultFileName = (base || profileId) + ".tar.gz";
        b.open();
    }

    onProfileIdChanged: _reset()
    onPageActiveChanged: {
        if (pageActive)
            _reset();
        else
            _release();
    }
    Component.onCompleted: {
        _reset();
        nameField.forceActiveFocus();
    }
    Component.onDestruction: _release()

    SettingsPage {
        SettingsCard {
            width: parent.width

            SettingsRow {
                body: DTextField {
                    id: nameField
                    outlined: true
                    labelText: I18n.tr("Profile name")
                    width: parent.width
                    isError: root.nameInvalid
                    onTextEdited: {
                        root.pendingName = text;
                        root.nameInvalid = false;
                    }
                    onAccepted: root._submit()
                }
            }

            SettingsNoteRow {
                visible: root.isNew || SettingsUiState.selectedConfigProfileImported
                noteIconName: "info"
                tint: Theme.surfaceVariantText
                tintBackground: Theme.surfaceVariantAlpha
                text: root.isNew ? I18n.tr("The new profile uses your current settings for the groups selected below", "config profile editor note, shown when creating a profile") : I18n.tr("Select settings to import", "config profile editor note, shown right after importing a profile")
            }

            Repeater {
                model: Profiles.CATEGORIES

                Column {
                    id: scopeCategory

                    required property var modelData
                    readonly property var groups: modelData.groups
                    readonly property var selected: groups.filter(g => root.pendingGroups.includes(g))
                    readonly property bool expanded: root.expandedCategories.includes(modelData.id)

                    width: parent?.width ?? 0
                    spacing: Theme.groupedListGap

                    SettingsRow {
                        title: ConfigProfileService.categoryLabel(scopeCategory.modelData.id)
                        subtitle: (scopeCategory.selected.length > 0 ? scopeCategory.selected : scopeCategory.groups).map(g => ConfigProfileService.groupLabel(g)).join(", ")
                        clickable: true
                        resetKeys: []
                        Accessible.description: subtitle + ". " + (scopeCategory.expanded ? I18n.tr("Collapse") : I18n.tr("Expand"))
                        onClicked: root._toggleExpanded(scopeCategory.modelData.id)

                        DIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: scopeCategory.expanded ? "expand_less" : "expand_more"
                            size: Theme.iconSize
                            color: Theme.surfaceVariantText
                        }

                        DToggle {
                            anchors.verticalCenter: parent.verticalCenter
                            hideText: true
                            text: ConfigProfileService.categoryLabel(scopeCategory.modelData.id)
                            checked: scopeCategory.selected.length > 0
                            onToggled: on => root._setGroups(scopeCategory.groups, on)
                        }
                    }

                    SettingsRow {
                        visible: scopeCategory.expanded
                        body: DFilterChips {
                            width: parent?.width ?? 0
                            multiSelect: true
                            showCounts: false
                            model: scopeCategory.groups.map(g => ({
                                        "value": g,
                                        "label": ConfigProfileService.groupLabel(g)
                                    }))
                            selectedValues: root.pendingGroups
                            onSelectionToggled: (index, selected) => root._setGroups([scopeCategory.groups[index]], selected)
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width

            SettingsRow {
                title: I18n.tr("Image", "config profile thumbnail")
                body: [
                    ProfilePreview {
                        width: Math.min(parent?.width ?? 0, SettingsMetrics.mediaMaxWidth)
                        owner: root.imageOwner
                        targetScreen: root.parentModal?.screen ?? Quickshell.screens[0] ?? null
                    },
                    Flow {
                        width: parent?.width ?? 0
                        spacing: Theme.spacingS

                        DButton {
                            text: I18n.tr("Browse Files")
                            iconName: "folder_open"
                            backgroundColor: Theme.secondaryContainer
                            textColor: Theme.onSecondaryContainer
                            enabled: root.imageId !== ""
                            onClicked: root._openBrowser()
                        }

                        DButton {
                            text: I18n.tr("Take screenshot", "config profile image: take a screenshot of the current screen")
                            iconName: "screenshot_monitor"
                            backgroundColor: Theme.secondaryContainer
                            textColor: Theme.onSecondaryContainer
                            enabled: root.imageId !== "" && ConfigProfileService.screenshotTargetId === ""
                            onClicked: ConfigProfileService.startScreenshot(root.imageId)
                        }
                    }
                ]
            }
        }

        SettingsCard {
            width: parent.width
            visible: !root.isNew && root.profileId === ConfigProfileService.activeProfileId

            SettingsToggleRow {
                text: I18n.tr("Sync changes to this profile", "config profile toggle: write later setting changes into this profile")
                checked: root.pendingSync
                onToggled: on => root.pendingSync = on
            }
        }

        SettingsCard {
            width: parent.width
            visible: !root.isNew

            SettingsRow {
                subtitle: root.dirty ? I18n.tr("Unsaved changes") : ""
                body: Flow {
                    width: parent?.width ?? 0
                    spacing: Theme.spacingS

                    DButton {
                        enabled: !root.dirty
                        text: I18n.tr("Update from current settings", "config profile action: overwrite the profile with the current setup")
                        iconName: "sync"
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: confirm.showWithOptions({
                            title: I18n.tr("Update from current settings", "config profile action: overwrite the profile with the current setup"),
                            message: I18n.tr("Replace settings of profile \"%1\"?", "confirm dialog message, %1 is the config profile name").arg(root.profile?.name ?? ""),
                            confirmText: I18n.tr("Update"),
                            onConfirm: () => root._updateFromCurrent()
                        })
                    }

                    DButton {
                        text: I18n.tr("Export", "config profile action: save the profile as an archive file")
                        iconName: "upload"
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        enabled: !root.dirty
                        onClicked: root._openExport()
                    }
                }
            }

            SettingsNavRow {
                title: I18n.tr("Compare", "config profile: page and link row showing what applying the profile would change")
                onClicked: keyboard => root.parentModal?.navigateTo("profile_inspect", keyboard)
            }
        }

        SettingsCard {
            width: parent.width
            visible: !root.isNew

            SettingsRow {
                body: DButton {
                    text: I18n.tr("Delete profile")
                    iconName: "delete"
                    backgroundColor: SettingsMetrics.controlSurface
                    textColor: Theme.error
                    onClicked: confirm.request(root.profile, () => root._deleteConfirmed())
                }
            }
        }

        SettingsFabBar {
            DFab {
                text: root.isNew ? I18n.tr("Create") : I18n.tr("Save")
                iconName: root.isNew ? "add" : "check"
                colorRole: root.isNew ? "primaryContainer" : "primary"
                onClicked: root._submit()
            }
        }
    }

    ProfileDeleteConfirm {
        id: confirm
    }

    LazyLoader {
        id: imageBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            bucket: "wallpaper"
            showHiddenFiles: true
            filters: ConfigProfileService.imageExtensions.map(e => "*." + e)
            onAccepted: paths => ConfigProfileService.setImageFromFile(root.imageId, paths[0])
        }
    }

    LazyLoader {
        id: exportBrowserLoader
        active: false

        FileBrowserModal {
            parentModal: root.parentModal
            bucket: "profile_export"
            saveMode: true
            browserTitle: I18n.tr("Export", "config profile action: save the profile as an archive file")
            filters: ["*.tar.gz"]
            onAccepted: paths => ConfigProfileService.exportProfile(root.profileId, paths[0])
        }
    }
}
