pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Niri.Components
import qs.Modules.Settings.Widgets

// The cursor rows edit fields of SettingsData.cursorSettings, the one writer of dms/cursor.kdl, so they carry no settingKey.
NiriCard {
    id: root

    readonly property var cursor: SettingsData.cursorSettings
    readonly property var sizes: [24, 32, 48, 64]
    readonly property var idleSeconds: [0, 3, 5, 10]

    function setNiri(field, value) {
        const updated = JSON.parse(JSON.stringify(SettingsData.cursorSettings));
        updated.niri = updated.niri || {};
        updated.niri[field] = value;
        SettingsData.set("cursorSettings", updated);
    }

    title: I18n.tr("Cursor", "settings card title for mouse cursor theme")
    icon: "arrow_selector_tool"

    Component.onCompleted: SettingsData.detectAvailableCursorThemes()

    NiriRow {
        id: themeRow

        icon: "palette"
        title: I18n.tr("Theme")
        kdlKey: "cursor.xcursor-theme"
        // Many themes: always under the title, wrapping
        controlWidth: Number.MAX_VALUE

        Flow {
            width: themeRow.stackedControlWidth
            spacing: Theme.spacingS

            Repeater {
                model: SettingsData.availableCursorThemes

                Rectangle {
                    id: themeButton

                    required property string modelData
                    readonly property bool selected: root.cursor.theme === modelData

                    width: Theme.iconButtonSize * 2.4
                    height: themeColumn.implicitHeight + Theme.spacingS * 2
                    radius: Theme.cornerRadiusM
                    color: selected ? Theme.primaryContainer : Theme.surface
                    border.width: selected ? Theme.outlineWidthFocused : Theme.outlineWidth
                    border.color: selected ? Theme.primary : (themeMouse.containsMouse ? Theme.outline : Theme.outlineVariant)
                    activeFocusOnTab: true
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData
                    Accessible.checked: selected
                    Keys.onSpacePressed: SettingsData.setCursorTheme(modelData)
                    Keys.onReturnPressed: SettingsData.setCursorTheme(modelData)

                    Column {
                        id: themeColumn
                        x: Theme.spacingXS
                        y: Theme.spacingS
                        width: parent.width - Theme.spacingXS * 2
                        spacing: Theme.spacingXXS

                        InputCursorArt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            theme: themeButton.modelData
                            role: "default"
                            displaySize: Theme.iconSizeLarge
                        }

                        StyledText {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: themeButton.modelData === "System Default" ? I18n.tr("System Default") : themeButton.modelData
                            elide: Text.ElideRight
                            wrapMode: Text.NoWrap
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: themeButton.selected ? Theme.fontWeightBold : Theme.fontWeight
                            color: themeButton.selected ? Theme.onPrimaryContainer : Theme.surfaceText
                        }
                    }

                    MouseArea {
                        id: themeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: SettingsData.setCursorTheme(themeButton.modelData)
                    }
                }
            }
        }
    }

    // Three real cursors of the theme the page would apply, so a pick shows its own result.
    NiriRow {
        icon: "visibility"
        title: I18n.tr("Preview", "cursor card row, real cursors of the selected theme")

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingM

            InputCursorArt {
                theme: root.cursor.theme
                role: "default"
                displaySize: root.cursor.size || 24
            }

            InputCursorArt {
                theme: root.cursor.theme
                role: "text"
                displaySize: root.cursor.size || 24
            }

            InputCursorArt {
                theme: root.cursor.theme
                role: "resize"
                displaySize: root.cursor.size || 24
            }
        }
    }

    NiriRow {
        id: sizeRow

        icon: "open_in_full"
        title: I18n.tr("Size")
        kdlKey: "cursor.xcursor-size"

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: sizeButtons.width + Theme.spacingXS * 2
            height: sizeButtons.height + Theme.spacingXS * 2
            radius: height / 2
            color: SettingsMetrics.controlColor

            Row {
                id: sizeButtons
                anchors.centerIn: parent
                spacing: Theme.spacingXXS

                Repeater {
                    model: root.sizes

                    DActionButton {
                        id: sizeButton

                        required property int modelData
                        required property int index
                        readonly property bool selected: root.cursor.size === modelData

                        buttonSize: Theme.buttonHeightS
                        iconName: "arrow_selector_tool"
                        iconFilled: true
                        iconSize: Theme.iconSizeSmall + index * Theme.spacingXS
                        iconColor: selected ? Theme.onPrimary : Theme.surfaceText
                        backgroundColor: selected ? Theme.primary : "transparent"
                        tooltipText: modelData + " px"
                        tooltipSide: "top"
                        Accessible.name: modelData + " px"
                        onClicked: SettingsData.setCursorSize(modelData)
                    }
                }
            }
        }
    }

    NiriRow {
        id: typingRow

        readonly property bool hiding: root.cursor.niri?.hideWhenTyping ?? false

        icon: "keyboard"
        title: I18n.tr("Hide while typing", "niri page, cursor")
        kdlKey: "cursor.hide-when-typing"

        DToggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: typingRow.hiding
            Accessible.name: typingRow.title
            onToggled: checked => root.setNiri("hideWhenTyping", checked)
        }
    }

    NiriRow {
        id: idleRow

        readonly property int ms: root.cursor.niri?.hideAfterInactiveMs ?? 0

        icon: "visibility_off"
        title: I18n.tr("Hide when idle", "niri page, cursor")
        kdlKey: "cursor.hide-after-inactive-ms"

        DButtonGroup {
            id: idleGroup

            anchors.verticalCenter: parent.verticalCenter
            arrowKeysSelect: false
            model: root.idleSeconds.map(s => s === 0 ? I18n.tr("Never") : I18n.tr("%1 s", "seconds, short").arg(s))
            currentIndex: root.idleSeconds.indexOf(idleRow.ms / 1000)
            Accessible.name: idleRow.title
            onSelectionChanged: (index, selected) => {
                if (!selected || index === currentIndex)
                    return;
                root.setNiri("hideAfterInactiveMs", root.idleSeconds[index] * 1000);
            }
        }
    }
}
