import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root

    required property var pane

    readonly property var pick: pane.pick
    readonly property string mode: pane.mode
    readonly property int count: pane.listed.length
    readonly property string originText: pane.origin === "all" ? "" : " · " + (pane.origin === "dms" ? "DMS" : "niri")
    readonly property string icon: {
        switch (mode) {
        case "new":
            return "add_circle";
        case "menu":
            return "more_horiz";
        case "packs":
            return "inventory_2";
        case "export":
            return "ios_share";
        }
        return pick ? (pick.key ? "keyboard" : "category") : "touch_app";
    }
    readonly property string title: {
        switch (mode) {
        case "new":
            return I18n.tr("New shortcut", "niri keybinds pane title of the guided add");
        case "menu":
            return I18n.tr("More", "niri keybinds pane title of the more menu");
        case "packs":
            return I18n.tr("Packs", "niri keybinds pane, ready-made sets of shortcuts");
        case "export":
            return I18n.tr("Export", "niri keybinds pane, save the shortcuts as a sheet");
        }
        if (!pick)
            return I18n.tr("Shortcuts");
        return pick.key || pick.category || "";
    }
    readonly property string subtitle: {
        switch (mode) {
        case "packs":
            return I18n.tr("Hover to see the keys", "niri keybinds packs subtitle");
        case "export":
            return I18n.tr("One sheet, by category", "niri keybinds export subtitle");
        case "new":
        case "menu":
            return "";
        }
        if (!pick)
            return I18n.tr("Click a key or a category", "niri keybinds pane hint when nothing is picked");
        if (pick.key && count === 0)
            return I18n.tr("Free", "niri keybinds, a key with no shortcut") + originText;
        return (count === 1 ? I18n.tr("1 shortcut", "niri keybinds count, singular") : I18n.tr("%1 shortcuts", "niri keybinds count, plural").arg(count)) + originText;
    }

    implicitHeight: Math.max(Theme.iconButtonSize, texts.implicitHeight)
    height: implicitHeight

    Rectangle {
        id: plate
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.iconButtonSize
        height: width
        radius: Theme.cornerRadiusM
        color: root.pick || root.mode !== "" ? Theme.primaryContainer : Theme.surfaceContainerHigh

        DIcon {
            anchors.centerIn: parent
            name: root.icon
            size: Theme.iconSizeMedium
            color: root.pick || root.mode !== "" ? Theme.onPrimaryContainer : Theme.surfaceVariantText
        }
    }

    Column {
        id: texts
        anchors.left: plate.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: buttons.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightBold
            font.family: root.pick?.key && root.mode === "" ? Theme.monoFontFamily : Theme.fontFamily
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            visible: text !== ""
            text: root.subtitle
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Row {
        id: buttons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        DButton {
            visible: root.mode === "" && !KeybindsService.readOnly
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("New", "niri keybinds button that adds a shortcut")
            iconName: "add_circle"
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            onClicked: root.pane.openNew(root.pick?.key ?? "")
        }

        DActionButton {
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightS
            iconName: "more_horiz"
            iconColor: root.mode === "menu" ? Theme.onPrimaryContainer : Theme.surfaceText
            backgroundColor: root.mode === "menu" ? Theme.primaryContainer : "transparent"
            tooltipText: I18n.tr("More: packs, export, doubles, filter", "niri keybinds more button")
            Accessible.name: tooltipText

            // A dot says the origin filter hides some shortcuts
            Rectangle {
                visible: root.pane.origin !== "all"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacingXS
                width: Theme.spacingS
                height: width
                radius: width / 2
                color: Theme.primary
            }

            onClicked: root.pane.mode = root.mode === "menu" ? "" : "menu"
        }

        DActionButton {
            visible: root.mode !== "" || root.pick !== null
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: Theme.buttonHeightS
            iconName: "close"
            iconColor: Theme.surfaceText
            tooltipText: I18n.tr("Close")
            Accessible.name: tooltipText
            onClicked: root.pane.close()
        }
    }
}
