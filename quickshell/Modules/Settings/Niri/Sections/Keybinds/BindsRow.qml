import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

// One key of one action: the old tab's row, plus origin, doubles, Test
Item {
    id: root

    required property var group
    required property var keyData
    // "dms" or "niri"
    required property string origin

    readonly property string name: group.desc || KeybindsService.getActionLabel(group.action) || group.action || I18n.tr("No action")
    readonly property string tip: KeybindsService.getActionTip(group.action)
    // bindGroups splits a conflicted action per key: the pill counts the action's keys, not the entry's
    readonly property int sameCount: KeybindsService.keysForAction(group.action).length

    signal editRequested
    signal removeRequested

    implicitHeight: Math.max(Theme.listItemHeight, texts.implicitHeight + Theme.spacingS * 2)

    HoverHandler {
        id: hover
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusM
        color: hover.hovered ? Theme.surfaceTextHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
    }

    Column {
        id: texts
        x: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - acts.width - Theme.spacingS * 2
        spacing: Theme.spacingXXS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DKeycap {
                id: cap
                anchors.verticalCenter: parent.verticalCenter
                text: root.keyData.key
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - cap.width - parent.spacing
                text: root.name
                // A long action name wraps instead of truncating: the row grows, densities stay
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }

        StyledText {
            visible: root.tip !== ""
            width: parent.width
            text: I18n.tr(root.tip)
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        StyledText {
            visible: NiriPageService.expert
            width: parent.width
            text: root.group.action
            wrapMode: Text.WrapAnywhere
            elide: Text.ElideNone
            font.family: Theme.monoFontFamily
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Flow {
            id: tags
            width: parent.width
            spacing: Theme.spacingXS

            BindsTag {
                maximumWidth: tags.width
                icon: root.origin === "dms" ? "widgets" : "description"
                text: root.origin === "dms" ? "DMS" : "niri"
                tip: root.origin === "dms" ? "dms/binds.kdl" : "config.kdl"
            }

            BindsTag {
                maximumWidth: tags.width
                visible: root.sameCount > 1
                icon: "content_copy"
                text: I18n.tr("%1 do the same", "niri keybinds tag, how many keys run this action").arg(root.sameCount)
            }

            BindsTag {
                maximumWidth: tags.width
                visible: !!root.group.conflict
                icon: "error"
                text: I18n.tr("Overridden by config")
                warn: true
            }
        }
    }

    Row {
        id: acts
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingXS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXXS

        DActionButton {
            visible: KeybindsService.canExecuteAction(root.group.action)
            iconName: "play_arrow"
            tooltipText: I18n.tr("Test", "niri keybinds, run the action now")
            Accessible.name: tooltipText + ", " + root.name
            onClicked: KeybindsService.executeAction(root.group.action)
        }

        DActionButton {
            visible: !KeybindsService.readOnly
            iconName: "edit"
            tooltipText: I18n.tr("Edit")
            Accessible.name: tooltipText + ", " + root.name
            onClicked: root.editRequested()
        }

        DActionButton {
            visible: !KeybindsService.readOnly && (root.keyData.isDMSManaged || root.keyData.isOverride)
            iconName: "delete"
            iconColor: Theme.error
            tooltipText: I18n.tr("Delete")
            Accessible.name: tooltipText + ", " + root.keyData.key
            onClicked: root.removeRequested()
        }
    }
}
