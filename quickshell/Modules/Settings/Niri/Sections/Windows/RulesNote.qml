import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    // "", "ok" or "warn"
    property string tone: ""
    property bool mono: false
    readonly property color toneColor: tone === "warn" ? Theme.warning : tone === "ok" ? Theme.success : Theme.primary

    width: parent?.width ?? 0
    implicitHeight: Math.max(Theme.iconSizeMedium, label.implicitHeight) + Theme.spacingM * 2
    radius: Theme.cornerRadiusM
    color: tone === "" ? Theme.surfaceContainerHighest : Theme.withAlpha(toneColor, 0.16)

    DIcon {
        id: glyph
        x: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: Theme.iconSizeMedium
        color: root.toneColor
    }

    StyledText {
        id: label
        x: glyph.x + glyph.width + Theme.spacingS
        width: parent.width - x - Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        wrapMode: Text.Wrap
        font.family: root.mono ? Theme.monoFontFamily : Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        Accessible.role: Accessible.StaticText
    }
}
