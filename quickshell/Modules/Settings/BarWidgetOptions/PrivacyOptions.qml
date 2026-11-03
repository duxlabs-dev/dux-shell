import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets

Column {
    id: root

    property var page: null

    width: parent?.width ?? 0
    spacing: Theme.spacingL

    SettingsCard {
        title: I18n.tr("Always on icons")
        settingKey: "barWidgetPrivacy"

        SettingsToggleRow {
            iconName: "mic"
            text: I18n.tr("Microphone", "toggle for the microphone indicator icon")
            checked: root.page.value("privacyShowMicIcon")
            onToggled: checked => root.page.set("privacyShowMicIcon", checked)
        }

        SettingsToggleRow {
            iconName: "camera_video"
            text: I18n.tr("Camera", "toggle for the camera indicator icon")
            checked: root.page.value("privacyShowCameraIcon")
            onToggled: checked => root.page.set("privacyShowCameraIcon", checked)
        }

        SettingsToggleRow {
            iconName: "screen_share"
            text: I18n.tr("Screen sharing")
            checked: root.page.value("privacyShowScreenShareIcon")
            onToggled: checked => root.page.set("privacyShowScreenShareIcon", checked)
        }
    }
}
