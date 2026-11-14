import QtQuick
import qs.Common

IconOSD {
    id: root

    osdKind: "doNotDisturb"
    iconName: dndActive ? "notifications_off" : "notifications"
    iconColor: dndActive ? Theme.primary : Theme.outline

    readonly property bool dndActive: SessionData.doNotDisturb
    property bool stateInitialized: false

    onDndActiveChanged: {
        if (stateInitialized)
            root.show();
    }

    Component.onCompleted: stateInitialized = true
}
