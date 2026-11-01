import QtQuick
import Quickshell
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    function getBarComponentsFromSettings() {
        const bars = SettingsData.barConfigs || [];
        return bars.map(bar => {
            return {
                "id": "bar:" + bar.id,
                "name": bar.name || "Bar",
                "barId": bar.id
            };
        });
    }

    property var variantComponents: getVariantComponentsList()

    function getVariantComponentsList() {
        return [...getBarComponentsFromSettings(),
            {
                "id": "notifications",
                "name": I18n.tr("Notification popups")
            },
            {
                "id": "wallpaper",
                "name": I18n.tr("Wallpaper")
            },
            {
                "id": "osd",
                "name": I18n.tr("OSD", "on-screen display, shell component name in per-display settings")
            },
            {
                "id": "toast",
                "name": I18n.tr("Toasts", "noun plural, toast popups, shell component name in per-display settings")
            },
            {
                "id": "notepad",
                "name": I18n.tr("Notepad")
            }
        ];
    }

    Connections {
        target: SettingsData
        function onBarConfigsChanged() {
            variantComponents = getVariantComponentsList();
        }
    }

    function getScreenPreferences(componentId) {
        if (componentId.startsWith("bar:")) {
            const barId = componentId.substring(4);
            const barConfig = SettingsData.getBarConfig(barId);
            return barConfig?.screenPreferences || ["all"];
        }
        return SettingsData.screenPreferences && SettingsData.screenPreferences[componentId] || ["all"];
    }

    function setScreenPreferences(componentId, screenNames) {
        if (componentId.startsWith("bar:")) {
            const barId = componentId.substring(4);
            SettingsData.updateBarConfig(barId, {
                "screenPreferences": screenNames
            });
            return;
        }
        var prefs = SettingsData.screenPreferences || {};
        var newPrefs = Object.assign({}, prefs);
        newPrefs[componentId] = screenNames;
        SettingsData.set("screenPreferences", newPrefs);
    }

    function getShowOnLastDisplay(componentId) {
        if (componentId.startsWith("bar:")) {
            const barId = componentId.substring(4);
            const barConfig = SettingsData.getBarConfig(barId);
            return barConfig?.showOnLastDisplay ?? true;
        }
        return SettingsData.showOnLastDisplay && SettingsData.showOnLastDisplay[componentId] || false;
    }

    function setShowOnLastDisplay(componentId, enabled) {
        if (componentId.startsWith("bar:")) {
            const barId = componentId.substring(4);
            SettingsData.updateBarConfig(barId, enabled ? {
                "showOnLastDisplay": true,
                "hideOnLastDisplay": false
            } : {
                "showOnLastDisplay": false
            });
            return;
        }
        var prefs = SettingsData.showOnLastDisplay || {};
        var newPrefs = Object.assign({}, prefs);
        newPrefs[componentId] = enabled;
        SettingsData.set("showOnLastDisplay", newPrefs);
    }

    function getHideOnLastDisplay(componentId) {
        if (!componentId.startsWith("bar:"))
            return false;
        const barId = componentId.substring(4);
        return SettingsData.getBarConfig(barId)?.hideOnLastDisplay ?? false;
    }

    function setHideOnLastDisplay(componentId, enabled) {
        if (!componentId.startsWith("bar:"))
            return;
        const barId = componentId.substring(4);
        SettingsData.updateBarConfig(barId, enabled ? {
            "hideOnLastDisplay": true,
            "showOnLastDisplay": false
        } : {
            "hideOnLastDisplay": false
        });
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            title: I18n.tr("Available displays (%1)", "display widgets settings heading, %1 is the monitor count").arg(Quickshell.screens.length)

            SettingsButtonGroupRow {
                id: displayModeGroup
                readonly property bool modelMode: SettingsData.displayNameMode === "model"
                text: I18n.tr("Name format")
                model: [I18n.tr("Name"), I18n.tr("Model")]
                currentIndex: modelMode ? 1 : 0
                onModelModeChanged: currentIndex = modelMode ? 1 : 0
                onSelectionChanged: (index, selected) => {
                    if (!selected)
                        return;
                    SettingsData.displayNameMode = index === 1 ? "model" : "system";
                    SettingsData.saveSettings();
                }
            }

            Repeater {
                model: Quickshell.screens

                SettingsRow {
                    required property var modelData
                    readonly property var currentMode: WlrOutputService.wlrOutputAvailable ? WlrOutputService.getOutput(modelData.name)?.currentMode : null

                    iconName: "desktop_windows"
                    title: SettingsData.getScreenDisplayName(modelData)
                    subtitle: {
                        const size = currentMode ? currentMode.width + "×" + currentMode.height + "@" + Math.round(currentMode.refresh / 1000) + "Hz" : modelData.width + "×" + modelData.height;
                        return size + " · " + (SettingsData.displayNameMode === "system" ? (modelData.model || I18n.tr("Unknown Model")) : modelData.name);
                    }
                }
            }
        }

        Repeater {
            model: root.variantComponents

            SettingsCard {
                id: componentCard
                required property var modelData

                title: modelData.name

                SettingsDisplayPicker {
                    displayPreferences: root.getScreenPreferences(componentCard.modelData.id)
                    emptyMeansAll: false
                    allowEmpty: true
                    showLastDisplay: ["notifications", "osd", "toast", "notepad"].includes(componentCard.modelData.id) || componentCard.modelData.id.startsWith("bar:")
                    showOnLastDisplay: root.getShowOnLastDisplay(componentCard.modelData.id)
                    allowHideOnLastDisplay: componentCard.modelData.id.startsWith("bar:")
                    hideOnLastDisplay: root.getHideOnLastDisplay(componentCard.modelData.id)
                    preferencesHandler: prefs => root.setScreenPreferences(componentCard.modelData.id, prefs)
                    onLastDisplayToggled: checked => root.setShowOnLastDisplay(componentCard.modelData.id, checked)
                    onHideOnLastDisplayToggled: checked => root.setHideOnLastDisplay(componentCard.modelData.id, checked)
                }

                SettingsToggleRow {
                    visible: componentCard.modelData.id === "notifications"
                    text: I18n.tr("Focused display only")
                    checked: SettingsData.notificationFocusedMonitor
                    onToggled: checked => SettingsData.set("notificationFocusedMonitor", checked)
                }
            }
        }
    }
}
