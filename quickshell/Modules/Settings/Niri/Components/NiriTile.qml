pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets

// An on/off setting shown as what it does: the picture goes in the default slot and reads `on` and `hovered`.
Rectangle {
    id: root

    property string settingKey: ""
    property string icon: ""
    property string title: ""
    property string tip: ""
    property string kdlKey: ""
    property string dependsOn: ""
    default property alias illustration: picture.data

    readonly property bool on: settingKey !== "" && NiriPageService.get(settingKey) === true
    readonly property bool modified: settingKey !== "" && NiriPageService.isModified(settingKey)
    readonly property bool folded: dependsOn !== "" && !NiriPageService.get(dependsOn)
    readonly property bool expert: NiriPageService.expert
    readonly property bool hovered: hover.hovered
    readonly property bool isNew: settingKey !== "" && NiriPageService.isNew(settingKey)

    visible: !folded
    implicitWidth: Theme.iconButtonSize * 4.25
    implicitHeight: content.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadiusM
    color: on ? Theme.blend(Theme.surface, Theme.primaryContainer, 0.3) : Theme.surface
    border.width: Theme.outlineWidth
    border.color: on ? Theme.primary : Theme.outlineVariant

    Behavior on color {
        enabled: !SettingsData.reduceMotion
        ColorAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    HoverHandler {
        id: hover
    }

    Column {
        id: content

        x: Theme.spacingS
        y: Theme.spacingS
        width: parent.width - Theme.spacingS * 2
        spacing: Theme.spacingS

        Rectangle {
            id: picture
            width: parent.width
            height: Theme.buttonHeightM + Theme.buttonHeightXXS
            radius: Theme.cornerRadiusM
            color: SettingsMetrics.controlColor
            clip: true
        }

        Column {
            x: Theme.spacingXS
            width: parent.width - Theme.spacingXS * 2
            spacing: Theme.spacingXXS

            Row {
                id: titleRow
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, titleRow.width - (newPill.visible ? newPill.width + Theme.spacingS : 0) - (modDot.visible ? modDot.width + Theme.spacingS : 0))
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                Rectangle {
                    id: newPill

                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isNew
                    width: newText.implicitWidth + Theme.spacingS * 2
                    height: Theme.iconSizeSmall + Theme.spacingXXS
                    radius: height / 2
                    color: Theme.primaryContainer
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("New", "niri page pill, an option that came with a niri update")

                    StyledText {
                        id: newText
                        anchors.centerIn: parent
                        text: I18n.tr("New", "niri page pill, an option that came with a niri update")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightBold
                        color: Theme.onPrimaryContainer
                    }

                    // Once the pill is on screen the version is seen, and it stops showing next session.
                    onVisibleChanged: {
                        if (visible)
                            NiriPageService.noteSeenVersion();
                    }
                }

                Rectangle {
                    id: modDot
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.modified
                    width: Theme.spacingS
                    height: width
                    radius: width / 2
                    color: Theme.primary
                    Accessible.role: Accessible.StaticText
                    Accessible.name: I18n.tr("Modified")
                }
            }

            StyledText {
                width: parent.width
                visible: root.expert && root.tip !== ""
                text: root.tip
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                width: parent.width
                visible: root.expert && root.kdlKey !== ""
                text: root.kdlKey
                elide: Text.ElideRight
                font.family: Theme.monoFontFamily
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Loader {
                active: root.hovered && !root.expert && root.tip !== ""
                sourceComponent: DTooltipHost {
                    target: titleText
                    side: "top"
                    multiline: true
                    text: root.tip
                    Component.onCompleted: Qt.callLater(schedule)
                }
            }
        }

        Item {
            x: Theme.spacingXS
            width: parent.width - Theme.spacingXS * 2
            height: Math.max(toggle.height, Theme.avatarSize)

            // Reset sits just before the switch; its slot stays reserved so every tile's switch lines up.
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.avatarSize
                    height: Theme.avatarSize

                    DActionButton {
                        anchors.centerIn: parent
                        visible: root.modified
                        buttonSize: Theme.avatarSize
                        iconName: "restart_alt"
                        iconColor: Theme.surfaceVariantText
                        tooltipText: I18n.tr("Reset to default")
                        tooltipSide: "top"
                        onClicked: NiriPageService.reset(root.settingKey)
                    }
                }

                DToggle {
                    id: toggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.on
                    Accessible.name: root.title
                    onToggled: checked => NiriPageService.set(root.settingKey, checked)
                }
            }
        }
    }
}
