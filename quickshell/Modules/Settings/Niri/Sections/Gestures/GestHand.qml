pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

// Finger dots or the mouse, with the Mod key when the gesture needs it. Its origin is the touch point.
Item {
    id: root

    property var spec: null
    property real tapIn: 0
    // 0..1 while the gesture drags: the pressed mouse button sinks (keycap pressed tint)
    property real pressIn: 0

    visible: spec !== null

    readonly property bool pad: spec?.dev === "pad"
    readonly property bool mouse: spec?.dev === "mouse"
    // Touchpad swipe direction, from `from` to `to`
    readonly property real dx: spec ? spec.to[0] - spec.from[0] : 0
    readonly property real dy: spec ? spec.to[1] - spec.from[1] : 0
    readonly property bool horiz: Math.abs(dx) > Math.abs(dy)
    readonly property string chevron: horiz ? (dx > 0 ? "keyboard_arrow_right" : "keyboard_arrow_left") : dy > 0 ? "keyboard_arrow_down" : "keyboard_arrow_up"
    readonly property bool swept: dx !== 0 || dy !== 0
    readonly property bool pressed: pressIn > 0

    component Chevron: DIcon {
        name: root.chevron
        size: Theme.iconSizeSmall
        color: Theme.surfaceVariantText
    }

    Row {
        id: dots

        visible: !root.mouse
        x: -width / 2
        y: -height / 2
        spacing: Theme.spacingXS

        Repeater {
            model: root.spec?.dev === "touch" ? 1 : (root.spec?.n ?? 0)

            Rectangle {
                width: root.spec?.dev === "touch" ? Theme.iconSizeMedium : Theme.spacingM
                height: width
                radius: width / 2
                color: Theme.primary
                border.width: Theme.outlineWidthFocused
                border.color: Theme.surface
            }
        }

        Rectangle {
            visible: root.spec?.tap === true
            width: Theme.iconSizeMedium
            height: width
            radius: width / 2
            color: Theme.primary
            border.width: Theme.outlineWidthFocused
            border.color: Theme.surface
            opacity: root.tapIn
            scale: root.tapIn
        }
    }

    // Discreet chevrons ahead of the dots: the swipe direction stays readable without noise
    Column {
        visible: root.pad && !root.horiz && root.swept
        anchors.horizontalCenter: dots.horizontalCenter
        y: root.dy < 0 ? dots.y - height - Theme.spacingXXS : dots.y + dots.height + Theme.spacingXXS
        spacing: Theme.spacingXXS

        Chevron {}
        Chevron {}
    }

    Row {
        visible: root.pad && root.horiz && root.swept
        anchors.verticalCenter: dots.verticalCenter
        x: root.dx > 0 ? dots.x + dots.width + Theme.spacingXXS : dots.x - width - Theme.spacingXXS
        spacing: Theme.spacingXXS

        Chevron {}
        Chevron {}
    }

    // A real three-button mouse: the button the gesture presses sinks (keycap pressed tint)
    Item {
        visible: root.mouse
        width: Theme.iconSize * 2.4
        height: width * 1.35
        x: -width / 2
        y: -height / 2

        Rectangle {
            anchors.fill: parent
            radius: width * 0.45
            color: Theme.surfaceContainerHigh
            border.width: Theme.outlineWidthFocused
            border.color: Theme.outline
        }

        Rectangle {
            readonly property bool down: root.pressed && root.spec?.btn === "left"
            x: parent.width * 0.08
            y: parent.height * 0.07
            width: parent.width * 0.30
            height: parent.height * 0.28
            radius: Theme.cornerRadiusXS
            color: down ? Theme.primaryContainer : Theme.surface
            border.width: Theme.outlineWidth
            border.color: Theme.outlineVariant
        }

        Rectangle {
            id: middle

            readonly property bool down: root.pressed && root.spec?.btn === "middle"
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.07
            width: parent.width * 0.16
            height: parent.height * 0.28
            radius: Theme.cornerRadiusXS
            color: down ? Theme.primaryContainer : Theme.surface
            border.width: Theme.outlineWidth
            border.color: Theme.outlineVariant

            // The wheel of the middle button
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.55
                height: parent.height * 0.55
                radius: width / 2
                color: middle.down ? Theme.onPrimaryContainer : Theme.outline
            }
        }

        Rectangle {
            readonly property bool down: root.pressed && root.spec?.btn === "right"
            x: parent.width * 0.92 - width
            y: parent.height * 0.07
            width: parent.width * 0.30
            height: parent.height * 0.28
            radius: Theme.cornerRadiusXS
            color: down ? Theme.primaryContainer : Theme.surface
            border.width: Theme.outlineWidth
            border.color: Theme.outlineVariant
        }
    }

    GestModKey {
        visible: root.spec?.mod === true
        x: Theme.spacingM
        y: Theme.spacingM
    }
}
