pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

// One sheet of every shortcut by category, saved as a PNG in Pictures
Column {
    id: root

    // A URL loader item cannot take required properties: safe default, fed by Binding from BindsPane
    property var groups: []

    readonly property var categories: [...new Set((groups ?? []).map(g => g.category))]
    readonly property string path: Paths.strip(Paths.pictures) + "/niri-shortcuts.png"
    property string message: ""

    function save() {
        message = "";
        const started = sheet.grabToImage(result => {
            root.message = result.saveToFile(root.path) ? I18n.tr("Saved to %1", "niri keybinds export, %1 is the file path").arg(root.path) : I18n.tr("Could not save %1", "niri keybinds export, %1 is the file path").arg(root.path);
        });
        if (!started)
            message = I18n.tr("Could not save %1", "niri keybinds export, %1 is the file path").arg(path);
    }

    spacing: Theme.spacingM

    Rectangle {
        id: sheet
        width: parent.width
        height: flow.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadiusM
        color: Theme.surface
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant

        Flow {
            id: flow
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingM

            Repeater {
                model: root.categories

                delegate: Column {
                    id: block

                    required property string modelData
                    readonly property var binds: (root.groups ?? []).filter(g => g.category === modelData)

                    width: (flow.width - flow.spacing) / 2
                    spacing: Theme.spacingXXS

                    StyledText {
                        width: parent.width
                        text: block.modelData
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.primary
                    }

                    Repeater {
                        model: block.binds

                        delegate: Row {
                            id: line

                            required property var modelData

                            width: block.width
                            spacing: Theme.spacingXS

                            StyledText {
                                id: keyText
                                text: line.modelData.keys.map(k => k.key).join(" ")
                                font.family: Theme.monoFontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                            }

                            StyledText {
                                width: Math.max(0, line.width - keyText.width - line.spacing)
                                text: line.modelData.desc || KeybindsService.getActionLabel(line.modelData.action)
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }

    Row {
        spacing: Theme.spacingM

        DButton {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Save image", "niri keybinds export button")
            iconName: "download"
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            onClicked: root.save()
        }
    }

    StyledText {
        visible: root.message !== ""
        width: parent.width
        wrapMode: Text.WrapAnywhere
        text: root.message
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
