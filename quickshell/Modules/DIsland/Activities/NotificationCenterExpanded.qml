pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.DDash

DashTabFace {
    id: root

    activityId: "notificationcenter"
    entryId: "notifications"
    tabComponent: Component {
        NotificationsTab {
            live: root.live
            transientSurfaceTracker: root.controller.transientSurfaces
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("notificationcenter")
    Component.onDestruction: root.controller.setVisualsReady("notificationcenter", false)
}
