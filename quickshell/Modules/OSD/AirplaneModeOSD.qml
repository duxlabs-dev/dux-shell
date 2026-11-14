import QtQuick
import qs.Common
import qs.Services

IconOSD {
    id: root

    osdKind: "airplaneMode"
    iconName: DMSService.airplaneMode ? "airplanemode_active" : "airplanemode_inactive"
    iconColor: DMSService.airplaneMode ? Theme.primary : Theme.outline

    Connections {
        target: DMSService

        function onAirplaneModeChanged() {
            if (DMSService.rfkillStateInitialized)
                root.show();
        }
    }
}
