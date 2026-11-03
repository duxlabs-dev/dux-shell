import QtQuick
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Modules.Settings.DesktopWidgetSettings

DesktopWidgetInstanceSettings {
    id: root

    readonly property var styles: ["pill", "expressive", "ring", "minimal", "dots"]
    readonly property var styleLabels: [I18n.tr("Pill", "lock screen password field style"), I18n.tr("Expressive"), I18n.tr("Ring"), I18n.tr("Minimal", "lock screen password field style"), I18n.tr("Dots", "lock screen password field style")]
    readonly property var visibilityModes: ["always", "typing", "never"]
    readonly property var visibilityLabels: [I18n.tr("Always show", "lock screen widget visibility"), I18n.tr("Hide until typing", "lock screen widget visibility"), I18n.tr("Never")]
    readonly property string profileVisibility: cfg.profileVisibility ?? (cfg.showProfileImage === false ? "never" : "always")
    readonly property string passwordVisibility: cfg.passwordVisibility ?? (cfg.showPasswordField === false ? "typing" : "always")

    showAppearance: false

    SettingsDropdownRow {
        text: I18n.tr("Style")
        options: root.styleLabels
        currentValue: root.styleLabels[Math.max(0, root.styles.indexOf(root.cfg.style ?? "expressive"))]
        onValueChanged: value => {
            const idx = root.styleLabels.indexOf(value);
            if (idx >= 0)
                root.updateConfig("style", root.styles[idx]);
        }
    }

    SettingsDropdownRow {
        text: I18n.tr("Profile image", "lock screen toggle, show the user avatar")
        options: root.visibilityLabels
        currentValue: root.visibilityLabels[Math.max(0, root.visibilityModes.indexOf(root.profileVisibility))]
        onValueChanged: value => {
            const index = root.visibilityLabels.indexOf(value);
            if (index >= 0)
                root.updateConfig("profileVisibility", root.visibilityModes[index]);
        }
    }

    SettingsDropdownRow {
        text: I18n.tr("Password field", "lock screen password field visibility setting")
        description: root.passwordVisibility === "typing" ? I18n.tr("Typing reveals the field. Escape hides it again. The editor always shows it.", "lock screen hide until typing behavior") : ""
        options: root.visibilityLabels.slice(0, 2)
        currentValue: root.visibilityLabels[Math.max(0, root.visibilityModes.indexOf(root.passwordVisibility))]
        onValueChanged: value => {
            const index = root.visibilityLabels.indexOf(value);
            if (index >= 0 && index < 2)
                root.updateConfig("passwordVisibility", root.visibilityModes[index]);
        }
    }
}
