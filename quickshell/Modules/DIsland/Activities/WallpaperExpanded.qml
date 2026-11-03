pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.DDash

DashTabFace {
    id: root

    property var effectiveScreen: null

    activityId: "wallpaper"
    tabComponent: Component {
        WallpaperTab {
            active: root.live
            pagerCachePages: 0
            targetScreen: root.effectiveScreen
            parentPopout: hostContract
            transientSurfaceTracker: root.controller.transientSurfaces
        }
    }

    function beginSession() {
        root.tab?.collapseSearch();
        root.focusFace();
    }

    QtObject {
        id: hostContract

        property var customKeyboardFocus: null

        onCustomKeyboardFocusChanged: root.controller.keyboardYielded = hostContract.customKeyboardFocus !== null
    }

    Connections {
        target: root.controller

        function onSessionStarted(activityId) {
            if (activityId === "wallpaper")
                Qt.callLater(root.beginSession);
        }
    }

    Component.onCompleted: root.controller.markVisualsReady("wallpaper")
    Component.onDestruction: {
        root.controller.keyboardYielded = false;
        root.controller.setVisualsReady("wallpaper", false);
    }
}
