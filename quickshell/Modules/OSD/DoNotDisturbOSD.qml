import QtQuick
import qs.Common
import qs.Widgets

DOSD {
    id: root

    osdKind: "doNotDisturb"

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    readonly property bool dndActive: SessionData.doNotDisturb
    property bool stateInitialized: false

    onDndActiveChanged: {
        if (stateInitialized)
            root.show();
    }

    Component.onCompleted: stateInitialized = true

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: root.dndActive ? "notifications_off" : "notifications"
            iconColor: root.dndActive ? Theme.primary : Theme.outline
        }
    }
}
