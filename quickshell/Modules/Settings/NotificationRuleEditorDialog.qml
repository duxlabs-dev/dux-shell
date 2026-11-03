pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

DDialog {
    id: root

    required property var fieldOptions
    required property var matchTypeOptions
    required property var actionOptions
    required property var urgencyOptions

    property int editingIndex: -1
    property string ruleField: ""
    property string ruleMatchType: ""
    property string ruleAction: ""
    property string ruleUrgency: ""
    property bool ruleBypassDnd: false
    property var ruleConditions: []
    readonly property bool isEditMode: editingIndex >= 0

    signal ruleSubmitted

    embedded: nativeWindow
    opened: nativeWindow
    maximumWidth: SettingsMetrics.formDialogWidth
    surfaceColor: Theme.hostSurface
    title: isEditMode ? I18n.tr("Edit rule") : I18n.tr("Add rule", "notification rule dialog title and button")
    acceptEnabled: patternInput.text.trim() !== ""
    onAccepted: submit()

    function labelOf(options, value) {
        return (options.find(option => option.value === value) ?? options[0]).label;
    }

    function valueOf(options, label) {
        return (options.find(option => option.label === label) ?? options[0]).value;
    }

    function show(index, rule) {
        editingIndex = index;
        populate(rule || {});
        opened = true;
        forceActiveFocus();
        patternInput.forceActiveFocus();
    }

    function populate(rule) {
        ruleField = rule.field || fieldOptions[0].value;
        ruleMatchType = rule.matchType || matchTypeOptions[0].value;
        ruleAction = rule.action || actionOptions[0].value;
        ruleUrgency = rule.urgency || urgencyOptions[0].value;
        ruleBypassDnd = rule.bypassDnd === true;
        ruleConditions = (rule.conditions || []).map(condition => ({
                    field: condition.field || fieldOptions[0].value,
                    matchType: condition.matchType || matchTypeOptions[0].value,
                    pattern: condition.pattern || ""
                }));
        patternInput.text = rule.pattern || "";
        fieldDropdown.currentValue = labelOf(fieldOptions, ruleField);
        matchTypeDropdown.currentValue = labelOf(matchTypeOptions, ruleMatchType);
    }

    function submit() {
        if (!acceptEnabled)
            return;
        const rule = {
            field: ruleField,
            pattern: patternInput.text,
            matchType: ruleMatchType,
            conditions: ruleConditions.filter(condition => condition.pattern.trim() !== "").map(condition => Object.assign({}, condition)),
            action: ruleAction,
            urgency: ruleUrgency,
            bypassDnd: ruleBypassDnd
        };
        if (isEditMode)
            SettingsData.updateNotificationRule(editingIndex, rule);
        else
            SettingsData.addNotificationRule(rule);
        ruleSubmitted();
    }

    function addCondition() {
        ruleConditions = ruleConditions.concat([
            {
                field: fieldOptions[0].value,
                matchType: matchTypeOptions[0].value,
                pattern: ""
            }
        ]);
    }

    function removeCondition(index) {
        ruleConditions = ruleConditions.filter((_, i) => i !== index);
    }

    actions: [
        DButton {
            text: I18n.tr("Cancel")
            backgroundColor: "transparent"
            textColor: Theme.primary
            onClicked: root.rejected()
        },
        DButton {
            text: root.isEditMode ? I18n.tr("Save") : I18n.tr("Add")
            enabled: root.acceptEnabled
            onClicked: root.submit()
        }
    ]

    SettingsCard {
        title: I18n.tr("Match Criteria")

        SettingsRow {
            body: Row {
                width: parent.width
                spacing: Theme.spacingS

                DDropdown {
                    id: fieldDropdown
                    width: Math.round(parent.width / 3)
                    anchors.verticalCenter: parent.verticalCenter
                    compactMode: true
                    Accessible.name: I18n.tr("Field", "notification rule dropdown label, which notification field to match")
                    options: root.fieldOptions.map(option => option.label)
                    onValueChanged: value => root.ruleField = root.valueOf(root.fieldOptions, value)
                }

                DDropdown {
                    id: matchTypeDropdown
                    width: Math.round(parent.width / 4)
                    anchors.verticalCenter: parent.verticalCenter
                    compactMode: true
                    Accessible.name: I18n.tr("Match type", "notification rule dropdown label, how the pattern is compared")
                    options: root.matchTypeOptions.map(option => option.label)
                    onValueChanged: value => root.ruleMatchType = root.valueOf(root.matchTypeOptions, value)
                }

                DTextField {
                    id: patternInput
                    width: parent.width - fieldDropdown.width - matchTypeDropdown.width - parent.spacing * 2
                    anchors.verticalCenter: parent.verticalCenter
                    outlined: true
                    placeholderText: I18n.tr("Pattern", "noun, text field label for a match or filter pattern")
                    onAccepted: root.submit()
                }
            }
        }

        // Edits go to the array entry in place: modelData is a copy, and reassigning the array would rebuild the rows and drop focus.
        Repeater {
            model: root.ruleConditions

            delegate: SettingsRow {
                id: conditionRow

                required property var modelData
                required property int index

                body: Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DDropdown {
                        id: conditionFieldDropdown
                        width: Math.round(parent.width / 3)
                        anchors.verticalCenter: parent.verticalCenter
                        compactMode: true
                        Accessible.name: I18n.tr("Field", "notification rule dropdown label, which notification field to match")
                        options: root.fieldOptions.map(option => option.label)
                        currentValue: root.labelOf(root.fieldOptions, conditionRow.modelData.field)
                        onValueChanged: value => root.ruleConditions[conditionRow.index].field = root.valueOf(root.fieldOptions, value)
                    }

                    DDropdown {
                        id: conditionMatchTypeDropdown
                        width: Math.round(parent.width / 4)
                        anchors.verticalCenter: parent.verticalCenter
                        compactMode: true
                        Accessible.name: I18n.tr("Match type", "notification rule dropdown label, how the pattern is compared")
                        options: root.matchTypeOptions.map(option => option.label)
                        currentValue: root.labelOf(root.matchTypeOptions, conditionRow.modelData.matchType)
                        onValueChanged: value => root.ruleConditions[conditionRow.index].matchType = root.valueOf(root.matchTypeOptions, value)
                    }

                    DTextField {
                        id: conditionPatternInput
                        width: parent.width - conditionFieldDropdown.width - conditionMatchTypeDropdown.width - removeConditionButton.width - parent.spacing * 3
                        anchors.verticalCenter: parent.verticalCenter
                        outlined: true
                        placeholderText: I18n.tr("Pattern", "noun, text field label for a match or filter pattern")
                        Component.onCompleted: text = conditionRow.modelData.pattern
                        onTextEdited: root.ruleConditions[conditionRow.index].pattern = text
                        onAccepted: root.submit()
                    }

                    DActionButton {
                        id: removeConditionButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "delete"
                        iconColor: Theme.error
                        Accessible.name: I18n.tr("Remove condition", "button in the notification rule editor, removes this match condition")
                        onClicked: root.removeCondition(conditionRow.index)
                    }
                }
            }
        }

        SettingsRow {
            subtitle: root.ruleConditions.length > 0 ? I18n.tr("A notification must match every condition", "hint in the notification rule editor, all match conditions must apply") : ""

            DButton {
                text: I18n.tr("Add condition", "button in the notification rule editor, adds another match condition")
                iconName: "add"
                backgroundColor: "transparent"
                textColor: Theme.primary
                onClicked: root.addCondition()
            }
        }
    }

    SettingsCard {
        title: I18n.tr("Actions")

        SettingsDropdownRow {
            text: I18n.tr("Action", "noun, dropdown label for what a notification rule or keybind does")
            description: I18n.tr("The Default action only overrides priority")
            options: root.actionOptions.map(option => option.label)
            currentValue: root.labelOf(root.actionOptions, root.ruleAction)
            onValueChanged: value => root.ruleAction = root.valueOf(root.actionOptions, value)
        }

        SettingsDropdownRow {
            text: I18n.tr("Priority", "notification rule dropdown label, urgency assigned to matches")
            options: root.urgencyOptions.map(option => option.label)
            currentValue: root.labelOf(root.urgencyOptions, root.ruleUrgency)
            onValueChanged: value => root.ruleUrgency = root.valueOf(root.urgencyOptions, value)
        }

        SettingsToggleRow {
            text: I18n.tr("Allow in Do Not Disturb")
            checked: root.ruleBypassDnd
            onToggled: checked => root.ruleBypassDnd = checked
        }
    }
}
