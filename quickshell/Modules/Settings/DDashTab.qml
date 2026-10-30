pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Overview

FocusScope {
    id: root

    property var parentModal: null

    focus: true

    readonly property var tabs: DashRegistry.tabEntries
    readonly property var optionEntryIds: DashRegistry.entries.filter(e => (e.options?.length ?? 0) > 0).map(e => e.id)

    function showDashPluginBrowser() {
        dashPluginBrowserLoader.active = true;
        if (dashPluginBrowserLoader.item)
            dashPluginBrowserLoader.item.show();
    }

    LazyLoader {
        id: dashPluginBrowserLoader
        active: false

        PluginBrowser {
            parentModal: root.parentModal
            typeFilters: ["dash-tab", "dash-card"]
        }
    }

    SettingsPage {
        SettingsCard {
            title: I18n.tr("Weather")

            SettingsNavRow {
                tab: "dank_dash"
                settingKey: "dashWeatherSettings"
                title: I18n.tr("Weather")
                iconName: "partly_cloudy_day"
                onClicked: keyboard => root.parentModal?.navigateTo("weather", keyboard)
            }
        }

        SettingsCard {
            title: I18n.tr("Media player")

            SettingsNavRow {
                tab: "dank_dash"
                settingKey: "dashMediaSettings"
                title: I18n.tr("Media player")
                hint: I18n.tr("Lyrics providers", "Lyrics source priority settings")
                iconName: "music_note"
                onClicked: keyboard => root.parentModal?.navigateTo("media_player", keyboard)
            }
        }

        SettingsCard {
            title: I18n.tr("Digital wellbeing", "settings page and dashboard tab title, screen time tracking")

            SettingsNavRow {
                tab: "dank_dash"
                settingKey: "dashWellbeingSettings"
                title: I18n.tr("Digital wellbeing", "settings page and dashboard tab title, screen time tracking")
                hint: I18n.tr("Screen time and app limits", "settings sidebar hint and dashboard tab description for digital wellbeing")
                iconName: "digital_wellbeing"
                onClicked: root.parentModal?.navigateTo("wellbeing")
            }
        }

        SettingsCard {
            title: I18n.tr("Tabs", "noun, card title for dashboard tabs")
            settingKey: "dashTabs"
            tab: "dank_dash"

            headerActions: DActionButton {
                iconName: "refresh"
                iconSize: Theme.iconSizeSmall
                tooltipText: I18n.tr("Reset to default")
                onClicked: {
                    SettingsData.resetDashTabs();
                    SettingsData.resetToDefault(["dashTabPosition", "dashTabsEvenlySpaced"]);
                }
            }

            SettingsDropdownRow {
                text: I18n.tr("Position")
                readonly property var positions: [
                    {
                        value: "auto",
                        text: I18n.tr("Auto")
                    },
                    {
                        value: "left",
                        text: I18n.tr("Left")
                    },
                    {
                        value: "right",
                        text: I18n.tr("Right")
                    },
                    {
                        value: "bottom",
                        text: I18n.tr("Bottom")
                    },
                    {
                        value: "center",
                        text: I18n.tr("Center")
                    }
                ]
                settingKey: "dashTabPosition"
                tab: "dank_dash"
                tags: ["dashboard", "tabs", "position", "navigation"]
                currentValue: (positions.find(option => option.value === SettingsData.dashTabPosition) ?? positions[0]).text
                options: positions.map(option => option.text)
                onValueChanged: value => {
                    const option = positions.find(option => option.text === value);
                    if (option)
                        SettingsData.set("dashTabPosition", option.value);
                }
            }

            SettingsToggleRow {
                settingKey: "dashTabsEvenlySpaced"
                tab: "dank_dash"
                tags: ["dashboard", "tabs", "spacing", "navigation"]
                text: I18n.tr("Evenly space tabs", "dashboard tab bar toggle")
                checked: SettingsData.dashTabsEvenlySpaced
                onToggled: checked => SettingsData.set("dashTabsEvenlySpaced", checked)
            }

            SettingsReorderList {
                id: tabList

                model: ScriptModel {
                    values: root.tabs
                    objectProp: "id"
                }
                onReordered: indices => SettingsData.setDashTabOrder(indices.map(i => root.tabs[i].id))

                delegate: SettingsReorderRow {
                    id: tabRow

                    required property var modelData

                    reorderList: tabList

                    readonly property bool available: modelData.available !== false

                    iconName: modelData.icon
                    iconColor: available && modelData.enabled ? Theme.primary : Theme.onSurface_38
                    titleColor: available ? Theme.surfaceText : Theme.onSurface_38
                    title: modelData.text
                    subtitle: available ? modelData.description ?? "" : I18n.tr("Disabled")
                    clickable: available
                    onClicked: SettingsData.setDashTabEnabled(modelData.id, !modelData.enabled)

                    Row {
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        DActionButton {
                            anchors.verticalCenter: parent.verticalCenter
                            objectName: "editDashTab"
                            iconName: "edit"
                            tooltipText: I18n.tr("Edit")
                            Accessible.description: tabRow.modelData.text
                            visible: !tabRow.modelData.action
                            enabled: tabRow.available
                            onClicked: PopoutService.openDankDashEditor(tabRow.modelData.id, root.Window.window?.screen)
                        }

                        DToggle {
                            anchors.verticalCenter: parent.verticalCenter
                            hideText: true
                            checked: tabRow.modelData.enabled
                            enabled: tabRow.available
                            onToggled: checked => SettingsData.setDashTabEnabled(tabRow.modelData.id, checked)
                        }
                    }
                }
            }
        }

        Repeater {
            // value-diffed ids keep a card alive across option changes, a rebuilt card collapses
            model: ScriptModel {
                values: root.optionEntryIds
            }

            SettingsCard {
                id: optionCard

                required property string modelData
                readonly property var entry: DashRegistry.entries.find(e => e.id === modelData) ?? null
                readonly property var options: entry?.options ?? []

                title: entry?.text ?? ""
                settingKey: "dashOptions:" + modelData
                tab: "dank_dash"
                collapsible: true
                expanded: false

                Repeater {
                    model: optionCard.options.length

                    DashOptionRow {
                        required property int index

                        spec: optionCard.options[index] ?? ({})
                        value: DashRegistry.option(optionCard.modelData, spec.key)
                        settingKey: "dashOptions:" + optionCard.modelData + ":" + spec.key
                        onCommitted: next => DashRegistry.setOption(optionCard.modelData, spec.key, next)
                    }
                }
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Browse plugins")
                iconName: "store"
                colorRole: "secondaryContainer"
                onClicked: root.showDashPluginBrowser()
            }
        }
    }
}
