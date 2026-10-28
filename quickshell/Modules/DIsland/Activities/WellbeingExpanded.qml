pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.DDash

DashTabFace {
    id: root

    activityId: "wellbeing"
    tabComponent: Component {
        WellbeingTab {
            live: root.live
            transientSurfaceTracker: root.controller.transientSurfaces
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("wellbeing")
    Component.onDestruction: root.controller.setVisualsReady("wellbeing", false)
}
