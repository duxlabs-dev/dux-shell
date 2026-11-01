import QtQuick
import qs.Common
import qs.DCommon.Widgets

// shortcut: niri's Mod is Super on a real session; show the configured mod key once W-adv exposes it.
Rectangle {
    width: label.implicitWidth + Theme.spacingXS * 2
    height: label.implicitHeight + Theme.spacingXXS
    radius: Theme.cornerRadiusXS
    color: Theme.surfaceContainerHighest
    border.width: Theme.outlineWidth
    border.color: Theme.outlineVariant

    StyledText {
        id: label
        anchors.centerIn: parent
        text: I18n.tr("Super", "keyboard key")
        font.family: Theme.monoFontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightBold
        color: Theme.surfaceText
    }
}
