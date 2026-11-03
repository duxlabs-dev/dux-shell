pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var groupCollapsedStates: ({})
    property var parentModal: null
    property string newGroupName: ""
    property string renamingGroupId: ""

    readonly property var allInstances: SettingsData.desktopWidgetInstances || []
    readonly property var allGroups: SettingsData.desktopWidgetGroups || []

    readonly property bool dragActive: dragGroup.active
    property alias reorderGroup: dragGroup

    SettingsReorderGroup {
        id: dragGroup

        coordinateItem: root
        onTransferred: (source, sourceIndex, target, targetIndex) => SettingsData.moveDesktopWidgetInstanceToGroup(source.model[sourceIndex].id, target.groupKey || null, targetIndex)
    }

    function storageKeyFor(sectionKey) {
        return sectionKey === "" ? "_ungrouped" : sectionKey;
    }

    function toggleCollapsed(sectionKey) {
        const key = storageKeyFor(sectionKey);
        var states = Object.assign({}, groupCollapsedStates);
        states[key] = !(states[key] ?? false);
        groupCollapsedStates = states;
    }

    function configureWidget(instanceId, title) {
        SettingsUiState.selectedDesktopWidgetId = instanceId;
        SettingsUiState.selectedWidgetTitle = title;
        parentModal?.navigateTo("desktop_widget");
    }

    function openRenameDialog(group) {
        renamingGroupId = group.id;
        renameDialog.show(group.name);
    }

    function saveGroupName(name) {
        SettingsData.updateDesktopWidgetGroup(renamingGroupId, {
            name: name
        });
        renameDialog.hide();
    }

    function showWidgetBrowser() {
        widgetBrowserLoader.active = true;
        if (widgetBrowserLoader.item)
            widgetBrowserLoader.item.show();
    }

    function showDesktopPluginBrowser() {
        desktopPluginBrowserLoader.active = true;
        if (desktopPluginBrowserLoader.item)
            desktopPluginBrowserLoader.item.show();
    }

    LazyLoader {
        id: widgetBrowserLoader
        active: false

        DesktopWidgetBrowser {
            parentModal: root.parentModal
            onWidgetAdded: widgetType => {
                ToastService.showInfo(I18n.tr("Widget added"));
            }
        }
    }

    LazyLoader {
        id: desktopPluginBrowserLoader
        active: false

        PluginBrowser {
            parentModal: root.parentModal
            typeFilters: ["desktop-widget"]
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            settingKey: "desktopGeneral"
            tags: ["desktop", "context", "menu", "right click", "wallpaper"]
            width: parent.width
            iconName: "mouse"
            title: I18n.tr("General")

            SettingsDropdownRow {
                settingKey: "desktopContextMenu"
                text: I18n.tr("Right-click menu")
                description: I18n.tr("Auto turns it off on compositors that use clicks on the empty desktop themselves", "desktop context menu dropdown description")
                options: [I18n.tr("Auto"), I18n.tr("On"), I18n.tr("Off")]
                readonly property var values: ["auto", "on", "off"]
                currentValue: options[Math.max(0, values.indexOf(SettingsData.desktopContextMenu))]
                onValueChanged: value => SettingsData.set("desktopContextMenu", values[options.indexOf(value)])
            }
        }

        SettingsCard {
            settingKey: "desktopWidgetGroups"
            tags: ["groups", "profiles", "layouts"]
            width: parent.width
            iconName: "folder"
            title: I18n.tr("Groups", "noun, card title for desktop widget groups")
            collapsible: true
            expanded: root.allGroups.length > 0

            SettingsRow {
                body: Row {
                    spacing: Theme.spacingS
                    width: parent.width

                    DTextField {
                        id: newGroupField
                        outlined: true
                        leftIconName: "folder"
                        labelText: I18n.tr("Name")
                        width: parent.width - addGroupBtn.width - Theme.spacingS
                        text: root.newGroupName
                        onTextChanged: root.newGroupName = text
                        onAccepted: {
                            if (!text.trim())
                                return;
                            SettingsData.createDesktopWidgetGroup(text.trim());
                            root.newGroupName = "";
                            text = "";
                        }
                    }

                    DButton {
                        id: addGroupBtn
                        iconName: "add"
                        text: I18n.tr("Add")
                        enabled: root.newGroupName.trim().length > 0
                        onClicked: {
                            SettingsData.createDesktopWidgetGroup(root.newGroupName.trim());
                            root.newGroupName = "";
                            newGroupField.text = "";
                        }
                    }
                }
            }

            Repeater {
                model: root.allGroups

                delegate: SettingsRow {
                    id: groupRow

                    required property var modelData

                    iconName: "folder"
                    title: modelData.name
                    singleLineTitle: true

                    DActionButton {
                        iconName: "edit"
                        tooltipText: I18n.tr("Rename")
                        onClicked: root.openRenameDialog(groupRow.modelData)
                    }

                    DActionButton {
                        iconName: "delete"
                        iconColor: Theme.error
                        tooltipText: I18n.tr("Delete")
                        onClicked: {
                            SettingsData.removeDesktopWidgetGroup(groupRow.modelData.id);
                            ToastService.showInfo(I18n.tr("Group removed"));
                        }
                    }
                }
            }
        }

        Repeater {
            id: groupsRepeater
            model: root.allGroups

            DesktopWidgetGroupSection {
                required property var modelData
                required property int index

                width: mainColumn.columnWidth
                reorderGroup: dragGroup
                groupId: modelData.id
                groupName: modelData.name
                isUngrouped: false
                showHeader: true
                collapsed: root.groupCollapsedStates[modelData.id] ?? false
                instances: root.allInstances.filter(inst => inst.group === modelData.id)
                visible: instances.length > 0 || root.dragActive

                onCollapseToggled: key => root.toggleCollapsed(key)
                onConfigureRequested: (instanceId, title) => root.configureWidget(instanceId, title)
                onDuplicateRequested: instanceId => SettingsData.duplicateDesktopWidgetInstance(instanceId)
                onDeleteRequested: instanceId => {
                    SettingsData.removeDesktopWidgetInstance(instanceId);
                    ToastService.showInfo(I18n.tr("Widget removed"));
                }
            }
        }

        DesktopWidgetGroupSection {
            id: ungroupedSection

            readonly property var ungroupedInstances: root.allInstances.filter(inst => {
                if (!inst.group)
                    return true;
                return !root.allGroups.some(g => g.id === inst.group);
            })

            width: mainColumn.columnWidth
            reorderGroup: dragGroup
            groupId: null
            groupName: I18n.tr("Ungrouped", "section header for desktop widgets without a group")
            isUngrouped: true
            showHeader: root.allGroups.length > 0
            collapsed: root.groupCollapsedStates["_ungrouped"] ?? false
            instances: ungroupedInstances
            visible: ungroupedInstances.length > 0 || root.dragActive

            onCollapseToggled: key => root.toggleCollapsed(key)
            onConfigureRequested: (instanceId, title) => root.configureWidget(instanceId, title)
            onDuplicateRequested: instanceId => SettingsData.duplicateDesktopWidgetInstance(instanceId)
            onDeleteRequested: instanceId => {
                SettingsData.removeDesktopWidgetInstance(instanceId);
                ToastService.showInfo(I18n.tr("Widget removed"));
            }
        }

        StyledText {
            visible: root.allInstances.length === 0
            text: I18n.tr("No widgets added. Click \"Add widget\" to get started.")
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignLeft
        }

        SettingsCard {
            width: parent.width
            iconName: "info"
            title: I18n.tr("Help", "noun, card title for desktop widget usage tips")

            SettingsRow {
                iconName: "drag_indicator"
                iconBox: true
                title: I18n.tr("Reorder & group")
                subtitle: I18n.tr("Drag a widget by its handle here to reorder it or drop it into another group")
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Browse plugins")
                iconName: "store"
                colorRole: "secondaryContainer"
                onClicked: root.showDesktopPluginBrowser()
            }

            DFab {
                text: I18n.tr("Edit widgets")
                iconName: "edit"
                colorRole: "secondaryContainer"
                onClicked: DesktopWidgetRegistry.editing = true
            }

            DFab {
                text: I18n.tr("Add widget")
                iconName: "add"
                onClicked: root.showWidgetBrowser()
            }
        }
    }

    SettingsReorderPreview {
        group: dragGroup
    }

    SettingsRenameDialog {
        id: renameDialog
        parent: root.parentModal?.modalFocusScope ?? root
        supportingText: root.allGroups.find(g => g.id === root.renamingGroupId)?.name ?? ""
        leftIconName: "folder"
        onAccepted: name => root.saveGroupName(name)
    }
}
