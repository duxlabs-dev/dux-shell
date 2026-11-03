import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var config: ({})
    property bool configLoaded: false
    property bool configError: false
    property bool saving: false
    readonly property bool historyEnabled: !(config.disabled ?? false)

    readonly property var maxHistoryOptions: [
        {
            text: "25",
            value: 25
        },
        {
            text: "50",
            value: 50
        },
        {
            text: "100",
            value: 100
        },
        {
            text: "200",
            value: 200
        },
        {
            text: "500",
            value: 500
        },
        {
            text: "1,000",
            value: 1000
        },
        {
            text: "10,000",
            value: 10000
        },
        {
            text: "15,000",
            value: 15000
        },
        {
            text: "20,000",
            value: 20000
        },
        {
            text: "30,000",
            value: 30000
        },
        {
            text: "50,000",
            value: 50000
        },
        {
            text: "100,000",
            value: 100000
        },
        {
            text: "∞",
            value: -1
        }
    ]

    readonly property var maxEntrySizeOptions: [
        {
            text: "1 MB",
            value: 1048576
        },
        {
            text: "2 MB",
            value: 2097152
        },
        {
            text: "5 MB",
            value: 5242880
        },
        {
            text: "10 MB",
            value: 10485760
        },
        {
            text: "20 MB",
            value: 20971520
        },
        {
            text: "50 MB",
            value: 52428800
        }
    ]

    readonly property var autoClearOptions: [
        {
            text: I18n.tr("Never"),
            value: 0
        },
        {
            text: I18n.duration(1 * 86400),
            value: 1
        },
        {
            text: I18n.duration(3 * 86400),
            value: 3
        },
        {
            text: I18n.duration(7 * 86400),
            value: 7
        },
        {
            text: I18n.duration(14 * 86400),
            value: 14
        },
        {
            text: I18n.duration(30 * 86400),
            value: 30
        },
        {
            text: I18n.duration(90 * 86400),
            value: 90
        }
    ]

    readonly property var maxPinnedOptions: [
        {
            text: "5",
            value: 5
        },
        {
            text: "10",
            value: 10
        },
        {
            text: "15",
            value: 15
        },
        {
            text: "25",
            value: 25
        },
        {
            text: "50",
            value: 50
        },
        {
            text: "100",
            value: 100
        }
    ]

    readonly property var entryActionKeys: ["copy", "paste", "pin", "edit", "delete"]
    readonly property var entryActionLabels: [I18n.tr("Copy"), I18n.tr("Paste"), I18n.tr("Pin", "pin item action"), I18n.tr("Edit"), I18n.tr("Delete")]

    function getMaxHistoryText(value) {
        if (value <= 0)
            return "∞";
        for (let opt of maxHistoryOptions) {
            if (opt.value === value)
                return opt.text;
        }
        return value.toLocaleString();
    }

    function getMaxEntrySizeText(value) {
        for (let opt of maxEntrySizeOptions) {
            if (opt.value === value)
                return opt.text;
        }
        const mb = Math.round(value / 1048576);
        return mb + " MB";
    }

    function getAutoClearText(value) {
        for (let opt of autoClearOptions) {
            if (opt.value === value)
                return opt.text;
        }
        return I18n.duration(value * 86400);
    }

    function getMaxPinnedText(value) {
        for (let opt of maxPinnedOptions) {
            if (opt.value === value)
                return opt.text;
        }
        return value.toString();
    }

    function visibleEntryActionKeys() {
        return SettingsData.clipboardVisibleEntryActions || ["pin", "edit", "delete"];
    }

    function visibleEntryActionLabels() {
        const visibleKeys = visibleEntryActionKeys();
        return entryActionKeys.map((key, index) => visibleKeys.includes(key) ? entryActionLabels[index] : null).filter(label => label !== null);
    }

    function setVisibleEntryAction(index, selected) {
        const actionKey = entryActionKeys[index];
        if (!actionKey)
            return;

        let actions = visibleEntryActionKeys().slice();
        if (selected && !actions.includes(actionKey)) {
            actions.push(actionKey);
        } else if (!selected && actions.includes(actionKey)) {
            actions = actions.filter(action => action !== actionKey);
        }
        SettingsData.set("clipboardVisibleEntryActions", actions);
    }

    function loadConfig() {
        configLoaded = false;
        configError = false;
        DMSService.sendRequest("clipboard.getConfig", null, response => {
            if (response.error) {
                configError = true;
                return;
            }
            config = response.result || {};
            configLoaded = true;
        });
    }

    function saveConfig(key, value) {
        const params = {};
        params[key] = value;
        saving = true;
        DMSService.sendRequest("clipboard.setConfig", params, response => {
            saving = false;
            if (response.error) {
                ToastService.showError(I18n.tr("Failed to save clipboard setting"), response.error);
                return;
            }
            const updated = JSON.parse(JSON.stringify(config));
            updated[key] = value;
            config = updated;
        });
    }

    Component.onCompleted: {
        if (DMSService.isConnected)
            loadConfig();
    }

    Connections {
        target: DMSService
        function onIsConnectedChanged() {
            if (DMSService.isConnected)
                loadConfig();
        }
    }

    SettingsPage {
        id: mainColumn

        SettingsNoteRow {
            paintBackground: false
            visible: !DMSService.isConnected || configError
            text: !DMSService.isConnected ? I18n.tr("DMS service is not connected. Clipboard settings are unavailable.") : I18n.tr("Failed to load clipboard configuration.")
        }

        SettingsCard {
            tab: "clipboard"
            tags: ["clipboard", "history", "limit"]
            title: I18n.tr("History")
            iconName: "history"
            visible: configLoaded

            SettingsToggleRow {
                tab: "clipboard"
                tags: ["clipboard", "history", "enable", "disable", "disk", "persistence"]
                settingKey: "disabled"
                text: I18n.tr("Enabled")
                checked: root.historyEnabled
                enabled: !root.saving
                onToggled: checked => root.saveConfig("disabled", !checked)
            }

            SettingsDropdownRow {
                id: maxHistoryDropdown
                enabled: root.historyEnabled
                tab: "clipboard"
                tags: ["clipboard", "history", "max", "limit"]
                settingKey: "maxHistory"
                text: I18n.tr("Maximum entries")
                options: root.maxHistoryOptions.map(opt => opt.text)

                Component.onCompleted: {
                    currentValue = root.getMaxHistoryText(root.config.maxHistory ?? 100);
                }

                onValueChanged: value => {
                    for (let opt of root.maxHistoryOptions) {
                        if (opt.text === value) {
                            root.saveConfig("maxHistory", opt.value);
                            return;
                        }
                    }
                }

                Connections {
                    target: root
                    function onConfigChanged() {
                        maxHistoryDropdown.currentValue = root.getMaxHistoryText(root.config.maxHistory ?? 100);
                    }
                }
            }

            SettingsDropdownRow {
                id: maxEntrySizeDropdown
                enabled: root.historyEnabled
                tab: "clipboard"
                tags: ["clipboard", "entry", "size", "limit"]
                settingKey: "maxEntrySize"
                text: I18n.tr("Maximum entry size")
                options: root.maxEntrySizeOptions.map(opt => opt.text)

                Component.onCompleted: {
                    currentValue = root.getMaxEntrySizeText(root.config.maxEntrySize ?? 5242880);
                }

                onValueChanged: value => {
                    for (let opt of root.maxEntrySizeOptions) {
                        if (opt.text === value) {
                            root.saveConfig("maxEntrySize", opt.value);
                            return;
                        }
                    }
                }

                Connections {
                    target: root
                    function onConfigChanged() {
                        maxEntrySizeDropdown.currentValue = root.getMaxEntrySizeText(root.config.maxEntrySize ?? 5242880);
                    }
                }
            }

            SettingsDropdownRow {
                id: autoClearDaysDropdown
                enabled: root.historyEnabled
                tab: "clipboard"
                tags: ["clipboard", "auto", "clear", "days"]
                settingKey: "autoClearDays"
                text: I18n.tr("Auto-clear after")
                options: root.autoClearOptions.map(opt => opt.text)

                Component.onCompleted: {
                    currentValue = root.getAutoClearText(root.config.autoClearDays ?? 0);
                }

                onValueChanged: value => {
                    for (let opt of root.autoClearOptions) {
                        if (opt.text === value) {
                            root.saveConfig("autoClearDays", opt.value);
                            return;
                        }
                    }
                }

                Connections {
                    target: root
                    function onConfigChanged() {
                        autoClearDaysDropdown.currentValue = root.getAutoClearText(root.config.autoClearDays ?? 0);
                    }
                }
            }

            SettingsDropdownRow {
                id: maxPinnedDropdown
                enabled: root.historyEnabled
                tab: "clipboard"
                tags: ["clipboard", "pinned", "max", "limit"]
                settingKey: "maxPinned"
                text: I18n.tr("Maximum pinned entries")
                options: root.maxPinnedOptions.map(opt => opt.text)

                function updateValue() {
                    if (root.configLoaded) {
                        currentValue = root.getMaxPinnedText(root.config.maxPinned ?? 25);
                    }
                }

                Component.onCompleted: {
                    updateValue();
                }

                onValueChanged: value => {
                    for (let opt of root.maxPinnedOptions) {
                        if (opt.text === value) {
                            root.saveConfig("maxPinned", opt.value);
                            return;
                        }
                    }
                }

                Connections {
                    target: root
                    function onConfigLoadedChanged() {
                        if (root.configLoaded) {
                            maxPinnedDropdown.updateValue();
                        }
                    }
                    function onConfigChanged() {
                        maxPinnedDropdown.updateValue();
                    }
                }
            }

            SettingsToggleRow {
                tab: "clipboard"
                tags: ["clipboard", "clear", "startup"]
                settingKey: "clearAtStartup"
                text: I18n.tr("Clear at startup")
                checked: root.config.clearAtStartup ?? false
                enabled: root.historyEnabled
                onToggled: checked => root.saveConfig("clearAtStartup", checked)
            }
        }

        SettingsCard {
            tab: "clipboard"
            tags: ["clipboard", "behavior"]
            title: I18n.tr("Behavior")
            iconName: "settings"
            visible: configLoaded

            SettingsToggleRow {
                tab: "clipboard"
                tags: ["clipboard", "click", "paste", "behavior"]
                settingKey: "clipboardClickToPaste"
                text: I18n.tr("Click to paste")
                checked: SettingsData.clipboardClickToPaste
                onToggled: checked => SettingsData.set("clipboardClickToPaste", checked)
            }

            SettingsToggleRow {
                tab: "clipboard"
                tags: ["clipboard", "enter", "paste", "behavior"]
                settingKey: "clipboardEnterToPaste"
                text: I18n.tr("Enter to paste")
                checked: SettingsData.clipboardEnterToPaste
                onToggled: checked => SettingsData.set("clipboardEnterToPaste", checked)
            }
        }

        SettingsCard {
            tab: "clipboard"
            tags: ["clipboard", "appearance", "size", "modal"]
            settingKey: "clipboardAppearance"
            title: I18n.tr("Appearance")
            iconName: "tune"

            SettingsButtonGroupRow {
                readonly property var sizes: ["micro", "compact", "medium", "large"]

                tab: "clipboard"
                tags: ["clipboard", "size", "micro", "compact", "medium", "large"]
                settingKey: "clipboardSize"
                text: I18n.tr("Size")
                model: ["1", "2", "3", "4"]
                currentIndex: {
                    const index = sizes.indexOf(SettingsData.clipboardSize);
                    return index >= 0 ? index : 1;
                }
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.set("clipboardSize", sizes[index]);
                }
            }
        }

        SettingsCard {
            tab: "clipboard"
            tags: ["clipboard", "advanced"]
            title: I18n.tr("Advanced")
            iconName: "tune"
            collapsible: true
            expanded: false
            visible: configLoaded

            SettingsToggleRow {
                tab: "clipboard"
                tags: ["clipboard", "filter", "type", "remember", "behavior"]
                settingKey: "clipboardRememberTypeFilter"
                text: I18n.tr("Remember type filter")
                checked: SettingsData.clipboardRememberTypeFilter
                onToggled: checked => SettingsData.set("clipboardRememberTypeFilter", checked)
            }

            SettingsToggleRow {
                tab: "clipboard"
                tags: ["clipboard", "fullscreen", "overlay", "layer", "behavior"]
                settingKey: "clipboardUseOverlayLayer"
                text: I18n.tr("Use overlay layer")
                checked: SettingsData.clipboardUseOverlayLayer
                onToggled: checked => SettingsData.set("clipboardUseOverlayLayer", checked)
            }

            SettingsButtonGroupRow {
                tab: "clipboard"
                tags: ["clipboard", "actions", "buttons", "hide", "density", "copy", "paste", "pin", "edit", "delete"]
                settingKey: "clipboardVisibleEntryActions"
                resetByKeys: false
                onResetRequested: {
                    SettingsData.resetToDefault(["clipboardVisibleEntryActions"]);
                    currentSelection = root.visibleEntryActionLabels();
                }
                text: I18n.tr("Visible entry actions")
                selectionMode: "multi"
                model: root.entryActionLabels
                currentSelection: root.visibleEntryActionLabels()
                checkEnabled: false
                buttonHeight: 28
                minButtonWidth: 56
                buttonPadding: Theme.spacingS
                textSize: Theme.fontSizeSmall
                onSelectionChanged: (index, selected) => root.setVisibleEntryAction(index, selected)
            }
        }
    }
}
