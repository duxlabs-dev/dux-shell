import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Column {
    id: root

    required property var pane

    readonly property var pick: pane.pick
    readonly property bool freeKey: !!pick?.key && pane.origin === "all"

    topPadding: Theme.spacingXL
    spacing: Theme.spacingS

    DIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        name: root.freeKey ? "check_circle" : root.pick ? "filter_alt_off" : "touch_app"
        size: Theme.iconSizeLarge
        color: root.freeKey ? Theme.success : Theme.outline
    }

    StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
        text: {
            if (KeybindsService.loading)
                return I18n.tr("Loading keybinds...");
            if (root.freeKey)
                return I18n.tr("Nothing on this key yet", "niri keybinds pane, the picked key is free");
            if (root.pick)
                return I18n.tr("No shortcut here", "niri keybinds pane, nothing matches the pick and filter");
            return I18n.tr("Click a key", "niri keybinds pane, nothing picked yet");
        }
    }

    StyledText {
        visible: !root.pick && !KeybindsService.loading
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        text: I18n.tr("or a category, to see its shortcuts", "niri keybinds pane hint, follows Click a key")
    }

    DButton {
        visible: root.freeKey && !KeybindsService.readOnly
        anchors.horizontalCenter: parent.horizontalCenter
        text: I18n.tr("New shortcut here", "niri keybinds pane, add a shortcut on the free key")
        iconName: "add"
        backgroundColor: Theme.primary
        textColor: Theme.onPrimary
        onClicked: root.pane.openNew(root.pick.key)
    }

    DButton {
        visible: !!root.pick && root.pane.origin !== "all"
        anchors.horizontalCenter: parent.horizontalCenter
        text: I18n.tr("Show all", "niri keybinds pane, clear the origin filter")
        onClicked: root.pane.origin = "all"
    }
}
