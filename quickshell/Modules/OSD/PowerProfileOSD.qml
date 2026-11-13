import QtQuick
import qs.Common
import qs.Services

IconOSD {
    id: root

    osdKind: "powerProfile"
    iconName: profileIcon

    property int currentProfile: 0
    property string profileIcon: "settings"

    Connections {
        target: PowerProfileWatcher

        function onProfileChanged(profile) {
            root.currentProfile = profile;
            root.profileIcon = Theme.getPowerProfileIcon(profile);
            root.show();
        }
    }

    Component.onCompleted: {
        if (typeof PowerProfileWatcher !== "undefined") {
            root.currentProfile = PowerProfileWatcher.currentProfile;
            root.profileIcon = Theme.getPowerProfileIcon(PowerProfileWatcher.currentProfile);
        }
    }
}
