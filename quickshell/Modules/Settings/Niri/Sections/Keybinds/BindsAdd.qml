pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Settings.Widgets
import "../../../../../Common/KeyUtils.js" as KeyUtils
import "../../../../../Common/niri/keymaps.js" as Keymaps

// Guided add without KDL: what it does, then the keys, with the clash and free keys shown live
Column {
    id: root

    // A URL loader item cannot take required properties: safe defaults, fed by Binding from BindsPane
    property var groups: []
    property string key: ""
    // {label, action} once step 1 is done
    property var what: null
    property bool _altShiftGhost: false

    readonly property var clash: key ? (groups ?? []).filter(g => g.action !== what?.action && g.keys.some(k => same(k.key, key))) : []
    // dms keybinds set replaces a key in dms/binds.kdl, but cannot touch one from config.kdl
    readonly property bool blocked: clash.some(g => g.keys.some(k => same(k.key, key) && k.source === "config"))
    readonly property var freeKeys: {
        if (!key || clash.length === 0)
            return [];
        const prefix = key.split("+").slice(0, -1).join("+");
        const free = [];
        for (const letter of "ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
            const chord = (prefix ? prefix + "+" : "") + letter;
            if (!(groups ?? []).some(g => g.keys.some(k => same(k.key, chord))))
                free.push(chord);
            if (free.length === 4)
                break;
        }
        return free;
    }

    signal done

    function same(a, b) {
        return Keymaps.chordId(a, KeybindsService.modKey) === Keymaps.chordId(b, KeybindsService.modKey);
    }

    function capture(event) {
        event.accepted = true;
        switch (event.key) {
        case Qt.Key_Control:
        case Qt.Key_Shift:
        case Qt.Key_Alt:
        case Qt.Key_Meta:
        case Qt.Key_NumLock:
        case Qt.Key_CapsLock:
        case Qt.Key_ScrollLock:
            return;
        }
        // Alt+Shift arrives as a key 0 press first; the next key must keep Shift (same trap as KeybindEditorDialog)
        if (event.key === 0 && (event.modifiers & Qt.AltModifier)) {
            _altShiftGhost = true;
            return;
        }
        const mods = KeyUtils.modsFromEvent(event.modifiers);
        if (_altShiftGhost && (event.modifiers & Qt.AltModifier) && !mods.includes("Shift"))
            mods.push("Shift");
        _altShiftGhost = false;
        const token = KeyUtils.chordToken(event.key, event.modifiers, mods, event.nativeScanCode, KeybindsService.modKey, KeybindsService.modSymbol);
        if (token)
            key = token;
    }

    function save() {
        if (!what || !key || blocked)
            return;
        KeybindsService.saveBind("", {
            "key": key,
            "action": what.action,
            "desc": what.label
        });
        done();
    }

    spacing: Theme.spacingM

    // Step 1: what
    BindsAddPick {
        visible: !root.what
        width: parent.width
        onChosen: item => {
            root.what = item;
            captureBox.forceActiveFocus();
        }
    }

    // Step 2: keys
    Row {
        visible: !!root.what
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - back.width - parent.spacing
            text: root.what?.label ?? ""
            elide: Text.ElideRight
            font.weight: Theme.fontWeightBold
            color: Theme.surfaceText
        }

        DButton {
            id: back
            text: I18n.tr("Other action", "niri keybinds guided add, back to step 1")
            iconName: "arrow_back"
            onClicked: root.what = null
        }
    }

    Rectangle {
        id: captureBox
        visible: !!root.what
        width: parent.width
        height: Theme.buttonHeightM
        radius: Theme.cornerRadiusM
        color: "transparent"
        border.width: activeFocus ? Theme.outlineWidthFocused : Theme.outlineWidth
        border.color: activeFocus ? Theme.primary : Theme.outline
        activeFocusOnTab: true
        Accessible.role: Accessible.EditableText
        Accessible.name: I18n.tr("Press the new shortcut", "niri keybinds guided add, key capture box")
        Keys.onPressed: event => root.capture(event)

        // Without it niri would run Super+key instead of handing it to the capture box
        ShortcutInhibitor {
            window: root.QsWindow.window
            enabled: captureBox.activeFocus
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingM

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "keyboard"
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.key || I18n.tr("Press keys…", "niri keybinds guided add, empty capture box")
                font.family: root.key ? Theme.monoFontFamily : Theme.fontFamily
                font.pixelSize: Theme.fontSizeLarge
                color: root.key ? Theme.surfaceText : Theme.surfaceVariantText
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: captureBox.forceActiveFocus()
        }
    }

    Rectangle {
        visible: !!root.what && root.key !== ""
        width: parent.width
        height: result.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadiusM
        color: root.clash.length === 0 ? Theme.withAlpha(Theme.success, 0.15) : Theme.withAlpha(root.blocked ? Theme.error : Theme.warning, 0.15)

        Column {
            id: result
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.surfaceText
                text: {
                    if (root.clash.length === 0)
                        return I18n.tr("Free", "niri keybinds, a key with no shortcut");
                    const name = root.clash[0].desc || KeybindsService.getActionLabel(root.clash[0].action);
                    if (root.blocked)
                        return I18n.tr("Used by %1 in config.kdl. Pick another key.", "niri keybinds guided add clash, %1 is the action").arg(name);
                    return I18n.tr("Used by %1. Save replaces it.", "niri keybinds guided add clash, %1 is the action").arg(name);
                }
            }

            Flow {
                visible: root.freeKeys.length > 0
                width: parent.width
                spacing: Theme.spacingXS

                StyledText {
                    text: I18n.tr("Free:", "niri keybinds guided add, label before free key suggestions")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Repeater {
                    model: root.freeKeys

                    delegate: DButton {
                        required property string modelData
                        text: modelData
                        buttonHeight: Theme.buttonHeightXS
                        onClicked: root.key = modelData
                    }
                }
            }
        }
    }

    StyledText {
        visible: !!root.what && NiriPageService.expert
        width: parent.width
        text: root.what ? "bind " + (root.key || "…") + " { " + root.what.action + "; }" : ""
        elide: Text.ElideRight
        font.family: Theme.monoFontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    Row {
        visible: !!root.what
        spacing: Theme.spacingS

        DButton {
            text: I18n.tr("Save")
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            enabled: root.key !== "" && !root.blocked && !KeybindsService.saving
            onClicked: root.save()
        }

        DButton {
            text: I18n.tr("Cancel")
            onClicked: root.done()
        }
    }
}
