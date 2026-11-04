import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

// Same setup and override warnings as the old Keybinds tab: without the include, nothing written here reaches niri
Rectangle {
    id: root

    readonly property var status: KeybindsService.dmsStatus
    readonly property bool showSetup: !status.included
    readonly property bool showWarning: status.included && status.overriddenBy > 0

    visible: (showSetup || showWarning) && !KeybindsService.loading
    height: visible ? row.implicitHeight + Theme.spacingM * 2 : 0
    radius: Theme.cornerRadiusM
    color: Theme.withAlpha(Theme.primary, 0.15)

    Row {
        id: row
        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        DIcon {
            name: root.showWarning ? "info" : "warning"
            size: Theme.iconSizeMedium
            color: Theme.primary
        }

        Column {
            width: parent.width - Theme.iconSizeMedium - (fix.visible ? fix.width + Theme.spacingS : 0) - Theme.spacingS
            spacing: Theme.spacingXXS

            StyledText {
                width: parent.width
                text: root.showSetup ? I18n.tr("First Time Setup") : I18n.tr("Possible override conflicts")
                font.weight: Theme.fontWeightMedium
                color: Theme.primary
            }

            StyledText {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                text: {
                    if (root.showSetup)
                        return I18n.tr("Click 'Setup' to create %1 and add include to your compositor config.", "include setup banner, %1 is the dms config file name").arg("dms/binds");
                    const count = root.status.overriddenBy;
                    return (count === 1 ? I18n.tr("%1 DMS bind may be overridden by config binds that come after the include.", "singular, keybinds warning, %1 is 1") : I18n.tr("%1 DMS binds may be overridden by config binds that come after the include.", "plural, keybinds warning, %1 is a count")).arg(count);
                }
            }
        }

        DButton {
            id: fix
            visible: root.showSetup
            text: KeybindsService.fixing ? I18n.tr("Setting up...") : I18n.tr("Setup", "verb, button that creates the dms include config file")
            backgroundColor: Theme.primary
            textColor: Theme.onPrimary
            enabled: !KeybindsService.fixing
            onClicked: KeybindsService.fixDmsBindsInclude()
        }
    }
}
