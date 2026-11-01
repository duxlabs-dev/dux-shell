pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

// The ⋯ tools: packs, export, doubles, origin filter, cheatsheet, unused
Column {
    id: root

    // A URL loader item cannot take required properties: safe default, fed by Binding from BindsPane
    property var pane: null

    readonly property var origins: ["all", "dms", "niri"]
    readonly property var doubleKeys: pane?.doubleKeys ?? []

    spacing: Theme.spacingXS

    component MenuEntry: Rectangle {
        id: entry

        property string icon: ""
        property string text: ""
        property string trailing: "chevron_right"
        property string count: ""
        property bool active: true
        signal clicked

        width: root.width
        height: Theme.buttonHeightS
        radius: Theme.cornerRadiusM
        color: area.containsMouse && active ? Theme.surfaceTextHover : "transparent"
        opacity: active ? 1 : 0.5
        activeFocusOnTab: active
        Accessible.role: Accessible.MenuItem
        Accessible.name: text
        Keys.onReturnPressed: entry.clicked()
        Keys.onEnterPressed: entry.clicked()
        Keys.onSpacePressed: entry.clicked()

        FocusRing {}

        DIcon {
            id: lead
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: entry.icon
            size: Theme.iconSizeMedium
            color: Theme.surfaceVariantText
        }

        StyledText {
            anchors.left: lead.right
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            text: entry.text
            color: Theme.surfaceText
        }

        StyledText {
            anchors.right: tail.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: entry.count
            font.weight: Theme.fontWeightBold
            color: Theme.primary
        }

        DIcon {
            id: tail
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            visible: entry.trailing !== ""
            name: entry.trailing
            size: Theme.iconSizeSmall
            color: Theme.surfaceVariantText
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: entry.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: entry.active
            onClicked: entry.clicked()
        }
    }

    MenuEntry {
        icon: "inventory_2"
        text: I18n.tr("Packs", "niri keybinds pane, ready-made sets of shortcuts")
        active: !KeybindsService.readOnly
        onClicked: {
            if (root.pane)
                root.pane.mode = "packs";
        }
    }

    MenuEntry {
        icon: "ios_share"
        text: I18n.tr("Export", "niri keybinds pane, save the shortcuts as a sheet")
        onClicked: {
            if (root.pane)
                root.pane.mode = "export";
        }
    }

    MenuEntry {
        icon: "cleaning_services"
        text: root.doubleKeys.length > 0 ? I18n.tr("Clean up doubles", "niri keybinds, remove the extra binding of a key bound twice") : I18n.tr("No doubles", "niri keybinds, no key is bound twice")
        trailing: ""
        count: root.doubleKeys.length > 0 ? String(root.doubleKeys.length) : ""
        active: root.doubleKeys.length > 0 && !KeybindsService.readOnly
        onClicked: root.pane?.cleanDoubles()
    }

    MenuEntry {
        visible: KeybindsService.cheatsheetAvailable
        icon: "keyboard"
        text: I18n.tr("Cheatsheet", "button opening the keybinds cheatsheet overlay")
        trailing: "open_in_new"
        onClicked: PopoutService.showKeybindsModal()
    }

    MenuEntry {
        id: unused
        icon: "hourglass_empty"
        text: I18n.tr("Unused", "niri keybinds, shortcuts never pressed")
        trailing: "info"
        active: false

        HoverHandler {
            id: unusedHover
        }

        Loader {
            active: unusedHover.hovered
            sourceComponent: DTooltipHost {
                target: unused
                side: "top"
                text: I18n.tr("Needs usage info from niri", "niri keybinds, why Unused is greyed out")
                Component.onCompleted: Qt.callLater(schedule)
            }
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.outlineWidth
        color: Theme.outlineVariant
    }

    StyledText {
        topPadding: Theme.spacingS
        text: I18n.tr("Show", "niri keybinds origin filter label")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    DButtonGroup {
        arrowKeysSelect: false
        selectionMode: "single"
        size: "small"
        selectedColor: Theme.primaryContainer
        selectedContentColor: Theme.onPrimaryContainer
        model: [I18n.tr("All"), "DMS", I18n.tr("niri config", "niri keybinds origin filter, binds from config.kdl")]
        currentIndex: root.origins.indexOf(root.pane?.origin)
        onSelectionChanged: (index, selected) => {
            if (selected && root.pane)
                root.pane.origin = root.origins[index];
        }
    }
}
