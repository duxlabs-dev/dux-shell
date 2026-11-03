pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DesktopWidgetSettings

DesktopWidgetInstanceSettings {
    id: root

    readonly property var shapes: ["round", "cookie9", "clover4", "sunny", "softBurst"]
    readonly property string shape: cfg.shape ?? "round"

    showAppearance: false

    SettingsRow {
        title: I18n.tr("Style")

        body: Row {
            width: parent.width
            spacing: Theme.spacingS

            Repeater {
                model: root.shapes

                Rectangle {
                    id: swatch

                    required property string modelData
                    readonly property bool selected: root.shape === modelData

                    width: (parent.width - Theme.spacingS * (root.shapes.length - 1)) / root.shapes.length
                    height: Theme.listItemHeight + Theme.spacingXS
                    radius: Theme.cornerRadius
                    color: selected ? Theme.primarySelected : SettingsMetrics.controlColor
                    border.color: selected ? Theme.primary : Theme.withAlpha(Theme.primary, 0)
                    border.width: Theme.outlineWidthFocused
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: modelData

                    DMaterialShape {
                        anchors.centerIn: parent
                        width: Theme.iconSizeLarge
                        height: Theme.iconSizeLarge
                        shape: swatch.modelData === "round" ? "circle" : swatch.modelData
                        color: Theme.secondaryContainer

                        DIcon {
                            anchors.centerIn: parent
                            name: "power_settings_new"
                            size: Theme.iconSizeSmall
                            color: Theme.onSecondaryContainer
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.updateConfig("shape", swatch.modelData)
                    }
                }
            }
        }
    }
}
