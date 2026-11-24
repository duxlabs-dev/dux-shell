pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.ProfilePicker

DashTabFace {
    id: root

    property var effectiveScreen: null

    activityId: "profiles"
    tabComponent: Component {
        ProfilePickerTab {
            active: root.live
            editMode: root.editMode
            targetScreen: root.effectiveScreen
            islandController: root.controller
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("profiles")
    Component.onDestruction: root.controller.setVisualsReady("profiles", false)
}
