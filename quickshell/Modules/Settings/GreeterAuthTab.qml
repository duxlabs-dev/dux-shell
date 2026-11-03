pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.Modules.Settings.Widgets

Item {
    id: root

    readonly property bool greeterFprintToggleAvailable: SettingsData.greeterFingerprintCanEnable || SettingsData.greeterEnableFprint
    readonly property bool greeterU2fToggleAvailable: SettingsData.greeterU2fCanEnable || SettingsData.greeterEnableU2f

    function greeterFingerprintDescription() {
        if (SettingsData.greeterPamExternallyManaged)
            return I18n.tr("Managed by the primary PAM source", "factor managed by PAM source status");
        if (SettingsData.greeterFingerprintSource === "pam")
            return I18n.tr("PAM already provides fingerprint auth. Enable this to show it at login.", "greeter fingerprint login setting");

        switch (SettingsData.greeterFingerprintReason) {
        case "ready":
            return I18n.tr("Press Apply changes to update the login screen", "greeter auth setting description");
        case "missing_enrollment":
            return I18n.tr("Fingerprint reader detected, but no prints are enrolled yet. You can enable this now and run Sync later.", "greeter fingerprint login setting");
        case "missing_reader":
            return I18n.tr("No fingerprint reader detected", "fingerprint setting status");
        case "missing_pam_support":
            return I18n.tr("Not available - install %1 and %2, or configure %3 PAM", "greeter fingerprint login setting, %1 and %2 are package names, %3 is greetd").arg("fprintd").arg("pam_fprintd").arg("greetd");
        default:
            return I18n.tr("Fingerprint availability could not be confirmed", "fingerprint setting status");
        }
    }

    function greeterU2fDescription() {
        if (SettingsData.greeterPamExternallyManaged)
            return I18n.tr("Managed by the primary PAM source", "factor managed by PAM source status");
        if (SettingsData.greeterU2fSource === "pam")
            return I18n.tr("PAM already provides security-key auth. Enable this to show it at login.", "greeter security key login setting");

        switch (SettingsData.greeterU2fReason) {
        case "ready":
            return I18n.tr("Press Apply changes to update the login screen", "greeter auth setting description");
        case "missing_key_registration":
            return I18n.tr("Security-key support was detected, but no registered key was found yet. You can enable this now and register one later.", "security key setting status");
        case "missing_pam_support":
            return I18n.tr("Not available - install or configure %1, or configure %2 PAM", "greeter security key login setting, %1 is a PAM module, %2 is greetd").arg("pam_u2f").arg("greetd");
        default:
            return I18n.tr("Security-key availability could not be confirmed", "security key setting status");
        }
    }

    function refreshAuthDetection() {
        SettingsData.refreshAuthAvailability();
    }

    onVisibleChanged: {
        if (visible)
            refreshAuthDetection();
    }

    Component.onCompleted: refreshAuthDetection()

    SettingsPage {
        SettingsCard {
            width: parent.width
            iconName: "fingerprint"
            settingKey: "greeterAuth"

            SettingsToggleRow {
                settingKey: "greeterPamExternallyManaged"
                tags: ["greeter", "pam", "managed", "external", "greetd", "auth"]
                text: I18n.tr("Use system PAM authentication", "system PAM policy toggle")
                description: I18n.tr("DMS removes its managed block from %1 and stops write services", "greeter system PAM toggle description, %1 is a PAM config path").arg("/etc/pam.d/greetd")
                checked: SettingsData.greeterPamExternallyManaged
                onToggled: checked => SettingsData.set("greeterPamExternallyManaged", checked)
            }

            SettingsToggleRow {
                settingKey: "greeterEnableFprint"
                tags: ["greeter", "fingerprint", "fprintd", "login", "auth"]
                text: I18n.tr("Fingerprint at login")
                description: root.greeterFingerprintDescription()
                descriptionColor: (SettingsData.greeterFingerprintReason === "ready" || SettingsData.greeterFingerprintReason === "configured_externally") ? Theme.surfaceVariantText : Theme.warning
                checked: SettingsData.greeterEnableFprint
                enabled: root.greeterFprintToggleAvailable && !SettingsData.greeterPamExternallyManaged
                onToggled: checked => SettingsData.set("greeterEnableFprint", checked)
            }

            SettingsToggleRow {
                settingKey: "greeterEnableU2f"
                tags: ["greeter", "u2f", "security", "key", "login", "auth"]
                text: I18n.tr("Security key at login")
                description: root.greeterU2fDescription()
                descriptionColor: (SettingsData.greeterU2fReason === "ready" || SettingsData.greeterU2fReason === "configured_externally") ? Theme.surfaceVariantText : Theme.warning
                checked: SettingsData.greeterEnableU2f
                enabled: root.greeterU2fToggleAvailable && !SettingsData.greeterPamExternallyManaged
                onToggled: checked => SettingsData.set("greeterEnableU2f", checked)
            }
        }

        GreeterSyncFabBar {}
    }
}
