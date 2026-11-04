pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "../../../../../Common/niri/keymaps.js" as Keymaps

// While a real chord is held: the pressed caps, the action it would run, its description, and a
// small animation of the effect. Pure overlay: it never takes focus nor keys, so the page keeps
// working under it, and it stays ~600 ms after the release before it goes away.
Rectangle {
    id: root

    required property KeyboardCard board

    // True while the chord is really held. The shown* properties keep the last chord during the
    // close delay, so the card does not empty itself the instant a key goes up.
    readonly property bool chord: board.holding && board.chordKey !== ""
    readonly property string chordId: chord ? Keymaps.chordId(board.heldLayer + "+" + board.chordKey, board.modKey) : ""

    property bool open: false
    property var shownCaps: []
    property var shownBinds: []

    readonly property var bind: shownBinds.length ? shownBinds[0] : null
    readonly property string actionName: bind ? (KeybindsService.getActionLabel(bind.action) || bind.action) : I18n.tr("Free", "niri keybinds, a key with no shortcut")
    readonly property string actionDesc: bind ? (bind.desc || "") : ""
    readonly property string category: bind ? bind.category : ""

    // What the animation draws, from the action's family: a window closes, a column slides,
    // a layout resizes, a tile lights up, or a launcher/system icon pops.
    readonly property string family: bind ? familyOf(bind.category) : ""
    readonly property string animIcon: category === "System" ? "power_settings_new" : "rocket_launch"

    function familyOf(category) {
        switch (category) {
        case "Workspace":
            return "workspace";
        case "Layout":
            return "layout";
        case "Focus":
        case "Monitor":
            return "focus";
        case "Execute":
        case "System":
        case "DMS":
            return "icon";
        default:
            return "window";
        }
    }

    onChordIdChanged: {
        if (!chord) {
            if (open)
                closeTimer.restart();
            return;
        }
        shownCaps = board.heldLayer.split("+").concat([board.chordKey]);
        shownBinds = board.bindsByChord[chordId] ?? [];
        closeTimer.stop();
        open = true;
    }

    radius: Theme.cornerRadiusL
    color: Theme.surfaceContainerHighest
    border.width: Theme.outlineWidth
    border.color: Theme.outlineVariant
    implicitHeight: content.implicitHeight + Theme.spacingL * 2
    opacity: open ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        enabled: !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: shownCaps.join("+") + (bind ? ": " + actionName : "")

    Timer {
        id: closeTimer

        interval: 600
        onTriggered: root.open = false
    }

    Column {
        id: content

        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingS

        // The caps held right now
        Flow {
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: root.shownCaps

                DKeycap {
                    required property string modelData

                    text: modelData
                }
            }
        }

        StyledText {
            width: parent.width
            text: root.actionName
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Theme.fontWeightBold
            color: root.bind ? Theme.surfaceText : Theme.primary
        }

        StyledText {
            width: parent.width
            visible: text !== ""
            text: root.actionDesc
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        ChordAnim {
            visible: root.bind !== null
            width: parent.width
            family: root.family
            animIcon: root.animIcon
        }
    }

    // A tiny desk, three columns of tiles, and one 0->1->0 motion that each family reads its own
    // way. The animation drives `anim` only: every animated look below stays a binding, so
    // stopping the loop anywhere leaves a coherent scene.
    component ChordAnim: Rectangle {
        id: scene

        property string family: "window"
        property string animIcon: "rocket_launch"
        property real anim: 0

        // The family gate factors: zero unless the chord is of that family
        readonly property real closeF: family === "window" ? anim : 0
        readonly property real slideF: family === "workspace" ? anim : 0
        readonly property real layoutF: family === "layout" ? anim : 0
        readonly property real glowF: family === "focus" ? anim : 0
        readonly property real popF: family === "icon" ? anim : 0
        readonly property real colW: (width - Theme.spacingXS * 4) / 3
        readonly property real tileH: (height - Theme.spacingXS * 2 - Theme.spacingXXS * 3) / 2

        height: Theme.buttonHeightM * 2
        radius: Theme.cornerRadiusM
        color: Theme.isLightMode ? Theme.surfaceContainerLow : Theme.surfaceContainerHigh
        clip: true

        SequentialAnimation {
            running: root.open && !SettingsData.reduceMotion && root.bind !== null
            loops: Animation.Infinite
            PauseAnimation {
                duration: 700
            }
            NumberAnimation {
                target: scene
                property: "anim"
                to: 1
                duration: Theme.mediumDuration
                easing.type: Theme.standardEasing
            }
            PauseAnimation {
                duration: 600
            }
            NumberAnimation {
                target: scene
                property: "anim"
                to: 0
                duration: Theme.shortDuration
            }
        }

        Rectangle {
            id: colA

            x: Theme.spacingXS
            y: Theme.spacingXS
            width: scene.colW * (1 + 0.4 * scene.layoutF)
            height: parent.height - Theme.spacingXS * 2
            radius: Theme.cornerRadiusXS
            color: Theme.surfaceContainerHighest

            // A window closes: shrink and fade the tile the chord acts on
            Rectangle {
                x: Theme.spacingXXS
                y: Theme.spacingXXS
                width: parent.width - Theme.spacingXXS * 2
                height: scene.tileH
                radius: Theme.cornerRadiusXS
                color: Theme.surfaceContainerHigh
            }

            Rectangle {
                x: Theme.spacingXXS
                y: parent.height - Theme.spacingXXS - scene.tileH
                width: parent.width - Theme.spacingXXS * 2
                height: scene.tileH
                radius: Theme.cornerRadiusXS
                color: Theme.surfaceContainerHigh
            }
        }

        Rectangle {
            id: colB

            // A workspace slides away under the others
            x: colA.x + colA.width + Theme.spacingXS - scene.slideF * (scene.colW + Theme.spacingXS)
            y: Theme.spacingXS
            width: scene.colW * (1 - 0.4 * scene.layoutF)
            height: parent.height - Theme.spacingXS * 2
            radius: Theme.cornerRadiusXS
            color: Theme.surfaceContainerHighest

            Rectangle {
                x: Theme.spacingXXS
                y: Theme.spacingXXS
                width: parent.width - Theme.spacingXXS * 2
                height: scene.tileH
                radius: Theme.cornerRadiusXS
                color: Theme.surfaceContainerHigh
            }

            // Focus: this is the tile that lights up
            Rectangle {
                id: bTile

                x: Theme.spacingXXS
                y: parent.height - Theme.spacingXXS - scene.tileH
                width: parent.width - Theme.spacingXXS * 2
                height: scene.tileH
                radius: Theme.cornerRadiusXS
                color: Theme.blend(Theme.surfaceContainerHigh, Theme.primaryContainer, scene.glowF)
                scale: 1 - 0.95 * scene.closeF
                opacity: 1 - scene.closeF
            }
        }

        Rectangle {
            id: colC

            x: parent.width - Theme.spacingXS - scene.colW
            y: Theme.spacingXS
            width: scene.colW
            height: parent.height - Theme.spacingXS * 2
            radius: Theme.cornerRadiusXS
            color: Theme.surfaceContainerHighest

            Rectangle {
                x: Theme.spacingXXS
                y: Theme.spacingXXS
                width: parent.width - Theme.spacingXXS * 2
                height: scene.tileH
                radius: Theme.cornerRadiusXS
                color: Theme.surfaceContainerHigh
            }

            Rectangle {
                x: Theme.spacingXXS
                y: parent.height - Theme.spacingXXS - scene.tileH
                width: parent.width - Theme.spacingXXS * 2
                height: scene.tileH
                radius: Theme.cornerRadiusXS
                color: Theme.surfaceContainerHigh
            }
        }

        // A launcher or system chord: an icon pops in
        DIcon {
            anchors.centerIn: parent
            name: scene.animIcon
            size: Theme.iconSizeLarge
            color: Theme.primary
            scale: 0.7 + 0.3 * scene.popF
            opacity: SettingsData.reduceMotion ? scene.family === "icon" ? 1 : 0 : scene.popF
        }
    }
}
