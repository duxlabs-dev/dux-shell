pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

SettingsRow {
    id: root

    required property var bindData
    property bool firstInGroup: false
    property bool lastInGroup: false
    property bool readOnly: false

    readonly property var keys: bindData.keys || []
    readonly property bool hasConfigConflict: !!bindData.conflict
    readonly property bool hasOverride: keys.some(key => key.isOverride)
    readonly property string statusText: {
        if (hasConfigConflict)
            return I18n.tr("Overridden by config");
        if (hasOverride)
            return I18n.tr("Override", "noun, badge on a keybind that overrides the default", true);
        return "";
    }
    readonly property string releaseText: bindData.releaseAction ? I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release") + ": " + (KeybindsService.getActionLabel(bindData.releaseAction) || bindData.releaseAction) : ""

    signal editRequested(int keyIndex)
    signal removeRequested(string key)

    title: bindData.desc || bindData.action || I18n.tr("No action")
    singleLineTitle: true
    subtitle: [bindData.category || "", releaseText, statusText].filter(part => part !== "").join(" · ")
    subtitleColor: hasConfigConflict ? Theme.primary : Theme.surfaceVariantText
    topRadius: firstInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius
    bottomRadius: lastInGroup ? Theme.groupedListOuterRadius : Theme.groupedListInnerRadius

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        Repeater {
            model: root.keys

            delegate: Row {
                id: keyLine

                required property var modelData
                required property int index
                readonly property bool removable: modelData.isDMSManaged || modelData.isOverride

                anchors.right: parent?.right
                spacing: Theme.spacingS

                Loader {
                    active: keyLine.modelData.trigger === "release"
                    visible: active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: DBadge {
                        text: I18n.tr("Release", "noun, hyprland bind flag toggle, trigger on key release")
                        color: Theme.primaryHover
                        textColor: Theme.primary
                    }
                }

                DKeycap {
                    text: keyLine.modelData.key
                    anchors.verticalCenter: parent.verticalCenter
                }

                DActionButton {
                    iconName: "edit"
                    Accessible.name: I18n.tr("Edit")
                    Accessible.description: root.title + ", " + keyLine.modelData.key
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.editRequested(keyLine.index)
                }

                Item {
                    width: deleteButton.width
                    height: deleteButton.height
                    visible: !root.readOnly
                    anchors.verticalCenter: parent.verticalCenter

                    DActionButton {
                        id: deleteButton
                        iconName: "delete"
                        iconColor: Theme.error
                        Accessible.name: I18n.tr("Delete")
                        Accessible.description: root.title + ", " + keyLine.modelData.key
                        visible: keyLine.removable
                        onClicked: root.removeRequested(keyLine.modelData.key)
                    }
                }
            }
        }
    }
}
