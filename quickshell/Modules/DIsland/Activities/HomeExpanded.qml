pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.DDash

DashTabFace {
    id: root

    activityId: "home"
    entryId: DashRegistry.overviewId
    tabComponent: Component {
        OverviewTab {
            live: root.live
            editMode: root.editMode
            rowBudget: root.controller.dashboardRowBudget
            transientSurfaceTracker: root.controller.transientSurfaces
            preferredFocusId: root.controller.overviewFocusId
            onTabRequested: id => root.controller.requestDashTab(id)
            onCardFocusChanged: id => root.controller.overviewFocusId = id
        }
    }
}
