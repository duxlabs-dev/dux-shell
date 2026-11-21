pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Overview
import "../DDash/utils/cards.js" as CardUtils
import "../../Services/SysmonCatalog.js" as SysmonCatalog

FocusScope {
    id: root

    property var parentModal: null

    focus: true

    readonly property var tabs: DashRegistry.tabEntries
    readonly property var optionCards: DashRegistry.entries.filter(e => (e.options?.length ?? 0) > 0).reduce((all, e) => {
        const copies = e.card?.allowMultiple === true ? DashRegistry.placed.filter(c => c.id === e.id) : [];
        if (copies.length === 0)
            return all.concat([{
                    "id": e.id,
                    "instanceId": "",
                    "number": 1,
                    "key": e.id
                }]);
        return all.concat(copies.map((c, i) => {
            const instanceId = typeof c.instanceId === "string" ? c.instanceId : "";
            return {
                "id": e.id,
                "instanceId": instanceId,
                "number": i + 1,
                "key": e.id + ":" + instanceId
            };
        }));
    }, [])

    readonly property var sysmonCards: DashRegistry.placed.filter(c => c?.id === "sysmon" && typeof c.instanceId === "string" && c.instanceId !== "").map(c => ({
                "instanceId": c.instanceId,
                "w": c.w,
                "h": c.h,
                "config": c.config
            }))

    function sysmonTitle(config) {
        return SysmonService.configTitle(config) || DashRegistry.entry("sysmon")?.text || "";
    }

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
        SettingsDeferred {
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
        }

        SettingsDeferred {
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
        }

        SettingsDeferred {
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
        }

        SettingsDeferred {
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
        }

        SettingsDeferred {
            when: root.sysmonCards.length > 0

            SettingsCard {
                title: I18n.tr("System Monitor", "system monitor widget name")
                iconName: "monitoring"
                settingKey: "dashSysmonCards"
                tab: "dank_dash"

                Repeater {
                    model: ScriptModel {
                        values: root.sysmonCards
                        objectProp: "instanceId"
                    }

                    SettingsRow {
                        id: cardRow

                        required property var modelData

                        readonly property var config: SysmonCatalog.normalizeConfig(modelData.config, SysmonCatalog.defaultDashConfig())

                        iconName: SysmonService.layoutIcon(config.layout)
                        title: root.sysmonTitle(config)
                        subtitle: actions.confirming ? I18n.tr("Confirm Delete", "delete button confirmation text") : SysmonService.layoutName(config.layout) + " · " + modelData.w + "×" + modelData.h
                        subtitleColor: actions.confirming ? Theme.error : supportingContentColor
                        clickable: true
                        onClicked: {
                            SettingsUiState.selectedDashCardId = modelData.instanceId;
                            SettingsUiState.selectedWidgetTitle = title;
                            root.parentModal?.navigateTo("dash_sysmon_card");
                        }

                        SettingsInstanceActions {
                            id: actions
                            anchors.verticalCenter: parent.verticalCenter
                            onDuplicateRequested: {
                                if (!DashRegistry.duplicateCard("sysmon", cardRow.modelData.instanceId))
                                    ToastService.showWarning(I18n.tr("Failed to duplicate %1", "toast title, %1 is a dash card name").arg(cardRow.title), I18n.tr("No room left on the dashboard", "dash settings: why a card can't be duplicated"));
                            }
                            onDeleteRequested: CardUtils.removeCard(DashRegistry.instanceIndex("sysmon", cardRow.modelData.instanceId))
                        }
                    }
                }
            }
        }

        Repeater {
            // keyed models keep a card alive across option changes, a rebuilt card collapses
            model: ScriptModel {
                values: root.optionCards
                objectProp: "key"
            }

            SettingsCard {
                id: optionCard

                required property var modelData
                readonly property string entryId: modelData.id
                readonly property string instanceId: modelData.instanceId
                readonly property string keySuffix: modelData.number > 1 ? "#" + modelData.number : ""
                readonly property var entry: DashRegistry.entries.find(e => e.id === entryId) ?? null
                readonly property var options: entry?.options ?? []
                readonly property string numberedTitle: modelData.number > 1 ? I18n.tr("%1 %2", "dash card name followed by its copy number, e.g. Clock 2").arg(entry?.text ?? "").arg(modelData.number) : (entry?.text ?? "")

                title: numberedTitle
                settingKey: "dashOptions:" + entryId + keySuffix
                tab: "dank_dash"
                collapsible: true
                expanded: false

                Repeater {
                    model: optionCard.contentWanted ? optionCard.options.length : 0

                    DashOptionRow {
                        required property int index

                        spec: optionCard.options[index] ?? ({})
                        value: DashRegistry.option(optionCard.entryId, spec.key, optionCard.instanceId)
                        settingKey: "dashOptions:" + optionCard.entryId + optionCard.keySuffix + ":" + spec.key
                        onCommitted: next => DashRegistry.setOption(optionCard.entryId, spec.key, next, optionCard.instanceId)
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
