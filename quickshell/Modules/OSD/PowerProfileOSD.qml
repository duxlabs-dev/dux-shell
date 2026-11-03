import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

DOSD {
    id: root

    osdKind: "powerProfile"

    property int currentProfile: 0
    property string profileIcon: "settings"

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    Connections {
        target: PowerProfileWatcher

        function onProfileChanged(profile) {
            if (SettingsData.osdPowerProfileEnabled) {
                root.currentProfile = profile;
                root.profileIcon = Theme.getPowerProfileIcon(profile);
                root.show();
            }
        }
    }

    Component.onCompleted: {
        if (SettingsData.osdPowerProfileEnabled && typeof PowerProfileWatcher !== "undefined") {
            root.currentProfile = PowerProfileWatcher.currentProfile;
            root.profileIcon = Theme.getPowerProfileIcon(PowerProfileWatcher.currentProfile);
        }
    }

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: root.profileIcon
            iconColor: Theme.primary
        }
    }
}
