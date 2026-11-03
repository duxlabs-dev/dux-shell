import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.DCommon.Widgets

Column {
    id: root

    property var page: null
    property string newOverrideRaw: ""
    property string newOverrideLabel: ""

    readonly property var overrides: root.page.value("keyboardLayoutNameLabelOverrides") ?? ({})
    readonly property var overridesModel: Object.keys(overrides).sort().map(raw => ({
                "raw": raw,
                "label": overrides[raw]
            }))

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    function addOverride() {
        const raw = newOverrideRaw.trim();
        const label = newOverrideLabel.trim();
        if (!raw || !label)
            return;
        const updated = Object.assign({}, overrides);
        updated[raw] = label;
        root.page.set("keyboardLayoutNameLabelOverrides", updated);
        root.newOverrideRaw = "";
        root.newOverrideLabel = "";
    }

    function removeOverride(raw) {
        const updated = Object.assign({}, overrides);
        delete updated[raw];
        root.page.set("keyboardLayoutNameLabelOverrides", updated);
    }

    SettingsCard {
        settingKey: "barWidgetKeyboardLayout"

        SettingsToggleRow {
            text: I18n.tr("Compact mode")
            checked: root.page.value("keyboardLayoutNameCompactMode")
            onToggled: checked => root.page.set("keyboardLayoutNameCompactMode", checked)
        }

        SettingsToggleRow {
            text: I18n.tr("Show icon")
            checked: root.page.value("keyboardLayoutNameShowIcon")
            onToggled: checked => root.page.set("keyboardLayoutNameShowIcon", checked)
        }
    }

    SettingsCard {
        settingKey: "barWidgetKeyboardLayoutOverrides"
        tags: ["keyboard", "layout", "label", "override", "rename"]
        iconName: "translate"
        title: I18n.tr("Label overrides", "card title, keyboard layout label override list")

        SettingsRow {
            subtitle: I18n.tr("Replace a displayed layout label with custom text, e.g. \"am-phonetic-alt\" → \"am\"", "explains the keyboard layout label override list")
        }

        SettingsRow {
            body: Row {
                width: parent.width
                spacing: Theme.spacingS

                DTextField {
                    id: rawField
                    outlined: true
                    labelText: I18n.tr("Displayed label", "keyboard layout override, the label currently shown")
                    width: (parent.width - addOverrideBtn.width - parent.spacing * 2) / 2
                    text: root.newOverrideRaw
                    onTextChanged: root.newOverrideRaw = text
                    onAccepted: root.addOverride()
                }

                DTextField {
                    id: customField
                    outlined: true
                    labelText: I18n.tr("Custom label", "keyboard layout override, the replacement label")
                    width: rawField.width
                    text: root.newOverrideLabel
                    onTextChanged: root.newOverrideLabel = text
                    onAccepted: root.addOverride()
                }

                DButton {
                    id: addOverrideBtn
                    iconName: "add"
                    text: I18n.tr("Add")
                    enabled: root.newOverrideRaw.trim().length > 0 && root.newOverrideLabel.trim().length > 0
                    onClicked: root.addOverride()
                }
            }
        }

        SettingsRow {
            body: Column {
                id: overridesList
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: root.overridesModel

                    delegate: Rectangle {
                        id: overrideItem
                        required property var modelData

                        width: overridesList.width
                        height: 48
                        radius: Theme.cornerRadius
                        color: SettingsMetrics.controlColor
                        border.width: 0

                        StyledText {
                            anchors.left: parent.left
                            anchors.right: removeOverrideBtn.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: overrideItem.modelData.raw + "  →  " + overrideItem.modelData.label
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        DActionButton {
                            id: removeOverrideBtn
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "close"
                            Accessible.name: I18n.tr("Remove")
                            iconSize: 16
                            buttonSize: 32
                            circular: true
                            iconColor: Theme.error
                            onClicked: root.removeOverride(overrideItem.modelData.raw)
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    text: I18n.tr("No label overrides", "empty state, keyboard layout label override list")
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.overridesModel.length === 0
                }
            }
        }
    }
}
