import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

Item {
    id: root

    property var parentModal: null
    property bool editorOpen: false
    property bool editorMounted: false
    property var editorRequest: null
    readonly property bool hasPendingRule: SettingsData.pendingNotificationRule !== null

    function indexedRules(predicate) {
        return (SettingsData.notificationRules || []).map((rule, index) => ({
                    rule: rule,
                    index: index
                })).filter(entry => predicate(entry.rule));
    }

    // Expired timed mutes drop out of the list the minute they lapse
    // (notificationRuleNowMs ticks), without waiting for the sweep.
    readonly property var mutedRules: indexedRules(rule => (rule.action || "").toString().toLowerCase() === "mute" && !SettingsData.isNotificationRuleExpired(rule, NotificationService.notificationRuleNowMs))

    readonly property var notificationRuleFieldOptions: [
        {
            value: "appName",
            label: I18n.tr("App name", "notification rule match field option")
        },
        {
            value: "desktopEntry",
            label: I18n.tr("Desktop Entry", "notification rule match field option")
        },
        {
            value: "summary",
            label: I18n.tr("Summary", "notification rule match field option")
        },
        {
            value: "body",
            label: I18n.tr("Body", "notification rule match field option")
        }
    ]

    readonly property var notificationRuleMatchTypeOptions: [
        {
            value: "contains",
            label: I18n.tr("Contains", "notification rule match type option")
        },
        {
            value: "exact",
            label: I18n.tr("Exact", "notification rule match type option")
        },
        {
            value: "regex",
            label: I18n.tr("Regex", "notification rule match type option")
        }
    ]

    readonly property var notificationRuleActionOptions: [
        {
            value: "default",
            label: I18n.tr("Default", "notification rule action option")
        },
        {
            value: "mute",
            label: I18n.tr("Mute Popups", "notification rule action option")
        },
        {
            value: "ignore",
            label: I18n.tr("Ignore Completely", "notification rule action option")
        },
        {
            value: "popup_only",
            label: I18n.tr("Popup Only", "notification rule action option")
        },
        {
            value: "no_history",
            label: I18n.tr("No History", "notification rule action option")
        }
    ]

    readonly property var notificationRuleUrgencyOptions: [
        {
            value: "default",
            label: I18n.tr("Default", "notification rule urgency option")
        },
        {
            value: "low",
            label: I18n.tr("Low Priority", "notification rule urgency option")
        },
        {
            value: "normal",
            label: I18n.tr("Normal Priority", "notification rule urgency option")
        },
        {
            value: "critical",
            label: I18n.tr("Critical Priority", "notification rule urgency option")
        }
    ]

    function getRuleOptionLabel(options, value, fallback) {
        for (let i = 0; i < options.length; i++) {
            if (options[i].value === value)
                return options[i].label;
        }
        return fallback;
    }

    function matchSummary(rule) {
        const parts = [getRuleOptionLabel(notificationRuleFieldOptions, rule.field, notificationRuleFieldOptions[0].label), getRuleOptionLabel(notificationRuleMatchTypeOptions, rule.matchType, notificationRuleMatchTypeOptions[0].label)];
        const extra = (rule.conditions || []).length;
        if (extra > 0)
            parts.push(I18n.tr("+%1 conditions", "notification rule summary, %1 is the number of extra conditions").arg(extra));
        return parts.join(" · ");
    }

    function remainingLabel(rule) {
        const expiresAt = rule && rule.expiresAt ? rule.expiresAt : 0;
        if (expiresAt <= NotificationService.notificationRuleNowMs)
            return "";
        const remaining = NotificationService.formatRuleRemaining(expiresAt);
        return remaining ? I18n.tr("expires in %1", "timed notification rule, %1 = remaining time until it expires").arg(remaining) : "";
    }

    function outcomeBadges(rule) {
        const badges = [];
        if ((rule.action || "default") !== "default")
            badges.push(getRuleOptionLabel(notificationRuleActionOptions, rule.action, rule.action));
        if ((rule.urgency || "default") !== "default")
            badges.push(getRuleOptionLabel(notificationRuleUrgencyOptions, rule.urgency, rule.urgency));
        if (rule.bypassDnd === true)
            badges.push(I18n.tr("Allow in Do Not Disturb"));
        const remaining = remainingLabel(rule);
        if (remaining !== "")
            badges.push(remaining);
        return badges;
    }

    onHasPendingRuleChanged: {
        // clearing the draft inside this handler is a binding loop on hasPendingRule
        if (hasPendingRule)
            Qt.callLater(openPendingRule);
    }

    function openPendingRule() {
        const draft = SettingsData.pendingNotificationRule;
        if (!draft)
            return;
        SettingsData.pendingNotificationRule = null;
        openEditor(-1, draft);
    }

    function openEditor(index, rule) {
        if (editorOpen)
            return;
        editorRequest = {
            index,
            rule
        };
        editorOpen = true;
        editorMounted = true;
        if (editorLoader.item)
            presentEditor();
    }

    function presentEditor() {
        if (!editorRequest)
            return;
        editorLoader.item.show(editorRequest.index, editorRequest.rule);
    }

    function closeEditor() {
        if (!editorOpen)
            return;
        editorOpen = false;
        editorRequest = null;
        if (editorLoader.item)
            editorLoader.item.opened = false;
    }

    SettingsPage {
        id: mainColumn

        SettingsCard {
            id: notificationRulesCard
            width: parent.width
            iconName: "rule_settings"
            title: I18n.tr("Notification rules", "settings card title, per-app notification rules list")
            settingKey: "notificationRules"
            tags: ["notification", "rules", "mute", "ignore", "priority", "regex", "history"]

            headerActions: DActionButton {
                buttonSize: 36
                iconName: "restart_alt"
                tooltipText: I18n.tr("Reset to default")
                iconSize: 20
                visible: JSON.stringify(SettingsData.notificationRules) !== JSON.stringify(SettingsData.getDefaultNotificationRules())
                iconColor: Theme.surfaceVariantText
                onClicked: SettingsData.resetNotificationRules()
            }

            SettingsRow {
                subtitle: I18n.tr("Mute, ignore and priority rules per app")
            }

            Repeater {
                // Count model: a rule edit must not rebuild the row holding the focused toggle
                model: SettingsData.notificationRules.length

                delegate: SettingsRow {
                    id: ruleRow

                    required property int index
                    readonly property var rule: SettingsData.notificationRules[index] ?? ({})
                    readonly property var badges: root.outcomeBadges(rule)

                    title: rule.pattern || I18n.tr("Rule %1", "notification rule heading, %1 is the rule number").arg(index + 1)
                    titleColor: rule.enabled !== false ? Theme.surfaceText : Theme.surfaceVariantText
                    subtitle: root.matchSummary(rule)

                    DToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        hideText: true
                        text: ruleRow.title
                        checked: ruleRow.rule.enabled !== false
                        onToggled: checked => SettingsData.updateNotificationRuleField(ruleRow.index, "enabled", checked)
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "edit"
                        Accessible.name: I18n.tr("Edit rule")
                        onClicked: root.openEditor(ruleRow.index, ruleRow.rule)
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        Accessible.name: I18n.tr("Delete rule")
                        onClicked: SettingsData.removeNotificationRule(ruleRow.index)
                    }

                    body: Flow {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: ruleRow.badges.length > 0

                        Repeater {
                            model: ruleRow.badges

                            delegate: DBadge {
                                required property string modelData
                                text: modelData
                                color: Theme.primaryContainer
                                textColor: Theme.onPrimaryContainer
                            }
                        }
                    }
                }
            }
        }

        SettingsCard {
            iconName: "volume_off"
            title: I18n.tr("Muted apps")
            settingKey: "mutedApps"
            tags: ["notification", "mute", "unmute", "popup"]

            SettingsRow {
                subtitle: root.mutedRules.length > 0 ? I18n.tr("Apps with notification popups muted. Unmute or delete to remove.") : I18n.tr("No apps muted. Right-click a notification and choose \"Mute popups\" to add one here.")
            }

            Repeater {
                model: root.mutedRules

                delegate: SettingsRow {
                    required property var modelData

                    title: modelData.rule?.pattern || I18n.tr("Unknown")
                    subtitle: root.remainingLabel(modelData.rule)
                    singleLineTitle: true

                    DButton {
                        text: I18n.tr("Unmute")
                        backgroundColor: "transparent"
                        textColor: Theme.primary
                        onClicked: SettingsData.removeNotificationRule(modelData.index)
                    }
                }
            }
        }

        SettingsFabBar {
            DFab {
                text: I18n.tr("Add rule", "notification rule dialog title and button")
                iconName: "add"
                onClicked: root.openEditor(-1, null)
            }
        }
    }

    Loader {
        id: editorLoader
        parent: root.parentModal?.modalFocusScope ?? root
        anchors.fill: parent
        z: 100
        active: root.editorMounted
        onLoaded: root.presentEditor()

        sourceComponent: NotificationRuleEditorDialog {
            fieldOptions: root.notificationRuleFieldOptions
            matchTypeOptions: root.notificationRuleMatchTypeOptions
            actionOptions: root.notificationRuleActionOptions
            urgencyOptions: root.notificationRuleUrgencyOptions
            onRejected: root.closeEditor()
            onRuleSubmitted: root.closeEditor()
            onActiveChanged: {
                if (!active && !root.editorOpen)
                    root.editorMounted = false;
            }
        }
    }
}
