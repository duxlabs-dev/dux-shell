pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets

Column {
    id: root

    // A URL loader item cannot take required properties: safe default, fed by Binding from BindsPane
    property var pane: null

    // [key, action, label]; labels stay English like the action catalog they come from
    readonly property var packs: [
        {
            "title": I18n.tr("Vim HJKL", "niri keybinds pack"),
            "icon": "keyboard",
            "set": [["Mod+H", "focus-column-left", "Focus Column Left"], ["Mod+J", "focus-window-down", "Focus Window Down"], ["Mod+K", "focus-window-up", "Focus Window Up"], ["Mod+L", "focus-column-right", "Focus Column Right"]]
        },
        {
            "title": I18n.tr("Arrows", "niri keybinds pack"),
            "icon": "keyboard_arrow_right",
            "set": [["Mod+Left", "focus-column-left", "Focus Column Left"], ["Mod+Right", "focus-column-right", "Focus Column Right"], ["Mod+Up", "focus-window-up", "Focus Window Up"], ["Mod+Down", "focus-window-down", "Focus Window Down"]]
        },
        {
            "title": I18n.tr("GNOME-like", "niri keybinds pack"),
            "icon": "grid_view",
            "set": [["Mod+A", "spawn dms ipc call spotlight toggle", "Launcher"], ["Mod+Up", "maximize-column", "Maximize Column"], ["Mod+V", "spawn dms ipc call notifications toggle", "Notifications"]]
        },
        {
            "title": I18n.tr("Hyprland-like", "niri keybinds pack"),
            "icon": "water_drop",
            "set": [["Mod+C", "close-window", "Close Window"], ["Mod+R", "spawn dms ipc call spotlight toggle", "Launcher"], ["Mod+V", "toggle-window-floating", "Toggle Floating"], ["Mod+M", "quit", "Quit"]]
        }
    ]
    property var hovered: null
    property var queue: []
    property bool applying: false

    function onKey(key) {
        const pane = root.pane;
        if (!pane)
            return [];
        return (pane.groups ?? []).filter(g => g.keys.some(k => pane.norm(k.key) === pane.norm(key)));
    }

    function changesOf(pack) {
        const pane = root.pane;
        if (!pane)
            return [];
        const out = [];
        for (const [key, action, label] of pack.set) {
            const cur = onKey(key);
            if (cur.length === 1 && cur[0].action === action)
                continue;
            out.push({
                "key": key,
                "action": action,
                "label": label,
                "before": cur.length ? (cur[0].desc || KeybindsService.getActionLabel(cur[0].action)) : "",
                // dms keybinds set cannot override a key from config.kdl
                "blocked": cur.some(g => g.keys.some(k => pane.norm(k.key) === pane.norm(key) && k.source === "config"))
            });
        }
        return out;
    }

    function apply(pack) {
        queue = changesOf(pack).filter(c => !c.blocked);
        applying = true;
        next();
    }

    function next() {
        if (queue.length === 0) {
            applying = false;
            if (root.pane)
                root.pane.mode = "";
            return;
        }
        const c = queue[0];
        queue = queue.slice(1);
        KeybindsService.saveBind("", {
            "key": c.key,
            "action": c.action,
            "desc": c.label
        });
    }

    // saveBind runs one process at a time, so a pack writes its keys one after the other
    Connections {
        target: KeybindsService
        enabled: root.applying
        function onBindSaveCompleted(success) {
            if (!success) {
                root.queue = [];
                root.applying = false;
                return;
            }
            root.next();
        }
    }

    spacing: Theme.spacingS

    Repeater {
        model: root.packs

        delegate: Rectangle {
            id: packItem

            required property var modelData
            readonly property var changes: root.changesOf(modelData)
            readonly property int writable: changes.filter(c => !c.blocked).length
            readonly property string summary: writable === 0 ? I18n.tr("Already in place", "niri keybinds pack, nothing to change") : writable === 1 ? I18n.tr("1 key changes", "niri keybinds pack, singular") : I18n.tr("%1 keys change", "niri keybinds pack, plural").arg(writable)
            readonly property bool usable: writable > 0 && !KeybindsService.saving

            function choose() {
                if (usable)
                    root.apply(modelData);
            }

            width: root.width
            height: Theme.listItemHeight
            radius: Theme.cornerRadiusM
            color: area.containsMouse || activeFocus ? Theme.surfaceTextHover : SettingsMetrics.controlColor
            opacity: writable > 0 ? 1 : 0.6
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.title + ", " + summary
            Keys.onReturnPressed: choose()
            Keys.onEnterPressed: choose()
            Keys.onSpacePressed: choose()
            // The keyboard previews a pack on focus, as the mouse does on hover
            onActiveFocusChanged: root.hovered = activeFocus ? changes : null

            FocusRing {}

            DIcon {
                id: packIcon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                name: packItem.modelData.icon
                color: Theme.primary
            }

            Column {
                anchors.left: packIcon.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                StyledText {
                    text: packItem.modelData.title
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                StyledText {
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    text: packItem.summary
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                enabled: packItem.usable
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: root.hovered = containsMouse ? packItem.changes : null
                onClicked: packItem.choose()
            }
        }
    }

    Repeater {
        model: root.hovered ?? []

        delegate: Row {
            id: change

            required property var modelData

            spacing: Theme.spacingS

            DKeycap {
                anchors.verticalCenter: parent.verticalCenter
                text: change.modelData.key
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: change.modelData.before || I18n.tr("Free", "niri keybinds, a key with no shortcut")
                font.strikeout: change.modelData.before !== ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: change.modelData.blocked ? "block" : "arrow_forward"
                size: Theme.iconSizeSmall
                color: change.modelData.blocked ? Theme.error : Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: change.modelData.blocked ? I18n.tr("kept, in config.kdl", "niri keybinds pack, a key the pack cannot change") : change.modelData.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }
        }
    }
}
