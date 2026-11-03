pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.DDash

DashTabFace {
    id: root

    activityId: "media"
    tabComponent: Component {
        MediaPlayerTab {
            live: root.live
        }
    }
}
