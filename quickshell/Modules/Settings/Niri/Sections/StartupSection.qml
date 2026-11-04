pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Components
import "../../../../Common/niri/sections/startup.js" as Startup

// Expert only: startup apps live in DMS Autostart (linked from the Workspaces Session card).
Column {
    id: root

    readonly property string sectionId: "startup"
    // One NAME=value line in the KDL environment block
    readonly property int envMaxLength: 1024
    readonly property var env: NiriPageService.get("startup.env") ?? {}
    readonly property var envNames: Object.keys(env)
    readonly property var typed: Startup.parseEnv(envField.text)

    function addEnv() {
        if (!typed)
            return;
        const next = Object.assign({}, env);
        next[typed.name] = typed.value;
        NiriPageService.set("startup.env", next);
        envField.text = "";
    }

    function removeEnv(name) {
        const next = Object.assign({}, env);
        delete next[name];
        NiriPageService.set("startup.env", next);
    }

    spacing: Theme.spacingM

    NiriCard {
        icon: "terminal"
        title: I18n.tr("Environment", "niri page startup card")
        aside: I18n.tr("Next login", "niri page: the change applies at the next login")

        Row {
            width: parent.width
            spacing: Theme.spacingS
            bottomPadding: Theme.spacingS

            DIcon {
                name: "schedule"
                size: Theme.iconSizeSmall
                color: Theme.warning
            }

            StyledText {
                width: parent.width - x
                text: I18n.tr("Programs see a change only after the next login.", "niri page startup environment")
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Repeater {
            model: root.envNames

            Item {
                id: envRow

                required property string modelData

                width: parent.width
                height: Theme.listItemHeight

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - removeButton.width - Theme.spacingS
                    text: envRow.modelData + "=" + root.env[envRow.modelData]
                    elide: Text.ElideRight
                    font.family: Theme.monoFontFamily
                    color: Theme.surfaceText
                }

                DActionButton {
                    id: removeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "delete"
                    tooltipText: I18n.tr("Remove", "niri page startup environment")
                    Accessible.name: I18n.tr("Remove %1", "niri page startup environment, %1 is a variable name").arg(envRow.modelData)
                    onClicked: root.removeEnv(envRow.modelData)
                }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS
            topPadding: Theme.spacingS

            DTextField {
                id: envField
                width: parent.width - addButton.width - Theme.spacingS
                placeholderText: I18n.tr("NAME=value", "niri page startup environment placeholder")
                maximumLength: root.envMaxLength
                font.family: Theme.monoFontFamily
                isError: text !== "" && !root.typed
                supportingText: isError ? I18n.tr("Use NAME=value, letters, digits and _ in the name", "niri page startup environment") : ""
                onAccepted: root.addEnv()
            }

            DButton {
                id: addButton
                text: I18n.tr("Add", "niri page startup environment")
                iconName: "add"
                enabled: !!root.typed
                onClicked: root.addEnv()
            }
        }
    }
}
