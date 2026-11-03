pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var parentModal: null
    property string editingBarId: ""
    property string renameDraft: ""
    readonly property bool dotEnabled: SettingsData.dotBarConfig?.enabled ?? false
    readonly property var barPages: ["dankbar_settings", "dankbar_appearance"].map(id => SettingsTabs.page(id)).filter(page => page)

    BarSelectionState {
        id: bar

        onSelectedBarIdChanged: root.editingBarId = ""
    }

    function finishRename(value) {
        const id = editingBarId;
        editingBarId = "";
        const name = value.trim();
        if (!id || !name || SettingsData.barConfigs.some(config => config.id !== id && config.name === name))
            return;
        SettingsData.updateBarConfig(id, {
            name: name
        });
    }

    // A new bar shows up right away on every display, on an edge nothing else holds when there is one.
    function createNewBar() {
        if (SettingsData.edgeBarConfigCount >= 4)
            return;
        const defaultBar = SettingsData.getBarConfig("default");
        if (!defaultBar)
            return;
        const newId = "bar" + Date.now();
        const freeEdge = SettingsData.firstFreeEdge(newId, ["all"], [SettingsData.Position.Top, SettingsData.Position.Bottom, SettingsData.Position.Left, SettingsData.Position.Right]);
        const newBar = Object.assign(JSON.parse(JSON.stringify(defaultBar)), {
            id: newId,
            name: "Bar " + (SettingsData.edgeBarConfigCount + 1),
            enabled: true,
            position: freeEdge >= 0 ? freeEdge : (defaultBar.position ?? 0),
            screenPreferences: ["all"],
            showOnLastDisplay: true,
            hideOnLastDisplay: false
        });
        delete newBar.island;
        delete newBar.dot;
        SettingsData.stripIslandWidget(newBar);
        SettingsData.addBarConfig(newBar);
        bar.select(newId);
    }

    function canDeleteBar(config) {
        return config.id !== "default" && SettingsData.edgeBarConfigCount > 1;
    }

    function deleteBar(barId) {
        SettingsData.deleteBarConfig(barId);
        bar.select("default");
    }

    function setBarEnabled(barId, enabled) {
        SettingsData.updateBarConfig(barId, {
            enabled
        });
    }

    function barTitle(config) {
        return config.name || I18n.tr("Bar %1", "numbered name for an unnamed bar, %1 is its position").arg(SettingsData.barConfigs.findIndex(candidate => candidate.id === config.id) + 1);
    }

    function barSummary(config) {
        const parts = SettingsData.islandFreePlacement(config) ? [I18n.tr("Floating", "bar summary: island can be dragged anywhere on the display")] : [bar.positionLabel(config.position ?? SettingsData.Position.Top)];
        const prefs = config.screenPreferences || ["all"];
        if (prefs.includes("all"))
            parts.push(I18n.tr("All displays"));
        else
            parts.push(prefs.length === 1 ? I18n.tr("%1 display", "singular, bar summary of assigned monitors, %1 is 1").arg(prefs.length) : I18n.tr("%1 displays", "plural, bar summary of assigned monitors, %1 is a count").arg(prefs.length));
        if (SettingsData.hostsIsland(config))
            parts.push(I18n.tr("Island"));
        return parts.join(" • ");
    }

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        iconName: "dashboard"
        title: I18n.tr("Bars", "plural noun, the shell bars or panels, settings title")
        settingKey: "barConfigurations"
        tags: ["bar", "configuration", "add", "remove", "enable", "multiple", "name"]
        headerActions: DButton {
            text: I18n.tr("Add")
            iconName: "add"
            buttonHeight: Theme.buttonHeightXS
            visible: SettingsData.edgeBarConfigCount < 4
            onClicked: root.createNewBar()
        }

        Repeater {
            model: SettingsData.barConfigs.filter(config => !SettingsData.isDotBarConfig(config))

            delegate: SettingsInstanceRow {
                required property var modelData

                title: root.barTitle(modelData)
                summary: root.barSummary(modelData)
                selected: bar.selectedBarId === modelData.id
                checked: modelData.enabled ?? false
                deletable: root.canDeleteBar(modelData)
                onClicked: bar.select(modelData.id)
                onToggled: checked => {
                    bar.select(modelData.id);
                    root.setBarEnabled(modelData.id, checked);
                }
                onDeleteRequested: root.deleteBar(modelData.id)
            }
        }

        SettingsNavRow {
            iconName: "keyboard_command_key"
            title: I18n.tr("Keyboard shortcuts")
            hint: I18n.tr("With no bar, Dot or dock launcher on, shortcuts are the only way back to settings", "bars card hint shown when every bar, the Dot and every dock launcher button are off")
            visible: !root.dotEnabled && !SettingsData.barConfigs.some(config => config.enabled && !SettingsData.isDotBarConfig(config)) && !SettingsData.dockConfigs.some(dock => dock.enabled && dock.launcherEnabled)
            onClicked: keyboard => root.parentModal?.navigateTo("keybinds", keyboard)
        }
    }

    SettingsCard {
        iconName: bar.selectedBarIsIsland ? "view_in_ar" : "toolbar"
        title: bar.selectedBarName
        settingKey: "barLayout"
        tags: ["layout", "standard", "frame", "island", "mode", "bar", "name", "rename"]
        visible: !!bar.selectedBarConfig

        SettingsRow {
            title: I18n.tr("Name")
            subtitle: root.editingBarId ? "" : bar.selectedBarName

            DActionButton {
                iconName: root.editingBarId ? "check" : "edit"
                Accessible.name: root.editingBarId ? I18n.tr("Save") : I18n.tr("Rename")
                onClicked: {
                    if (root.editingBarId) {
                        root.finishRename(root.renameDraft);
                        return;
                    }
                    root.renameDraft = bar.selectedBarName;
                    root.editingBarId = bar.selectedBarId;
                }
            }
            DActionButton {
                visible: root.editingBarId !== ""
                iconName: "close"
                Accessible.name: I18n.tr("Cancel")
                onClicked: root.editingBarId = ""
            }

            body: Loader {
                width: parent.width
                active: root.editingBarId !== ""
                visible: active
                sourceComponent: DTextField {
                    id: renameField
                    width: parent.width
                    outlined: true
                    labelText: I18n.tr("Name")
                    text: root.renameDraft
                    onTextEdited: root.renameDraft = renameField.text
                    onAccepted: root.finishRename(renameField.text)
                    Keys.onEscapePressed: root.editingBarId = ""
                    Component.onCompleted: {
                        renameField.forceActiveFocus();
                        renameField.selectAll();
                    }
                }
            }
        }

        SettingsRow {
            title: I18n.tr("Layout", "noun, settings section title for arrangement options")

            body: SettingsLayoutPicker {}
        }

        Repeater {
            model: root.barPages

            delegate: SettingsNavRow {
                required property var modelData

                iconName: modelData.icon
                title: modelData.text
                hint: modelData.hint ?? ""
                onClicked: keyboard => root.parentModal?.navigateTo(modelData.id, keyboard)
            }
        }
    }

    SettingsSplitRow {
        settingKey: "dotEnabled"
        tags: ["dot", "dankdot", "companion", "floating", "island", "enable"]
        iconName: "blur_on"
        iconColor: root.dotEnabled ? Theme.primary : Theme.onSurfaceVariant
        title: I18n.tr("Dot", "bar layout: free-floating dot that opens island activities")
        subtitle: I18n.tr("A floating companion that works alongside any bar layout", "bar settings: what the dot is")
        navigable: root.dotEnabled
        checked: root.dotEnabled
        onNavigated: keyboard => root.parentModal?.navigateTo("dankbar_dot", keyboard)
        onToggled: value => SettingsData.setDotEnabled(value, bar.selectedBarId)
    }
}
