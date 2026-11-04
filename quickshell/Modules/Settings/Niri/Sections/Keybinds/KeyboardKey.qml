pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Keys
import "../../../../../Common/niri/keymaps.js" as Keymaps

// One keycap. A key with `sym` takes binds, one with `mod` toggles a layer, `super` shows the maker logo.
Rectangle {
    id: root

    property var key: ({})
    property string chord: ""
    property var binds: []
    property color tint: "transparent"
    // Icon colour, already pulled toward the text colour by the card for contrast
    property color line: Theme.surfaceText
    property string icon: ""
    property bool down: false
    property bool selected: false
    property bool dimmed: false
    property bool showNames: false
    required property color keycap
    required property color keycapDim

    readonly property bool bindable: key.sym !== undefined
    readonly property bool active: bindable || !!key.mod || key.super === true
    readonly property bool clash: binds.length > 1
    readonly property bool taken: binds.length > 0
    readonly property bool compact: height < Theme.buttonHeightXS
    readonly property string name: clash ? I18n.tr("%1 actions").arg(binds.length) : taken ? (binds[0].desc || binds[0].action) : ""

    signal picked
    signal held(bool on)

    function activate() {
        if (key.super)
            held(!showNames);
        else
            picked();
    }

    radius: compact ? Theme.cornerRadiusXS : Theme.cornerRadiusS
    color: down || key.super ? Theme.primaryContainer : clash ? Theme.errorContainer : taken ? tint : bindable ? keycap : keycapDim
    // The Super cap is tinted even at rest: only a pressed edge says it is really down
    border.width: selected ? Theme.outlineWidthFocused : (down && key.super) ? Theme.outlineWidth : 0
    border.color: Theme.surfaceText
    opacity: dimmed ? 0.3 : 1
    activeFocusOnTab: active

    Accessible.role: key.mod || bindable ? Accessible.Button : Accessible.StaticText
    Accessible.name: key.super ? I18n.tr("Super. Press and hold to see every key") : key.mod ? I18n.tr("%1 layer").arg(key.mod) : bindable ? chord + ": " + (name || I18n.tr("Free", "niri keybinds, a key with no shortcut")) : key.label
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onSpacePressed: activate()

    StyledText {
        id: letter

        readonly property bool corner: root.taken && visible && text !== ""

        // Taken keys keep their letter small in the corner, the icon sits under it.
        x: root.taken && !root.compact ? Theme.spacingXS + Theme.spacingXXS : (parent.width - width) / 2
        y: root.taken && !root.compact ? Theme.spacingXXS : (parent.height - height) / 2
        visible: !root.key.super && (!root.taken || (!root.compact && !root.showNames))
        text: root.key.label ?? ""
        font.family: root.taken ? Theme.monoFontFamily : font.family
        font.pixelSize: root.taken || !root.bindable || root.compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
        font.weight: root.bindable && !root.taken ? Font.Medium : Font.Normal
        color: root.down ? Theme.onPrimaryContainer : Theme.surfaceText
    }

    DIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: letter.corner ? letter.height / 2 : 0
        visible: root.taken && !root.showNames
        name: root.clash ? "error" : root.icon
        size: Math.round(root.height * (letter.corner ? 0.4 : 0.46))
        color: root.clash ? Theme.blend(Theme.error, Theme.surfaceText, 0.5) : root.line
    }

    StyledText {
        id: names

        readonly property string cap: Keymaps.capName(root.name)
        // Whole words shrink down to the 11 px readability floor; a word still wider than the cap
        // there breaks anywhere at the floor instead of spilling onto the neighbours
        readonly property bool wordsFit: widest.advanceWidth <= width

        anchors.fill: parent
        anchors.margins: Theme.spacingXXS
        visible: root.taken && root.showNames
        text: cap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: wordsFit ? Text.WordWrap : Text.Wrap
        maximumLineCount: root.compact ? 2 : 3
        elide: Text.ElideRight
        fontSizeMode: Text.Fit
        minimumPixelSize: Math.round(Theme.fontScale * 11)
        font.pixelSize: wordsFit ? Theme.fontSizeSmall : minimumPixelSize
        lineHeight: 0.9
        color: Theme.surfaceText

        TextMetrics {
            id: widest

            font.family: names.font.family
            font.pixelSize: names.minimumPixelSize
            text: names.cap.split(" ").reduce((a, b) => b.length > a.length ? b : a, "")
        }
    }

    SuperKeyLogo {
        anchors.centerIn: parent
        visible: root.key.super === true
        size: Math.round(root.height * 0.6)
        color: Theme.onPrimaryContainer
    }

    FocusRing {}

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.active
        hoverEnabled: root.bindable
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
        onPressAndHold: {
            if (root.key.super)
                root.held(true);
        }
        onReleased: {
            if (root.key.super)
                root.held(false);
        }
    }

    Loader {
        active: root.bindable && (mouse.containsMouse || root.activeFocus) && !root.showNames
        sourceComponent: DTooltipHost {
            target: root
            side: "top"
            text: (root.name || I18n.tr("Free", "niri keybinds, a key with no shortcut")) + " · " + root.chord
            Component.onCompleted: Qt.callLater(schedule)
        }
    }
}
