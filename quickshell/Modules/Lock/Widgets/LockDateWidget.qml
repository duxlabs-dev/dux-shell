import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    property var instanceData: null
    property var lockHost: null
    readonly property var cfg: instanceData?.config ?? ({})
    readonly property color contentColor: lockHost?.contentColor(cfg.colorMode ?? "default", cfg.customColor ?? "#ffffff") ?? Theme.lockScreenContentColor
    readonly property string fontFamily: SettingsData.lockScreenFontFamily
    readonly property bool resizable: true
    readonly property real minWidth: implicitWidth / 2
    readonly property real minHeight: implicitHeight / 2
    readonly property real fitScale: implicitWidth > 0 && implicitHeight > 0 ? Math.min(width / implicitWidth, height / implicitHeight) : 1

    implicitWidth: dateText.implicitWidth
    implicitHeight: dateText.implicitHeight

    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    StyledText {
        id: dateText
        anchors.centerIn: parent
        scale: root.fitScale
        text: {
            if (SettingsData.lockDateFormat && SettingsData.lockDateFormat.length > 0)
                return systemClock.date.toLocaleDateString(I18n.locale(), SettingsData.lockDateFormat);
            return systemClock.date.toLocaleDateString(I18n.locale(), (root.cfg.format ?? "long") === "short" ? "ddd, d MMM" : Locale.LongFormat);
        }
        font.pixelSize: Theme.fontSizeXLarge
        font.family: root.fontFamily !== "" ? root.fontFamily : resolvedFontFamily
        color: root.contentColor
    }
}
