pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../../../../Common/niri/keymaps.js" as Keymaps

// The keybinds keyboard: the live xkb layout, keys coloured by category. Picking a key or a
// category fills SettingsUiState.niriKeyPick, the side pane lists its shortcuts.
FocusScope {
    id: root

    readonly property string modKey: KeybindsService.modKey || "Super"
    readonly property var bindsByChord: {
        KeybindsService._dataVersion;
        return Keymaps.bindMap(KeybindsService.getFlatBinds(), modKey);
    }
    readonly property var categories: {
        KeybindsService._dataVersion;
        return KeybindsService.getCategories();
    }
    readonly property var counts: {
        const out = {};
        for (const id in bindsByChord)
            for (const b of bindsByChord[id])
                out[b.category] = (out[b.category] ?? 0) + 1;
        return out;
    }
    readonly property string layoutName: NiriService.keyboardLayoutNames[NiriService.currentKeyboardLayoutIndex] ?? ""
    readonly property string layoutId: Keymaps.layoutOf(layoutName)
    readonly property var keyRows: Keymaps.rows(layoutId)

    // Layers keep the configured mod key first; a duplicate (Alt as mod, +Alt) is dropped.
    readonly property var layers: {
        const out = [];
        for (const extra of ["", "+Shift", "+Ctrl", "+Alt"]) {
            const l = modKey + extra;
            if (!out.some(o => Keymaps.chordId(o + "+x", modKey) === Keymaps.chordId(l + "+x", modKey)))
                out.push(l);
        }
        return out;
    }
    property string chosenLayer: modKey
    property bool holding: false
    property string heldLayer: ""
    property string chordKey: ""
    // Keys held right now, by drawn sym or printed label; the version counter re-runs the
    // delegates' down bindings on each change (a plain var map change notifies nothing).
    property var pressed: ({})
    property int pressVersion: 0
    readonly property string shownLayer: holding && heldLayer ? heldLayer : chosenLayer
    readonly property var shownMods: Keymaps.chordId(shownLayer + "+x", modKey).split("+")

    readonly property var pick: SettingsUiState.niriKeyPick
    readonly property string pickedChord: pick?.key ? Keymaps.chordId(pick.key, modKey) : ""
    readonly property string pickedCategory: pick && !pick.key ? (pick.category ?? "") : ""

    // A search pick can name a chord from another layer: show that layer so the key lights up,
    // like the mockup's setLayer(modOf(ch)). A bare key sits on every layer and changes nothing.
    onPickedChordChanged: {
        if (!pickedChord || holding)
            return;
        const layer = Keymaps.layerOf(pickedChord, layers, modKey);
        if (layer && layer !== chosenLayer)
            chosenLayer = layer;
    }

    readonly property real colW: deck.width > 0 ? (deck.width - Theme.spacingM * 2) / 60 : 0
    // Held: the names need every pixel, the caps close ranks
    readonly property real gap: colW * 4 < 30 || holding ? Theme.spacingXS : Theme.spacingS
    // Keys keep their shape and grow with the width the section gets, never under 32 px to stay clickable
    readonly property real keyH: Math.round(Math.max(Theme.buttonHeightXS,colW * 4 * 0.95) + (holding ? Theme.spacingS : 0))

    readonly property color keycap: Theme.isLightMode ? Theme.surfaceContainerLowest : Theme.surfaceContainerHighest
    readonly property color keycapDim: Theme.isLightMode ? Theme.surfaceContainerLow : Theme.surfaceContainerHigh
    readonly property var categoryColors: [Theme.primary, Theme.success, Theme.warning, Theme.tertiary, Theme.info, Theme.error, Theme.secondary]
    readonly property var icons: ({
            "DMS": "widgets",
            "Execute": "apps",
            "Workspace": "space_dashboard",
            "Tags": "sell",
            "Window": "select_window",
            "Move/Resize": "open_with",
            "Focus": "center_focus_strong",
            "Move": "drag_pan",
            "Layout": "view_column",
            "Groups": "tab",
            "Monitor": "monitor",
            "Scratchpad": "inventory_2",
            "Screenshot": "screenshot_region",
            "System": "power_settings_new",
            "Pass-through": "keyboard_tab",
            "Overview": "grid_view",
            "Alt-Tab": "tab",
            "Other": "more_horiz"
        })

    function lineOf(category) {
        const i = categories.indexOf(category);
        return categoryColors[Math.max(0, i) % categoryColors.length];
    }

    // Half way to the text colour keeps a category icon at 3:1 on its tint, light and dark
    function iconOf(category) {
        return Theme.blend(lineOf(category), Theme.surfaceText, 0.5);
    }

    function tintOf(category) {
        return Theme.blend(keycap, lineOf(category), 0.28);
    }

    function pickKey(chord, binds) {
        // A key picked from the keyboard keeps its focus; a click hands it to the card for Hold Super
        if (!root.activeFocus)
            root.forceActiveFocus();
        if (pickedChord === Keymaps.chordId(chord, modKey)) {
            SettingsUiState.niriKeyPick = null;
            return;
        }
        SettingsUiState.niriKeyPick = {
            "key": chord,
            "category": binds[0]?.category ?? ""
        };
    }

    function pickCategory(category) {
        SettingsUiState.niriKeyPick = pickedCategory === category ? null : {
            "key": "",
            "category": category
        };
    }

    function hold(on, layer) {
        holding = on;
        heldLayer = on ? layer : "";
        if (!on)
            chordKey = "";
    }

    // The drawn Super cap lights on a physical Super press whatever the configured Mod key
    function isSuper(key) {
        return key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta;
    }

    function isModifier(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt || key === Qt.Key_AltGr || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R;
    }

    // The drawn key a Qt key event lands on: letters and F-keys keep their names, the rest goes
    // through the few labels the board prints. "" for keys the board does not draw.
    function symOf(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z)
            return String.fromCharCode(key);
        if (key >= Qt.Key_F1 && key <= Qt.Key_F12)
            return "F" + (key - Qt.Key_F1 + 1);
        switch (key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            return "Return";
        case Qt.Key_Space:
            return "Space";
        case Qt.Key_Delete:
            return "Delete";
        case Qt.Key_Print:
            return "Print";
        case Qt.Key_Left:
            return "Left";
        case Qt.Key_Up:
            return "Up";
        case Qt.Key_Down:
            return "Down";
        case Qt.Key_Right:
            return "Right";
        case Qt.Key_Escape:
            return "esc";
        case Qt.Key_Tab:
            return "tab";
        case Qt.Key_CapsLock:
            return "caps";
        case Qt.Key_Shift:
            return "shift";
        case Qt.Key_Control:
            return "ctrl";
        case Qt.Key_Alt:
        case Qt.Key_AltGr:
            return "alt";
        }
        return "";
    }

    function isPressed(key) {
        pressVersion;
        if (key.super === true)
            return !!pressed["super"];
        if (key.sym !== undefined)
            return !!pressed[key.sym];
        if (key.label !== undefined)
            return !!pressed[key.label];
        return false;
    }

    function pressKey(event) {
        if (isSuper(event.key)) {
            pressed["super"] = true;
            pressVersion++;
            return;
        }
        const s = symOf(event.key);
        if (s !== "") {
            pressed[s] = true;
            pressVersion++;
        }
        // A key pressed while the mod key is really held is a chord: the overlay card opens
        if (holding && s !== "" && !isModifier(event.key))
            chordKey = s;
    }

    function releaseKey(event) {
        if (isSuper(event.key)) {
            delete pressed["super"];
            pressVersion++;
            return;
        }
        const s = symOf(event.key);
        if (s !== "") {
            delete pressed[s];
            pressVersion++;
        }
        if (s === chordKey)
            chordKey = "";
    }

    width: parent?.width ?? 0
    implicitHeight: content.implicitHeight
    focus: true

    Component.onCompleted: {
        KeybindsService.addRef();
        forceActiveFocus();
    }
    Component.onDestruction: KeybindsService.removeRef()

    // A fresh open lands the window focus on the modal scope, after this card's creation:
    // take the focus back whenever the window activates, so real key presses reach the card.
    readonly property bool windowActive: root.Window?.active ?? false
    onWindowActiveChanged: {
        if (windowActive && visible)
            forceActiveFocus();
    }

    // The real Mod key (Super or Alt, as niri is configured) holds its layer; Shift, Ctrl or Alt
    // meanwhile move to that layer; the Mod key up ends the hold.
    Keys.onPressed: event => {
        if (Keymaps.isModKey(event.key, modKey) || holding)
            hold(true, Keymaps.heldLayer(event.modifiers, modKey));
        pressKey(event);
    }
    Keys.onReleased: event => {
        releaseKey(event);
        if (!holding)
            return;
        if (Keymaps.isModKey(event.key, modKey))
            hold(false, "");
        else
            hold(true, Keymaps.heldLayer(event.modifiers, modKey));
    }

    Column {
        id: content

        width: parent.width
        spacing: Theme.spacingM

        KeyboardChips {
            width: parent.width
            board: root
        }

        Rectangle {
            id: deck

            width: parent.width
            height: keys.height + Theme.spacingM * 2
            radius: Theme.cornerRadiusL
            color: Theme.isLightMode ? Theme.surfaceContainerHighest : Theme.surfaceContainerLowest

            Column {
                id: keys

                // Margins equal on both sides: the keys span colW * 60 minus half a gap each
                // end, so the column starts at spacingM + gap / 2 and must sit at spacingM.
                x: Theme.spacingM
                y: Theme.spacingM
                spacing: root.gap

                Repeater {
                    model: root.keyRows

                    Item {
                        id: keyRow

                        required property var modelData
                        required property int index

                        width: root.colW * 60
                        height: index === 0 ? Math.round(root.keyH / 2) : root.keyH

                        Repeater {
                            model: keyRow.modelData

                            KeyboardKey {
                                id: keyItem

                                required property var modelData

                                readonly property string chordText: modelData.sym !== undefined ? root.shownLayer + "+" + modelData.sym : ""
                                readonly property string chordKey: chordText ? Keymaps.chordId(chordText, root.modKey) : ""

                                key: modelData
                                keycap: root.keycap
                                keycapDim: root.keycapDim
                                chord: chordText
                                binds: chordKey ? (root.bindsByChord[chordKey] ?? []) : []
                                tint: binds.length ? root.tintOf(binds[0].category) : "transparent"
                                line: binds.length ? root.iconOf(binds[0].category) : Theme.surfaceText
                                icon: binds.length ? (root.icons[binds[0].category] ?? "keyboard_command_key") : ""
                                down: root.isPressed(modelData) || (!!modelData.mod && root.shownMods.includes(modelData.mod.toLowerCase()))
                                selected: chordKey !== "" && chordKey === root.pickedChord
                                dimmed: root.pickedCategory !== "" && !!chordText && !binds.some(b => b.category === root.pickedCategory)
                                showNames: root.holding
                                x: modelData.col * root.colW + root.gap / 2
                                y: modelData.half === "bottom" ? keyRow.height - height : 0
                                width: modelData.w * root.colW - root.gap
                                height: modelData.half ? (keyRow.height - Theme.spacingXXS) / 2 : keyRow.height
                                onHeld: on => root.hold(on, root.modKey)
                                onPicked: {
                                    if (modelData.mod) {
                                        root.chosenLayer = down ? root.modKey : root.modKey + "+" + modelData.mod;
                                        return;
                                    }
                                    if (modelData.sym !== undefined)
                                        root.pickKey(chordText, binds);
                                }

                                // Half-height keys draw small but take clicks toward the 32 px target: their whole
                                // share of the cell, the row gaps and, on the deck edges, its padding. Under the key
                                // so its own hover, tooltip and press stay as they are.
                                MouseArea {
                                    readonly property bool half: !!keyItem.modelData.half
                                    readonly property bool fnRow: keyRow.index === 0
                                    readonly property bool edgeRow: fnRow || keyRow.index === root.keyRows.length - 1
                                    readonly property bool topFree: keyItem.modelData.half === "bottom" && !keyRow.modelData.some(k => k.half === "top" && k.col === keyItem.modelData.col)

                                    z: -1
                                    enabled: half || fnRow
                                    anchors.fill: parent
                                    anchors.leftMargin: -root.gap / 2
                                    anchors.rightMargin: -root.gap / 2
                                    anchors.topMargin: fnRow ? -Theme.spacingM : topFree ? -keyItem.y - root.gap / 2 : keyItem.modelData.half === "top" ? -root.gap : -Theme.spacingXXS / 2
                                    anchors.bottomMargin: fnRow ? -root.gap : keyItem.modelData.half === "bottom" ? -(root.gap / 2 + (edgeRow ? Theme.spacingM : 0)) : -Theme.spacingXXS / 2
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: keyItem.picked()
                                }
                            }
                        }
                    }
                }
            }
        }

        KeyboardFooter {
            width: parent.width
            board: root
        }
    }

    // The chord overlay: top-center above the keyboard, above everything else, never in the
    // focus chain, so the keys keep reaching the FocusScope while it is shown.
    NiriChordCard {
        board: root
        z: 100
        width: Math.min(root.width, 540)
        x: (root.width - width) / 2
    }
}
