pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

// The small pictures of the Touchpad and mouse tiles: "tap", "natural", "follow" or "warp".
Item {
    id: root

    property string kind: ""
    property bool on: false
    property bool hovered: false

    readonly property color ink: on ? Theme.primary : Theme.surfaceVariantText
    readonly property real finger: Theme.spacingM
    readonly property real move: Theme.spacingM

    anchors.fill: parent

    Rectangle {
        id: pad

        visible: root.kind === "tap" || root.kind === "natural"
        anchors.centerIn: parent
        width: parent.height * 1.5
        height: parent.height - Theme.spacingS * 2
        radius: Theme.cornerRadiusS
        color: "transparent"
        border.width: Theme.outlineWidthFocused
        border.color: Theme.outline
    }

    Rectangle {
        visible: root.kind === "tap"
        anchors.centerIn: pad
        width: root.finger * (root.on && root.hovered ? 2.4 : 1.8)
        height: width
        radius: width / 2
        color: root.ink
        opacity: root.on ? 0.3 : 0

        Behavior on width {
            enabled: !SettingsData.reduceMotion
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Theme.standardEasing
            }
        }
    }

    Rectangle {
        visible: root.kind === "tap"
        anchors.centerIn: pad
        width: root.finger
        height: width
        radius: width / 2
        color: root.ink
    }

    Repeater {
        model: root.kind === "natural" ? 2 : 0

        Rectangle {
            required property int index

            x: pad.x + pad.width / 2 + (index === 0 ? -root.finger * 1.2 : root.finger * 0.2)
            y: pad.y + (pad.height - height) / 2 + (root.hovered ? -root.move / 2 : root.move / 2)
            width: root.finger
            height: width
            radius: width / 2
            color: root.ink

            Behavior on y {
                enabled: !SettingsData.reduceMotion
                NumberAnimation {
                    duration: Theme.mediumDuration
                    easing.type: Theme.standardEasing
                }
            }
        }
    }

    DIcon {
        visible: root.kind === "natural"
        anchors.left: pad.right
        anchors.leftMargin: Theme.spacingS
        y: (parent.height - height) / 2 + (root.hovered ? (root.on ? -root.move / 2 : root.move / 2) : 0)
        name: "article"
        size: Theme.iconSizeMedium
        color: Theme.surfaceVariantText

        Behavior on y {
            enabled: !SettingsData.reduceMotion
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Theme.standardEasing
            }
        }
    }

    Row {
        id: windows

        visible: root.kind === "follow" || root.kind === "warp"
        anchors.centerIn: parent
        spacing: Theme.spacingS

        Repeater {
            model: 2

            Rectangle {
                required property int index

                readonly property bool focused: root.on && (root.kind === "follow" ? index === 1 : index === 0)

                width: root.height * 0.9
                height: root.height - Theme.spacingS * 2
                radius: Theme.cornerRadiusS
                color: Theme.surfaceContainerHighest
                border.width: focused ? Theme.outlineWidthFocused : Theme.outlineWidth
                border.color: focused ? Theme.primary : Theme.outlineVariant
            }
        }
    }

    DIcon {
        visible: windows.visible
        readonly property bool atFirst: root.kind === "warp" && root.on
        x: windows.x + (atFirst ? windows.width * 0.22 : windows.width * 0.7)
        y: windows.y + windows.height * (atFirst ? 0.3 : 0.4)
        name: "arrow_selector_tool"
        filled: true
        size: Theme.iconSizeMedium
        color: Theme.surfaceText

        Behavior on x {
            enabled: !SettingsData.reduceMotion
            NumberAnimation {
                duration: Theme.mediumDuration
                easing.type: Theme.emphasizedEasing
            }
        }
    }
}
