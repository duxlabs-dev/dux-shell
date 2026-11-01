pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Common
import qs.DCommon.Widgets
import qs.Services
import qs.Widgets

Popup {
    id: root

    required property var health

    readonly property int lastGood: NiriPageService.history.find(v => !v.failed)?.n ?? 0
    // Measured on open: a Popup taller than the room below its parent slides up over the pill
    property real room: 0
    // One surface colour for the background and the edge fade carrier
    readonly property color surface: Theme.surfaceContainerHigh

    function fileState(state, overrides) {
        switch (state) {
        case "base":
            return I18n.tr("Base", "niri health file list, the main config.kdl");
        case "missing":
            return I18n.tr("Missing", "niri health file list");
        case "not-included":
            return I18n.tr("Not included", "niri health file list");
        case "unreadable":
            return I18n.tr("Unreadable", "niri health file list");
        }
        return overrides ? I18n.tr("Overrides %1", "niri health file list, %1 is a count of settings").arg(overrides) : I18n.tr("Active", "niri health file list");
    }

    x: parent.width - width
    y: parent.height + Theme.spacingXS
    width: Math.min(600, (parent.Window.width || 600) - Theme.spacingL * 2)
    height: Math.min(content.implicitHeight + padding * 2, room)
    margins: Theme.spacingM
    padding: Theme.spacingL
    modal: false
    focus: true
    // Outside the pill only: a press on the pill is its own toggle, closing here would reopen at release
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    onAboutToShow: {
        room = parent.Window.height - parent.mapToItem(null, 0, parent.height).y - Theme.spacingXS - Theme.spacingM * 2;
        health.refresh();
    }

    background: Rectangle {
        color: root.surface
        radius: Theme.cornerRadiusL
        border.width: Theme.outlineWidth
        border.color: Theme.outlineVariant
    }

    // Carries the popup surface: DEdgeFade looks for it among the list ancestors, and the background is not one
    contentItem: Item {
        readonly property color surfaceColor: root.surface

        DFlickable {
            anchors.fill: parent
            contentHeight: content.implicitHeight
            clip: true

            Column {
                id: content
                width: parent.width
                spacing: Theme.spacingS

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "health_and_safety"
                        size: Theme.iconSizeMedium
                        color: Theme.primary
                    }

                    StyledText {
                        id: heading
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Health", "niri health popover title")
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Theme.fontWeightBold
                        color: Theme.surfaceText
                    }

                    Item {
                        width: parent.width - heading.width - checkButton.width - closeButton.width - Theme.iconSizeMedium - parent.spacing * 4
                        height: 1
                    }

                    DButton {
                        id: checkButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Check", "niri health popover button that runs the doctor again")
                        iconName: "refresh"
                        busy: root.health.checking
                        onClicked: root.health.refresh()
                    }

                    DIconButton {
                        id: closeButton
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "close"
                        Accessible.name: I18n.tr("Close")
                        onClicked: root.close()
                    }
                }

                NiriHealthNote {
                    width: parent.width
                    health: root.health
                    visible: root.health.reloadFailed
                    tone: Theme.error
                    iconName: "settings_backup_restore"
                    text: root.lastGood ? I18n.tr("Reload failed · back to v%1", "niri health note, niri refused the last config").arg(root.lastGood) : I18n.tr("Reload failed", "niri health pill, niri refused the last config")
                }

                NiriHealthNote {
                    width: parent.width
                    health: root.health
                    visible: root.health.error !== ""
                    tone: Theme.error
                    iconName: "error"
                    text: root.health.error
                }

                NiriHealthHeading {
                    text: I18n.tr("Doctor", "niri health popover section, config checks")
                }

                StyledText {
                    visible: root.health.report !== null && root.health.findings.length === 0
                    text: I18n.tr("All good", "niri health doctor, no finding")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Repeater {
                    model: root.health.findings

                    NiriHealthFinding {
                        required property var modelData
                        width: content.width
                        health: root.health
                        finding: modelData
                    }
                }

                NiriHealthNote {
                    width: parent.width
                    health: root.health
                    visible: root.health.report?.undo ?? false
                    tone: Theme.primary
                    iconName: "undo"
                    text: I18n.tr("Include added to config.kdl", "niri health note after the add include fix")
                    actionText: I18n.tr("Undo")
                    onActionClicked: root.health.undoFix()
                }

                Item {
                    width: parent.width
                    height: Math.max(autoText.implicitHeight, onChip.height) + Theme.spacingS * 2

                    Column {
                        id: autoText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - onChip.width - Theme.spacingM

                        StyledText {
                            text: I18n.tr("Auto-restore", "niri health, a failed reload brings the last good version back")
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            width: parent.width
                            text: I18n.tr("If niri fails to reload, the last good version comes back", "niri health auto-restore explanation")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                        }
                    }

                    NiriHealthChip {
                        id: onChip
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("On", "niri health auto-restore state")
                        tone: Theme.success
                    }
                }

                NiriHealthHeading {
                    text: I18n.tr("Who overrides what", "niri health popover section, config files in load order")
                }

                Repeater {
                    model: root.health.report?.files ?? []

                    Item {
                        id: file

                        required property var modelData

                        width: content.width
                        height: Math.max(fileChip.height, fileName.implicitHeight) + Theme.spacingXS * 2

                        StyledText {
                            id: fileName
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - fileChip.width - Theme.spacingM
                            text: file.modelData.path
                            font.family: Theme.monoFontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: file.modelData.state === "base" ? Theme.fontWeightBold : Font.Normal
                            color: Theme.surfaceText
                            elide: Text.ElideMiddle
                        }

                        NiriHealthChip {
                            id: fileChip
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fileState(file.modelData.state, file.modelData.overrides)
                            tone: ({
                                    "missing": Theme.error,
                                    "unreadable": Theme.error,
                                    "not-included": Theme.warning,
                                    "base": Theme.surfaceVariantText
                                })[file.modelData.state] ?? (file.modelData.overrides ? Theme.warning : Theme.success)
                        }
                    }
                }

                NiriHealthVersions {
                    width: parent.width
                }
            }
        }
    }
}
