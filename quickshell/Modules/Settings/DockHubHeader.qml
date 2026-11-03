pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null
    property string editingDockId: ""
    property string renameDraft: ""
    readonly property var dockPages: ["dock_general", "dock_widgets", "dock_appearance"].map(id => SettingsTabs.page(id)).filter(page => page)

    function finishRename(value) {
        const id = editingDockId;
        editingDockId = "";
        const name = value.trim();
        if (!id || !name || SettingsData.dockConfigs.some(config => config.id !== id && config.name === name))
            return;
        SettingsData.updateDockConfig(id, {
            name: name
        });
    }

    function addDock() {
        dock.selectedDockId = SettingsData.createDockConfig();
        if (!dock.config?.enabled)
            ToastService.showWarning(I18n.tr("Every edge of this display is already taken"));
    }

    function removeDock(id) {
        SettingsData.removeDockConfig(id);
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    DockSelectionState {
        id: dock

        onSelectedDockIdChanged: root.editingDockId = ""
    }

    SettingsCard {
        iconName: "dock_to_bottom"
        title: I18n.tr("Docks", "noun plural, settings card title listing configured docks")
        settingKey: "dockConfiguration"
        tags: ["dock", "configuration", "add", "remove", "show", "enable"]
        headerActions: DButton {
            text: I18n.tr("Add", "verb, button that adds a new item to a list")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            onClicked: root.addDock()
        }

        Repeater {
            model: SettingsData.dockConfigs

            delegate: SettingsInstanceRow {
                required property var modelData

                title: modelData.name
                summary: dock.summaryFor(modelData)
                selected: dock.selectedDockId === modelData.id
                checked: modelData.enabled
                deletable: SettingsData.dockConfigs.length > 1
                onClicked: dock.selectedDockId = modelData.id
                onToggled: checked => {
                    dock.selectedDockId = modelData.id;
                    dock.setEnabled(checked);
                }
                onDeleteRequested: root.removeDock(modelData.id)
            }
        }
    }

    SettingsCard {
        iconName: "dock_to_bottom"
        title: dock.config?.name ?? ""
        settingKey: "dockPlacement"
        tags: ["dock", "layout", "placement", "position", "edge", "name", "rename"]
        visible: dock.hasConfig

        SettingsRow {
            title: I18n.tr("Name")
            subtitle: root.editingDockId ? "" : dock.config?.name ?? ""

            DActionButton {
                iconName: root.editingDockId ? "check" : "edit"
                Accessible.name: root.editingDockId ? I18n.tr("Save") : I18n.tr("Rename")
                onClicked: {
                    if (root.editingDockId) {
                        root.finishRename(root.renameDraft);
                        return;
                    }
                    root.renameDraft = dock.config.name;
                    root.editingDockId = dock.selectedDockId;
                }
            }
            DActionButton {
                visible: root.editingDockId !== ""
                iconName: "close"
                Accessible.name: I18n.tr("Cancel")
                onClicked: root.editingDockId = ""
            }

            body: Loader {
                width: parent.width
                active: root.editingDockId !== ""
                visible: active
                sourceComponent: DTextField {
                    id: renameField
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Name")
                    text: root.renameDraft
                    onTextEdited: root.renameDraft = renameField.text
                    onAccepted: root.finishRename(renameField.text)
                    Keys.onEscapePressed: root.editingDockId = ""
                    Component.onCompleted: {
                        renameField.forceActiveFocus();
                        renameField.selectAll();
                    }
                }
            }
        }

        SettingsRow {
            title: I18n.tr("Layout", "noun, settings section title for arrangement options")

            body: SettingsLayoutPicker {
                edgePlacement: true
                choices: [SettingsData.Position.Top, SettingsData.Position.Bottom, SettingsData.Position.Left, SettingsData.Position.Right].map(position => ({
                            key: String(position),
                            label: dock.positionLabel(position),
                            enabled: dock.positionChoices.includes(position)
                        }))
                selectedKey: String(dock.config?.position ?? SettingsData.Position.Bottom)
                onSelected: key => dock.setEnabled(true, Number(key))
            }
        }

        Repeater {
            model: root.dockPages

            delegate: SettingsNavRow {
                required property var modelData

                iconName: modelData.icon
                title: modelData.text
                hint: modelData.hint ?? ""
                onClicked: keyboard => root.parentModal?.navigateTo(modelData.id, keyboard)
            }
        }
    }
}
