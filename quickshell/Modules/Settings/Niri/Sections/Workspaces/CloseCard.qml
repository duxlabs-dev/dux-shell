import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.Niri.Components

NiriCard {
    id: root

    readonly property string bindAction: "spawn dms ipc call workspace closeAll"
    readonly property string modKey: KeybindsService.modKey || "Super"
    readonly property var bindKeys: {
        KeybindsService.displayList;
        return KeybindsService.keysForAction(bindAction).map(key => root.printKey(key));
    }
    readonly property bool neverAsk: NiriPageService.get("close.neverAsk") === true
    readonly property int askFromMax: 50
    readonly property int focusedCount: NiriWorkspaceActions.focusedWindowIds().length

    icon: "delete_sweep"
    title: I18n.tr("Close a whole workspace", "niri page card")
    aside: I18n.tr("By DMS", "niri page chip: a feature DMS adds on top of niri")

    Component.onCompleted: {
        KeybindsService.addRef();
        if (KeybindsService.available)
            KeybindsService.loadBinds(false);
    }
    Component.onDestruction: KeybindsService.removeRef()

    // The bind store spells the modifier "Mod"; the card shows the key it stands for.
    function printKey(key) {
        return String(key).split("+").map(part => part.toLowerCase() === "mod" ? root.modKey : part).join("+");
    }

    NiriRow {
        icon: "keyboard"
        title: I18n.tr("Shortcut")
        tip: I18n.tr("Closes every window on the focused workspace")

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: keyText.implicitWidth + Theme.spacingS * 2
            height: keyText.implicitHeight + Theme.spacingXS * 2
            radius: Theme.cornerRadiusS
            color: SettingsMetrics.controlColor

            StyledText {
                id: keyText
                anchors.centerIn: parent
                text: root.bindKeys.length ? root.bindKeys.join(", ") : I18n.tr("None", "no keyboard shortcut set")
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }
        }

        DButton {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Change")
            onClicked: SettingsUiState.niriSection = "keybinds"
        }
    }

    NiriRow {
        id: askRow

        settingKey: "close.askFrom"
        icon: "help"
        title: I18n.tr("Ask from", "niri page: confirm closing from this many windows")
        tip: root.neverAsk ? I18n.tr("Off while Never ask is on") : I18n.tr("Number of windows. 0 always asks")
        toggle: false
        tryValue: undefined
        // Field plus unit as one control, so a stacked row keeps room for both
        controlWidth: numberField.width + Theme.spacingS + unitLabel.implicitWidth
        enabled: !root.neverAsk
        opacity: enabled ? 1 : SettingsMetrics.disabledOpacity

        DTextField {
            id: numberField

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconButtonSize * 2
            outlined: true
            text: String(askRow.value ?? 0)
            validator: IntValidator {
                bottom: 0
                top: root.askFromMax
            }
            Accessible.name: askRow.title
            onEditingFinished: {
                const next = Math.max(0, Math.min(root.askFromMax, parseInt(text, 10) || 0));
                if (next !== askRow.value)
                    askRow.write(next);
                // Shows the stored value again after an empty or out-of-range entry
                text = Qt.binding(() => String(askRow.value ?? 0));
            }
        }

        StyledText {
            id: unitLabel

            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Windows", "niri page: unit after the Ask from number")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    NiriRow {
        settingKey: "close.neverAsk"
        icon: "bolt"
        title: I18n.tr("Never ask")
        tip: I18n.tr("Closes right away, cannot be undone")
        tryValue: undefined
    }

    StyledText {
        width: parent.width
        topPadding: Theme.spacingS
        text: root.focusedCount === 1 ? I18n.tr("Focused workspace: %1 window", "niri page, close whole workspace card; singular, %1 is 1").arg(1) : I18n.tr("Focused workspace: %1 windows", "niri page, close whole workspace card").arg(root.focusedCount)
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }
}
