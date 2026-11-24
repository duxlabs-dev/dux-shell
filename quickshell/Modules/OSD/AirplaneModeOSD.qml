import QtQuick
import qs.Common
import qs.Services

IconOSD {
    id: root

    readonly property bool airplaneMode: DMSService.airplaneMode
    property bool stateInitialized: false

    osdKind: "airplaneMode"
    iconName: airplaneMode ? "airplanemode_active" : "airplanemode_inactive"
    iconColor: airplaneMode ? Theme.primary : Theme.outline

    onAirplaneModeChanged: {
        if (stateInitialized && DMSService.rfkillStateInitialized)
            root.show();
    }

    Component.onCompleted: stateInitialized = true
}
