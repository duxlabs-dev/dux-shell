pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// Read-only rules found in the user's compositor config, shown in Expert; each one can be copied into a DMS rule.
Column {
    id: root

    required property RulesList list
    property string expandedId: ""

    width: parent?.width ?? 0
    spacing: Theme.spacingS
    visible: list.externalRules.length > 0 && NiriPageService.expert

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: I18n.tr("User window rules (%1)", "card title for read-only compositor config rules, %1 is a count").arg(root.list.externalRules.length)
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.tr("Rules found in your compositor config. These are read-only here, use Convert to DMS to make an editable copy.")
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Repeater {
        model: ScriptModel {
            objectProp: "id"
            values: root.list.externalRules
        }

        delegate: SettingsRow {
            id: ext

            required property var modelData
            readonly property bool expanded: root.expandedId === modelData.id
            readonly property var actionChips: root.list.chips(modelData.actions)

            title: modelData.name || root.list.matchesOf(modelData)[0]?.appId || root.list.matchesOf(modelData)[0]?.title || I18n.tr("Any window")
            subtitle: root.list.subtitleOf(modelData)
            clickable: true
            onClicked: root.expandedId = expanded ? "" : modelData.id

            DBadge {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: (ext.modelData.source || "").split("/").pop()
                color: SettingsMetrics.controlColor
                textColor: Theme.surfaceVariantText
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: ext.expanded ? "expand_less" : "expand_more"
                size: Theme.iconSize
                color: Theme.surfaceVariantText
            }

            DActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "content_copy"
                iconColor: Theme.surfaceVariantText
                tooltipText: I18n.tr("Convert to DMS")
                tooltipSide: "left"
                Accessible.name: I18n.tr("Convert to DMS")
                onClicked: root.list.openEditor("copy", ext.modelData)
            }

            body: Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: ext.actionChips.length > 0 || ext.expanded

                Flow {
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: ext.actionChips

                        delegate: DBadge {
                            required property string modelData
                            maximumWidth: parent?.width ?? 0
                            text: modelData
                            color: Theme.primaryContainer
                            textColor: Theme.onPrimaryContainer
                            tooltipText: truncated ? modelData : null
                        }
                    }
                }

                Repeater {
                    model: ext.expanded ? root.list.matchesOf(ext.modelData) : []

                    delegate: StyledText {
                        required property var modelData
                        width: parent.width
                        text: "• " + (root.list.chips(modelData).join("   ·   ") || I18n.tr("Any window"))
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }

                StyledText {
                    width: parent.width
                    visible: ext.expanded
                    text: I18n.tr("Source: %1", "window rule detail, %1 is the config file path").arg(ext.modelData.source || "")
                    elide: Text.ElideMiddle
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
