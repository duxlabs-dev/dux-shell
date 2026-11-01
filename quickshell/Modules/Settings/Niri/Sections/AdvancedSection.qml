pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets
import "../../../../Common/niri/sections/advanced.js" as Advanced
import "../../../../Common/niri/keep.js" as Keep

Column {
    id: root

    readonly property string sectionId: "advanced"

    property bool open: false

    spacing: Theme.spacingM

    NiriKeep {
        id: keeper
        risky: Advanced.risky
    }

    Rectangle {
        width: parent.width
        implicitHeight: foldColumn.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadiusL
        color: SettingsMetrics.rowColor
        border.width: Theme.outlineWidth
        border.color: Theme.warning

        Column {
            id: foldColumn

            // NiriCard padding, so the risky rows bleed to the edge like in every other card
            x: Theme.spacingL
            y: Theme.spacingS
            width: parent.width - Theme.spacingL * 2

            Rectangle {
                id: summary

                width: parent.width
                implicitHeight: Math.max(Theme.listItemHeight, summaryRow.implicitHeight + Theme.spacingS * 2)
                radius: Theme.cornerRadiusM
                color: "transparent"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: summaryText.text
                Accessible.onPressAction: root.open = !root.open

                Keys.onPressed: event => {
                    if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                        return;
                    root.open = !root.open;
                    event.accepted = true;
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.surfaceText
                    opacity: summaryMouse.pressed ? Theme.stateLayerPressed : summaryMouse.containsMouse ? Theme.stateLayerHover : 0
                }

                Row {
                    id: summaryRow

                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.spacingS - chevron.width
                    spacing: Theme.spacingM

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "shield"
                        size: Theme.iconSizeMedium
                        color: Theme.primary
                    }

                    StyledText {
                        id: summaryText
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("4 risky settings", "niri page advanced, folded card title")
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: chipRow.implicitWidth + Theme.spacingS * 2
                        height: chipRow.implicitHeight + Theme.spacingXXS * 2
                        radius: height / 2
                        color: Theme.withAlpha(Theme.warning, Theme.stateLayerPressed)

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXXS

                            DIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "timer"
                                size: Theme.iconSizeSmall
                                color: Theme.surfaceText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Keep? %1 s", "niri page advanced, risky settings revert after %1 seconds unless kept, %1 is the countdown length").arg(Keep.seconds)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                            }
                        }
                    }
                }

                DIcon {
                    id: chevron
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: "expand_more"
                    size: Theme.iconSize
                    color: Theme.surfaceText
                    rotation: root.open ? 180 : 0
                }

                MouseArea {
                    id: summaryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.open = !root.open
                }

                FocusRing {
                    anchors.margins: Theme.focusRingWidth / 2
                    radius: summary.radius
                }
            }

            Column {
                visible: root.open
                width: parent.width
                topPadding: Theme.spacingXS
                bottomPadding: Theme.spacingS
                spacing: Theme.spacingXXS

                NiriSeg {
                    settingKey: "advanced.modKey"
                    icon: "keyboard_command_key"
                    title: I18n.tr("Mod key", "niri page advanced")
                    tip: I18n.tr("Every Mod shortcut moves to the new key", "niri page advanced, mod key")
                    kdlKey: "input.mod-key"
                    tryValue: undefined
                    options: [
                        {
                            "value": "Super",
                            "text": "Super"
                        },
                        {
                            "value": "Alt",
                            "text": "Alt"
                        }
                    ]

                    function write(v) {
                        keeper.edit(settingKey, v);
                    }

                    function resetValue() {
                        keeper.edit(settingKey, NiriPageService.defaultOf(settingKey));
                    }
                }

                NiriRow {
                    settingKey: "advanced.powerKey"
                    icon: "power_settings_new"
                    title: I18n.tr("DMS handles the power button", "niri page advanced")
                    tip: I18n.tr("niri stops sending it to the system", "niri page advanced, power button")
                    kdlKey: "input.disable-power-key-handling"
                    tryValue: undefined

                    function write(v) {
                        keeper.edit(settingKey, v);
                    }

                    function resetValue() {
                        keeper.edit(settingKey, NiriPageService.defaultOf(settingKey));
                    }
                }

                NiriRow {
                    settingKey: "advanced.xwayland"
                    icon: "select_window"
                    title: I18n.tr("X11 apps", "niri page advanced")
                    tip: I18n.tr("Off: X11 apps stop opening", "niri page advanced, xwayland-satellite")
                    kdlKey: "xwayland-satellite off"
                    tryValue: undefined

                    function write(v) {
                        keeper.edit(settingKey, v);
                    }

                    function resetValue() {
                        keeper.edit(settingKey, NiriPageService.defaultOf(settingKey));
                    }
                }

                NiriRow {
                    settingKey: "advanced.debug"
                    icon: "bug_report"
                    title: I18n.tr("Debug options", "niri page advanced")
                    tip: I18n.tr("No compatibility promise from niri", "niri page advanced, debug block")
                    kdlKey: "debug"
                    tryValue: undefined

                    function write(v) {
                        keeper.edit(settingKey, v);
                    }

                    function resetValue() {
                        keeper.edit(settingKey, NiriPageService.defaultOf(settingKey));
                    }
                }

                Repeater {
                    model: Advanced.debugFlags

                    // The flag names are niri's own config words, shown as they are written.
                    NiriRow {
                        required property string modelData

                        settingKey: "advanced.dbg." + modelData
                        title: modelData
                        kdlKey: "debug." + modelData
                        dependsOn: "advanced.debug"
                        tryValue: undefined

                        function write(v) {
                            keeper.edit(settingKey, v);
                        }

                        function resetValue() {
                            keeper.edit(settingKey, NiriPageService.defaultOf(settingKey));
                        }
                    }
                }
            }
        }
    }

    NiriCard {
        icon: "notifications"
        title: I18n.tr("Notifications")

        NiriRow {
            settingKey: "advanced.configToast"
            icon: "notifications"
            title: I18n.tr("Show \"config reloaded\" toast")
            tip: I18n.tr("After niri reloads its config")
        }
    }
}
