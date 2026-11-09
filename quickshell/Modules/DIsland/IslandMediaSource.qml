pragma ComponentBehavior: Bound

import QtQuick
import qs.Modules.SurfaceWidgets

MediaActivitySource {
    id: root
    required property IslandController controller
    Component.onCompleted: {
        controller.updateMediaAvailability(available);
    }
    onAvailableChanged: {
        controller.updateMediaAvailability(available);
        if (available)
            controller.flashMediaTitle();
    }
    onTitleChanged: controller.flashMediaTitle()
}
