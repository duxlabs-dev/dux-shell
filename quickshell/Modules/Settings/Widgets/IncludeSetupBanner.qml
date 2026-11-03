import QtQuick
import qs.Common
import qs.DCommon.Widgets

StyledRect {
    id: root

    required property ConfigInclude include
    property bool visibleCondition: true

    readonly property bool showLegacy: include.readOnly
    readonly property bool showSetup: !showLegacy && !include.included

    width: parent.width
    height: content.implicitHeight + Theme.spacingL * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.primary, 0.15)
    border.color: Theme.withAlpha(Theme.primary, 0.3)
    border.width: Theme.outlineWidth
    visible: visibleCondition && include.compositorSupported && (showLegacy || showSetup) && !include.checking

    Row {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        DIcon {
            name: "warning"
            size: Theme.iconSize
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            width: parent.width - Theme.iconSize - (fixButton.visible ? fixButton.width + Theme.spacingM : 0) - Theme.spacingM
            spacing: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: root.showLegacy ? I18n.tr("%1 not found").arg("hyprland.lua") : I18n.tr("First Time Setup")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.primary
                width: parent.width
                horizontalAlignment: Text.AlignLeft
            }

            StyledText {
                text: root.showLegacy ? I18n.tr("Run %1 to create it before changing these settings.", "hyprland.lua missing warning, %1 is a command").arg("dms setup") : I18n.tr("Click 'Setup' to create %1 and add include to your compositor config.").arg(root.include.fragmentLabel)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignLeft
            }
        }

        DButton {
            id: fixButton
            visible: root.showSetup
            text: root.include.fixing ? I18n.tr("Setting up...") : I18n.tr("Setup")
            backgroundColor: Theme.primary
            textColor: Theme.primaryText
            enabled: !root.include.fixing && !root.include.readOnly
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.include.fix()
        }
    }
}
