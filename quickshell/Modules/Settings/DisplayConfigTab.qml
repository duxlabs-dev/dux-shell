import QtQuick
import qs.Common
import qs.Modals
import qs.Modals.FileBrowser
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DisplayConfig

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null
    property string pendingICCOutput: ""

    property string selectedProfileId: {
        const id = SessionData.activeDisplayProfile[CompositorService.compositor] || "";
        if (!SettingsData.displayProfileAutoSelect) {
            const profile = DisplayConfigState.validatedProfiles[id];
            if (profile && profile.name === "")
                return "";
        }
        return id;
    }
    property bool showNewProfileDialog: false
    property bool showDeleteConfirmDialog: false
    property bool showRenameDialog: false
    property bool showEditMonitorsDialog: false
    property string newProfileName: ""
    property string renameProfileName: ""
    property var editMonitorSelection: ({})

    function getProfileOptions() {
        return Object.values(DisplayConfigState.validatedProfiles).filter(p => p.name !== "").map(p => p.name);
    }

    function getProfileIds() {
        return Object.keys(DisplayConfigState.validatedProfiles);
    }

    function getProfileIdByName(name) {
        const profiles = DisplayConfigState.validatedProfiles;
        for (const id in profiles) {
            if (profiles[id].name === name)
                return id;
        }
        return "";
    }

    function getProfileNameById(id) {
        const profiles = DisplayConfigState.validatedProfiles;
        return profiles[id]?.name || "";
    }

    function openEditMonitorsDialog() {
        if (!root.selectedProfileId)
            return;
        editMonitorSelection = DisplayConfigState.getProfileMonitorInclusion(root.selectedProfileId);
        showEditMonitorsDialog = true;
    }

    Connections {
        target: DisplayConfigState
        function onChangesApplied(changeDescriptions) {
            confirmationModal.changes = changeDescriptions;
            confirmationModal.open();
        }
        function onChangesConfirmed() {
        }
        function onChangesReverted() {
        }
        function onProfileActivated(profileId, profileName) {
            ToastService.showInfo(I18n.tr("Profile activated: %1", "toast after switching display profile, %1 is the profile name").arg(profileName));
        }
        function onProfileSaved(profileId, profileName) {
            ToastService.showInfo(I18n.tr("Profile saved: %1", "toast after saving a display profile, %1 is the profile name").arg(profileName));
        }
        function onProfileDeleted(profileId) {
            ToastService.showInfo(I18n.tr("Profile deleted"));
        }
        function onProfileError(message) {
            ToastService.showError(I18n.tr("Profile error"), message);
        }
    }

    SettingsPage {
        id: mainColumn

        IncludeSetupBanner {
            include: DisplayConfigState.include
            visibleCondition: DisplayConfigState.hasOutputBackend
        }

        SettingsCard {
            width: parent.width
            visible: CompositorService.isAqueous && DisplayConfigState.validationError !== ""

            SettingsRow {
                subtitle: DisplayConfigState.validationError
                subtitleColor: Theme.error

                DButton {
                    text: I18n.tr("Discard draft and reload", "Discard unsaved Aqueous display settings and refresh the current display state")
                    enabled: !DisplayConfigState.validatingConfig
                    onClicked: DisplayConfigState.discardAqueousPreview()
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "tune"
            title: I18n.tr("Profiles", "card title for display configuration profiles")
            visible: DisplayConfigState.hasOutputBackend

            SettingsToggleRow {
                settingKey: "displayProfileAutoSelect"
                text: I18n.tr("Auto")
                description: I18n.tr("Applies the saved profile that matches the connected displays", "display profile auto select toggle description")
                checked: SettingsData.displayProfileAutoSelect
                onToggled: checked => {
                    SettingsData.displayProfileAutoSelect = checked;
                    if (!checked)
                        SessionData.setActiveDisplayProfile(CompositorService.compositor, "");
                    SettingsData.saveSettings();
                    if (checked)
                        DisplayConfigState.applyAutoConfig();
                }
            }

            SettingsRow {
                visible: !root.showNewProfileDialog && !root.showDeleteConfirmDialog && !root.showRenameDialog && !root.showEditMonitorsDialog
                subtitle: SettingsData.displayProfileAutoSelect ? I18n.tr("Disabled by Auto", "display profiles row, Auto is the profile auto select toggle above it") : ""
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS
                    opacity: SettingsData.displayProfileAutoSelect ? 0.4 : 1.0

                    DDropdown {
                        id: profileDropdown
                        downKeyOpens: false
                        backgroundColor: SettingsMetrics.controlSurface
                        width: parent.width - newButton.width - editMonitorsButton.width - deleteButton.width - Theme.spacingS * 3
                        compactMode: true
                        dropdownWidth: width
                        options: root.getProfileOptions()
                        emptyText: I18n.tr("No profiles")
                        enabled: !SettingsData.displayProfileAutoSelect
                        onValueChanged: value => {
                            const profileId = root.getProfileIdByName(value);
                            if (profileId && profileId !== root.selectedProfileId)
                                DisplayConfigState.activateProfile(profileId);
                        }
                    }

                    Binding {
                        target: profileDropdown
                        property: "currentValue"
                        value: SettingsData.displayProfileAutoSelect ? I18n.tr("Auto") : root.getProfileNameById(root.selectedProfileId)
                    }

                    DButton {
                        id: newButton
                        tooltipText: I18n.tr("New profile")
                        iconName: "add"
                        text: ""
                        horizontalPadding: Theme.spacingM
                        backgroundColor: SettingsMetrics.controlSurface
                        textColor: Theme.surfaceText
                        enabled: !SettingsData.displayProfileAutoSelect
                        onClicked: {
                            root.newProfileName = "";
                            root.showNewProfileDialog = true;
                        }
                    }

                    DButton {
                        id: editMonitorsButton
                        tooltipText: I18n.tr("Edit monitors")
                        iconName: "edit"
                        text: ""
                        horizontalPadding: Theme.spacingM
                        backgroundColor: SettingsMetrics.controlSurface
                        textColor: Theme.surfaceText
                        enabled: root.selectedProfileId !== "" && !SettingsData.displayProfileAutoSelect
                        onClicked: root.openEditMonitorsDialog()
                    }

                    DButton {
                        id: deleteButton
                        Accessible.name: I18n.tr("Delete profile")
                        iconName: "delete"
                        text: ""
                        horizontalPadding: Theme.spacingM
                        backgroundColor: SettingsMetrics.controlSurface
                        textColor: Theme.error
                        enabled: root.selectedProfileId !== "" && !SettingsData.displayProfileAutoSelect
                        onClicked: root.showDeleteConfirmDialog = true
                    }
                }
            }

            SettingsRow {
                visible: root.showNewProfileDialog
                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DTextField {
                        id: newProfileField
                        outlined: true
                        leftIconName: "badge"
                        labelText: I18n.tr("Profile name")
                        width: parent.width - createButton.width - cancelNewButton.width - Theme.spacingS * 2
                        text: root.newProfileName
                        onTextChanged: root.newProfileName = text
                        onAccepted: {
                            if (text.trim())
                                DisplayConfigState.createProfile(text.trim());
                            root.showNewProfileDialog = false;
                        }
                        Component.onCompleted: forceActiveFocus()
                    }

                    DButton {
                        id: createButton
                        text: I18n.tr("Create")
                        enabled: root.newProfileName.trim() !== ""
                        onClicked: {
                            DisplayConfigState.createProfile(root.newProfileName.trim());
                            root.showNewProfileDialog = false;
                        }
                    }

                    DButton {
                        id: cancelNewButton
                        text: I18n.tr("Cancel")
                        backgroundColor: "transparent"
                        textColor: Theme.surfaceText
                        onClicked: root.showNewProfileDialog = false
                    }
                }
            }

            SettingsRow {
                visible: root.showDeleteConfirmDialog
                title: I18n.tr("Delete profile \"%1\"?", "delete confirmation, %1 is the display profile name").arg(root.getProfileNameById(root.selectedProfileId))

                DButton {
                    text: I18n.tr("Delete")
                    backgroundColor: Theme.error
                    textColor: Theme.primaryText
                    onClicked: {
                        DisplayConfigState.deleteProfile(root.selectedProfileId);
                        root.showDeleteConfirmDialog = false;
                    }
                }

                DButton {
                    text: I18n.tr("Cancel")
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceText
                    onClicked: root.showDeleteConfirmDialog = false
                }
            }

            SettingsRow {
                visible: root.showEditMonitorsDialog
                title: I18n.tr("Displays in \"%1\"", "monitor list heading, %1 is the display profile name").arg(root.getProfileNameById(root.selectedProfileId)) + ":"
            }

            Repeater {
                model: Object.keys(DisplayConfigState.allOutputs || {})

                delegate: SettingsToggleRow {
                    required property string modelData

                    visible: root.showEditMonitorsDialog
                    text: {
                        const od = DisplayConfigState.allOutputs[modelData];
                        return DisplayConfigState.getOutputDisplayName(od, modelData);
                    }
                    description: DisplayConfigState.allOutputs[modelData]?.connected ? I18n.tr("Connected") : I18n.tr("Disconnected")
                    descriptionColor: DisplayConfigState.allOutputs[modelData]?.connected ? Theme.success : Theme.surfaceVariantText
                    checked: root.editMonitorSelection[modelData] ?? false
                    onToggled: checked => {
                        const sel = Object.assign({}, root.editMonitorSelection);
                        sel[modelData] = checked;
                        root.editMonitorSelection = sel;
                    }
                }
            }

            SettingsRow {
                visible: root.showEditMonitorsDialog

                DButton {
                    text: I18n.tr("Save")
                    enabled: Object.values(root.editMonitorSelection).some(v => v)
                    onClicked: {
                        const enabled = Object.keys(root.editMonitorSelection).filter(k => root.editMonitorSelection[k]);
                        DisplayConfigState.updateProfileMonitors(root.selectedProfileId, enabled);
                        root.showEditMonitorsDialog = false;
                    }
                }

                DButton {
                    text: I18n.tr("Cancel")
                    backgroundColor: "transparent"
                    textColor: Theme.surfaceText
                    onClicked: root.showEditMonitorsDialog = false
                }
            }
        }

        SettingsCard {
            width: parent.width
            iconName: "monitor"
            title: I18n.tr("Arrangement", "card title for monitor arrangement")
            visible: DisplayConfigState.hasOutputBackend

            SettingsToggleRow {
                settingKey: "displaySnapToEdge"
                visible: monitorCanvas.filteredOutputs.length > 1
                text: I18n.tr("Snap", "verb, toggle to snap monitors to edges when arranging")
                description: I18n.tr("Dragged displays line up with neighboring edges without overlapping", "display arrangement snap toggle description")
                checked: SettingsData.displaySnapToEdge
                onToggled: checked => SettingsData.set("displaySnapToEdge", checked)
            }

            SettingsButtonGroupRow {
                id: displayFormatGroup
                settingKey: "displayNameMode"
                resetKeys: []
                visible: !CompositorService.isMango
                text: I18n.tr("Name format")
                model: [I18n.tr("Name"), I18n.tr("Model")]
                currentIndex: SettingsData.displayNameMode === "model" ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    const newMode = index === 1 ? "model" : "system";
                    DisplayConfigState.setOriginalDisplayNameMode(SettingsData.displayNameMode);
                    SettingsData.displayNameMode = newMode;
                }

                Connections {
                    target: SettingsData
                    function onDisplayNameModeChanged() {
                        displayFormatGroup.currentIndex = SettingsData.displayNameMode === "model" ? 1 : 0;
                    }
                }
            }

            MonitorCanvas {
                id: monitorCanvas
                width: parent.width
            }

            SettingsRow {
                visible: {
                    const all = DisplayConfigState.allOutputs || {};
                    const disconnected = Object.keys(all).filter(k => !all[k]?.connected);
                    return disconnected.length > 0;
                }
                title: {
                    const all = DisplayConfigState.allOutputs || {};
                    const disconnected = Object.keys(all).filter(k => !all[k]?.connected);
                    if (SettingsData.displayShowDisconnected)
                        return I18n.tr("%1 disconnected", "displays row title, %1 is a count of disconnected monitors").arg(disconnected.length);
                    return I18n.tr("%1 disconnected (hidden)", "displays row title, %1 is a count of disconnected monitors").arg(disconnected.length);
                }

                DButton {
                    text: SettingsData.displayShowDisconnected ? I18n.tr("Hide") : I18n.tr("Show")
                    backgroundColor: "transparent"
                    textColor: Theme.primary
                    onClicked: {
                        SettingsData.displayShowDisconnected = !SettingsData.displayShowDisconnected;
                        SettingsData.saveSettings();
                    }
                }
            }
        }

        Repeater {
            model: {
                if (!DisplayConfigState.hasOutputBackend)
                    return [];
                const keys = Object.keys(DisplayConfigState.allOutputs || {});
                if (SettingsData.displayShowDisconnected)
                    return keys;
                return keys.filter(k => DisplayConfigState.allOutputs[k]?.connected);
            }

            delegate: OutputCard {
                required property string modelData
                outputName: modelData
                outputData: DisplayConfigState.allOutputs[modelData]
                onRequestICCBrowse: name => {
                    root.pendingICCOutput = name;
                    iccFileBrowser.open();
                }
                onRequestICCInfo: name => iccInfoModal.showProfile(name)
            }
        }

        NoBackendMessage {
            width: parent.width
            visible: !DisplayConfigState.hasOutputBackend
        }

        SettingsFabBar {
            id: pendingChangesBar
            shown: DisplayConfigState.hasOutputBackend && DisplayConfigState.hasPendingChanges

            DFab {
                text: I18n.tr("Discard", "verb, button to discard pending changes")
                iconName: "undo"
                colorRole: "secondaryContainer"
                onClicked: DisplayConfigState.discardChanges()
            }

            DFab {
                text: I18n.tr("Apply changes")
                iconName: "check"
                colorRole: "primary"
                onClicked: DisplayConfigState.applyChanges()
            }
        }
    }

    ICCProfileInfoModal {
        id: iccInfoModal
    }

    FileBrowserModal {
        id: iccFileBrowser
        parentModal: root.parentModal || null
        browserTitle: I18n.tr("Select ICC Profile", "ICC profile file browser title")
        bucket: "icc"
        filters: ["*.icc", "*.icm"]
        onAccepted: paths => {
            if (pendingICCOutput)
                ICCService.applyICC(pendingICCOutput, paths[0]);
        }
    }

    DisplayConfirmationModal {
        id: confirmationModal
        onConfirmed: DisplayConfigState.confirmChanges(root.selectedProfileId)
        onReverted: DisplayConfigState.revertChanges()
    }

    readonly property bool identifyConfigured: {
        if (!DisplayConfigState.hasOutputBackend || DisplayConfigState.readOnly)
            return false;
        if (!DisplayConfigState.include.compositorSupported)
            return true;
        return DisplayConfigState.includeStatus.included;
    }

    Loader {
        active: root.visible && root.identifyConfigured && monitorCanvas.identifyActive
        sourceComponent: MonitorIdentifyOverlay {}
    }
}
