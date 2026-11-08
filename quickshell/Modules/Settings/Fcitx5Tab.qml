import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import "../../Common/fcitx5Schema.js" as Fcitx5Schema

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    property var parentModal: null

    readonly property string globalUri: "fcitx://config/global"
    readonly property bool editable: Fcitx5Service.editable
    readonly property var addonIcons: ({
            "0": "language",
            "3": "extension",
            "4": "web_asset"
        })
    property var groupNames: []
    property string activeGroup: ""
    property string selectedGroup: ""
    property string renameTarget: ""
    property var group: null
    property var catalog: ({})
    property var layoutChoices: null
    property var globalSchema: null
    property var globalValue: ({})

    readonly property var items: group?.items ?? []
    readonly property bool needsLayouts: items.some(item => !Fcitx5Schema.isKeyboardIM(item.name))

    readonly property var hotkeyRows: globalSchema ? Fcitx5Schema.curatedRows(globalSchema, "Hotkey", [
        {
            "name": "TriggerKeys",
            "label": I18n.tr("Toggle input method", "Configurable keybind in the fcitx5 settings."),
            "description": I18n.tr("Switch between the first input method and the active one", "Description for a configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "EnumerateForwardKeys",
            "label": I18n.tr("Next input method", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "EnumerateBackwardKeys",
            "label": I18n.tr("Previous input method", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "EnumerateGroupForwardKeys",
            "label": I18n.tr("Next group", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "EnumerateGroupBackwardKeys",
            "label": I18n.tr("Previous group", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "ActivateKeys",
            "label": I18n.tr("Activate input method", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "DeactivateKeys",
            "label": I18n.tr("Deactivate input method", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "PrevPage",
            "label": I18n.tr("Previous page", "Configurable keybind in the fcitx5 settings."),
            "description": I18n.tr("Candidate list", "Description for a configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "NextPage",
            "label": I18n.tr("Next page", "Configurable keybind in the fcitx5 settings."),
            "description": I18n.tr("Candidate list", "Description for a configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "PrevCandidate",
            "label": I18n.tr("Previous candidate", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "NextCandidate",
            "label": I18n.tr("Next candidate", "Configurable keybind in the fcitx5 settings.")
        },
        {
            "name": "TogglePreedit",
            "label": I18n.tr("Toggle preedit in application", "Configurable keybind in the fcitx5 settings.")
        }
    ]) : []

    readonly property var behaviorRows: globalSchema ? Fcitx5Schema.curatedRows(globalSchema, "Behavior", [
        {
            "name": "ActiveByDefault",
            "label": I18n.tr("Active by default", "Option on the fcitx5 config page."),
            "description": I18n.tr("Start with the input method on instead of the plain keyboard", "Option on the fcitx5 config page.")
        },
        {
            "name": "ShareInputState",
            "label": I18n.tr("Share input state", "Option on the fcitx5 config page.")
        },
        {
            "name": "PreeditEnabledByDefault",
            "label": I18n.tr("Show preedit in application", "Option on the fcitx5 config page."),
            "description": I18n.tr("Show the text being composed inside the app instead of the candidate window", "Description for an option on the fcitx5 config page.")
        },
        {
            "name": "ShowInputMethodInformation",
            "label": I18n.tr("Show input method info on switch", "Option on the fcitx5 config page."),
            "description": I18n.tr("The fcitx5 popup. The shell's OSD toggle is in the OSD settings.", "Description for an option on the fcitx5 config page.")
        },
        {
            "name": "DefaultPageSize",
            "label": I18n.tr("Candidates per page", "Option on the fcitx5 config page.")
        }
    ]) : []

    function pickerItems() {
        const used = new Set(items.map(item => item.name));
        const list = Object.values(catalog).filter(im => !used.has(im.uniqueName));
        list.sort((a, b) => {
            const ka = Fcitx5Schema.isKeyboardIM(a.uniqueName);
            const kb = Fcitx5Schema.isKeyboardIM(b.uniqueName);
            return ka !== kb ? (ka ? 1 : -1) : a.name.localeCompare(b.name);
        });
        return list.map(im => ({
                    "id": im.uniqueName,
                    "text": im.name,
                    "description": im.nativeName,
                    "icon": Fcitx5Schema.isKeyboardIM(im.uniqueName) ? "keyboard" : "language"
                }));
    }

    function showPicker() {
        pickerLoader.active = true;
        if (!pickerLoader.item)
            return;
        pickerLoader.item.widgets = pickerItems();
        pickerLoader.item.show();
    }

    function imName(unique) {
        return catalog[unique]?.name ?? unique;
    }

    function load() {
        if (!editable)
            return;
        loadGroups();
        loadGlobal();
        loadAddons();
        Fcitx5Service.request("availableIMs", null, (result, error) => {
            if (error)
                return;
            const map = {};
            for (const im of result.inputMethods)
                map[im.uniqueName] = im;
            root.catalog = map;
        });
    }

    function loadGroups() {
        Fcitx5Service.request("getGroups", null, (result, error) => {
            if (error)
                return;
            root.groupNames = result.groups;
            root.activeGroup = result.current;
            if (!result.groups.includes(root.selectedGroup))
                root.selectedGroup = result.current;
            root.loadGroup(root.selectedGroup);
        });
    }

    function loadGroup(name) {
        Fcitx5Service.request("getGroup", {
            "name": name
        }, (result, error) => {
            if (!error)
                root.group = result;
        });
    }

    function loadGlobal() {
        Fcitx5Service.getConfig(globalUri, result => {
            if (!root.globalSchema)
                root.globalSchema = result.schema;
            root.globalValue = result.value;
        });
    }

    function loadAddons() {
        Fcitx5Service.request("getAddons", null, (result, error) => {
            if (error)
                return;
            if (addonModel.count > 0) {
                for (let i = 0; i < addonModel.count; i++) {
                    const fresh = result.addons.find(addon => addon.uniqueName === addonModel.get(i).uniqueName);
                    if (fresh)
                        addonModel.setProperty(i, "addonEnabled", fresh.enabled);
                }
                return;
            }
            const shown = result.addons.filter(addon => root.addonIcons[addon.category] !== undefined);
            shown.sort((a, b) => a.category !== b.category ? a.category - b.category : a.name.localeCompare(b.name));
            shown.forEach(addon => addonModel.append(Object.assign({}, addon, {
                    "addonEnabled": addon.enabled
                })));
        });
    }

    function setAddonEnabled(index, enabled) {
        addonModel.setProperty(index, "addonEnabled", enabled);
        Fcitx5Service.request("setAddonEnabled", {
            "name": addonModel.get(index).uniqueName,
            "enabled": enabled
        }, () => root.loadAddons());
    }

    function loadLayouts() {
        if (layoutChoices !== null)
            return;
        layoutChoices = {
            "values": [],
            "labels": []
        };
        Fcitx5Service.request("availableLayouts", null, (result, error) => {
            if (!error)
                root.layoutChoices = Fcitx5Schema.layoutOptions(result.layouts, I18n.tr("Default"));
        });
    }

    function saveItems(newItems) {
        group = Object.assign({}, group, {
            "items": newItems
        });
        Fcitx5Service.request("setGroup", {
            "name": group.name,
            "defaultLayout": group.defaultLayout,
            "items": newItems
        }, (result, error) => {
            root.loadGroup(root.selectedGroup);
        });
    }

    // Local state first, so a second edit before the reload builds on the first.
    function saveGlobal(path, value) {
        globalValue = Fcitx5Schema.setPath(globalValue, path, value);
        Fcitx5Service.setConfig(globalUri, globalValue, loadGlobal);
    }

    function addGroup() {
        let n = groupNames.length + 1;
        while (groupNames.includes("Group " + n))
            n++;
        groupRequest("addGroup", "Group " + n);
    }

    function renameGroup(old, target) {
        renameDialog.hide();
        if (target === old)
            return;
        Fcitx5Service.request("renameGroup", {
            "name": old,
            "newName": target
        }, (result, error) => {
            if (!error && root.selectedGroup === old)
                root.selectedGroup = target;
            root.loadGroups();
        });
    }

    function groupRequest(method, name) {
        Fcitx5Service.request(method, {
            "name": name
        }, (result, error) => {
            root.loadGroups();
        });
    }

    onEditableChanged: load()
    onNeedsLayoutsChanged: {
        if (needsLayouts)
            loadLayouts();
    }

    ListModel {
        id: addonModel
    }

    LazyLoader {
        id: pickerLoader

        active: false

        WidgetPickerWindow {
            id: picker

            objectName: "fcitx5ImPicker"
            parentModal: root.parentModal
            title: I18n.tr("Add input method", "Title for fcitx5 IM picker window")
            searchPlaceholder: I18n.tr("Search")
            onWidgetChosen: widget => {
                root.saveItems(root.items.concat({
                    "name": widget.id,
                    "layout": ""
                }));
                picker.hide();
            }
            onVisibleChanged: {
                if (!visible)
                    widgets = [];
            }
        }
    }

    SettingsRenameDialog {
        id: renameDialog

        parent: root.parentModal?.modalFocusScope ?? root
        title: I18n.tr("Rename")
        onAccepted: name => root.renameGroup(root.renameTarget, name)
    }

    SettingsPage {
        SettingsNoteRow {
            visible: !root.editable
            text: I18n.tr("Update DMS to configure fcitx5 from here", "Tip displayed when dms core is too old for fcitx5")
        }

        SettingsCard {
            width: parent.width
            visible: root.editable
            tags: ["fcitx5", "input method", "group"]
            title: I18n.tr("Groups")
            settingKey: "fcitx5Groups"
            iconName: "folder"

            headerActions: DButton {
                text: I18n.tr("Add")
                iconName: "add"
                buttonHeight: Theme.buttonHeightXS
                onClicked: root.addGroup()
            }

            Repeater {
                model: root.groupNames

                delegate: SettingsInstanceRow {
                    required property string modelData

                    title: modelData
                    summary: root.activeGroup === modelData ? I18n.tr("Active") : ""
                    selected: root.selectedGroup === modelData
                    toggleVisible: false
                    deletable: root.groupNames.length > 1
                    onClicked: {
                        root.selectedGroup = modelData;
                        root.loadGroup(modelData);
                    }
                    onDeleteRequested: root.groupRequest("removeGroup", modelData)

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "edit"
                        tooltipText: I18n.tr("Rename")
                        onClicked: {
                            root.renameTarget = modelData;
                            renameDialog.show(modelData);
                        }
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: root.editable
            tags: ["fcitx5", "input method", "ime", "layout", "language"]
            title: root.selectedGroup
            settingKey: "fcitx5InputMethods"
            iconName: "language"

            headerActions: DButton {
                text: I18n.tr("Add")
                iconName: "add"
                buttonHeight: Theme.buttonHeightXS
                onClicked: root.showPicker()
            }

            SettingsReorderList {
                id: imList

                model: root.items
                onReordered: indices => root.saveItems(Fcitx5Schema.applyOrder(root.items, indices))

                delegate: SettingsReorderRow {
                    id: imRow

                    required property var modelData
                    readonly property bool hasLayout: !Fcitx5Schema.isKeyboardIM(modelData.name) && (root.layoutChoices?.values.length ?? 0) > 0

                    reorderList: imList
                    title: root.imName(modelData.name)
                    subtitle: root.catalog[modelData.name]?.nativeName ?? ""

                    DDropdown {
                        // DDropdown assigns currentValue on selection, which would drop a binding on it.
                        readonly property string syncedValue: Fcitx5Schema.layoutKey(imRow.modelData.layout)

                        onSyncedValueChanged: currentValue = syncedValue
                        anchors.verticalCenter: parent.verticalCenter
                        visible: imRow.hasLayout
                        backgroundColor: SettingsMetrics.controlSurface
                        enableFuzzySearch: true
                        options: root.layoutChoices?.labels ?? []
                        optionValues: root.layoutChoices?.values ?? []
                        Accessible.name: I18n.tr("Keyboard layout")
                        onValueChanged: value => root.saveItems(root.items.map((item, i) => i === imRow.index ? {
                                    "name": item.name,
                                    "layout": Fcitx5Schema.layoutFromKey(value)
                                } : item))
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"
                        iconColor: Theme.error
                        enabled: root.items.length > 1
                        tooltipText: I18n.tr("Remove")
                        onClicked: root.saveItems(root.items.filter((_, i) => i !== imRow.index))
                    }
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: root.editable && root.behaviorRows.length > 0
            tags: ["fcitx5", "input method", "behavior", "preedit", "share", "state"]
            title: I18n.tr("Behavior")
            settingKey: "fcitx5Behavior"
            iconName: "tune"
            collapsible: true

            Repeater {
                model: root.behaviorRows

                delegate: Fcitx5Row {
                    required property var modelData

                    row: modelData
                    value: Fcitx5Schema.getPath(root.globalValue, modelData.path)
                    onValueEdited: (path, value) => root.saveGlobal(path, value)
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: root.editable && root.hotkeyRows.length > 0
            tags: ["fcitx5", "input method", "hotkey", "shortcut", "toggle", "switch"]
            title: I18n.tr("Keyboard shortcuts")
            settingKey: "fcitx5Hotkeys"
            iconName: "keyboard_command_key"
            collapsible: true
            expanded: false

            Repeater {
                model: root.hotkeyRows

                delegate: Fcitx5Row {
                    required property var modelData

                    row: modelData
                    value: Fcitx5Schema.getPath(root.globalValue, modelData.path)
                    onValueEdited: (path, value) => root.saveGlobal(path, value)
                }
            }
        }

        SettingsCard {
            width: parent.width
            visible: root.editable && addonModel.count > 0
            tags: ["fcitx5", "input method", "plugin", "addon", "module"]
            title: I18n.tr("Plugins")
            settingKey: "fcitx5Plugins"
            iconName: "extension"
            collapsible: true

            Repeater {
                model: addonModel

                delegate: SettingsSplitRow {
                    required property int index
                    required property string uniqueName
                    required property string name
                    required property string comment
                    required property int category
                    required property bool configurable
                    required property bool addonEnabled

                    iconName: root.addonIcons[category]
                    iconColor: checked ? Theme.primary : Theme.onSurfaceVariant
                    title: name
                    subtitle: comment
                    navigable: configurable
                    clickable: true
                    checked: addonEnabled
                    onNavigated: keyboard => {
                        if (!configurable) {
                            root.setAddonEnabled(index, !checked);
                            return;
                        }
                        SettingsUiState.selectedFcitx5Addon = uniqueName;
                        SettingsUiState.selectedFcitx5AddonTitle = name;
                        root.parentModal?.navigateTo("fcitx5_addon", keyboard);
                    }
                    onToggled: value => root.setAddonEnabled(index, value)
                }
            }
        }
    }
}
