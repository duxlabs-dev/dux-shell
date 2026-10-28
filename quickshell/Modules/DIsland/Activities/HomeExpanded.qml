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
            onTabRequested: id => {
                switch (id) {
                case "media":
                    root.controller.requestActivity("media", true, true);
                    break;
                case "weather":
                    if (SettingsData.weatherEnabled)
                        root.controller.requestWeather(false);
                    break;
                case "wellbeing":
                    root.controller.requestActivity("wellbeing", true, true);
                    break;
                case "notifications":
                    root.controller.requestNotificationCenter(false);
                    break;
                }
            }
        }
    }
}
