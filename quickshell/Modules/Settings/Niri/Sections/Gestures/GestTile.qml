pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// One gesture: a small device drawing, its name and how to do it. Hover or focus plays it on the stage.
Rectangle {
    id: root

    property string gesture: ""
    property string title: ""
    property string hint: ""
    property string sentence: ""
    // "pad", "mouse" or "touch"
    property string device: "pad"
    property int fingers: 3
    property string arrow: ""
    // mouse: "left", "right" or "wheel"; touch: the icon of the hand
    property string part: ""
    property bool mod: false

    readonly property bool active: hover.hovered || activeFocus

    signal playRequested

    width: parent?.width ?? 0
    implicitHeight: Math.max(Theme.buttonHeightM, row.implicitHeight + Theme.spacingS * 2)
    radius: Theme.cornerRadiusM
    color: Theme.surface
    border.width: activeFocus ? Theme.outlineWidthFocused : Theme.outlineWidth
    border.color: active ? Theme.primary : Theme.outlineVariant
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title + ": " + sentence
    Keys.onReturnPressed: playRequested()
    Keys.onEnterPressed: playRequested()
    Keys.onSpacePressed: playRequested()

    Behavior on border.color {
        enabled: !SettingsData.reduceMotion

        ColorAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    HoverHandler {
        id: hover
    }

    Row {
        id: row

        x: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingM

        Rectangle {
            id: figure

            readonly property bool mouse: root.device === "mouse"
            readonly property bool touch: root.device === "touch"

            anchors.verticalCenter: parent.verticalCenter
            width: mouse || touch ? Theme.buttonHeightXS + Theme.spacingM : Theme.buttonHeightM + Theme.spacingS
            height: touch || mouse ? Theme.buttonHeightM - Theme.spacingXS : Theme.buttonHeightS + Theme.spacingXS
            radius: mouse ? width * 0.45 : Theme.cornerRadiusS
            color: SettingsMetrics.controlColor
            border.width: Theme.outlineWidthFocused
            border.color: Theme.outline

            Row {
                visible: root.device === "pad"
                anchors.centerIn: parent
                spacing: Theme.spacingXXS + Theme.outlineWidth

                Repeater {
                    model: root.device === "pad" ? root.fingers : 0

                    Rectangle {
                        width: Theme.spacingS
                        height: width
                        radius: width / 2
                        color: Theme.primary
                    }
                }
            }

            Rectangle {
                visible: root.arrow !== ""
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -Theme.spacingXS
                width: Theme.iconSizeMedium
                height: width
                radius: width / 2
                color: Theme.surfaceContainerHigh

                DIcon {
                    anchors.centerIn: parent
                    name: root.arrow
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceText
                }
            }

            Rectangle {
                visible: figure.mouse && (root.part === "left" || root.part === "right")
                x: root.part === "left" ? Theme.spacingXS + Theme.spacingXXS : parent.width / 2 + Theme.outlineWidth
                y: Theme.spacingXS + Theme.spacingXXS
                width: parent.width / 2 - Theme.spacingXS - Theme.spacingXXS - Theme.outlineWidth
                height: parent.height * 0.32
                radius: Theme.cornerRadiusS
                color: Theme.primary
            }

            Rectangle {
                visible: figure.mouse
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.spacingS
                width: Theme.spacingXS + Theme.spacingXXS
                height: parent.height * 0.24
                radius: width / 2
                color: root.part === "wheel" ? Theme.primary : Theme.outline
            }

            DIcon {
                visible: figure.touch
                anchors.centerIn: parent
                name: root.part
                size: Theme.iconSize
                color: Theme.primary
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - figure.width - parent.spacing
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                text: root.title
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightBold
                color: Theme.surfaceText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingXS

                GestModKey {
                    id: modKey
                    visible: root.mod
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (modKey.visible ? modKey.width + parent.spacing : 0)
                    text: root.hint
                    wrapMode: Text.WordWrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
