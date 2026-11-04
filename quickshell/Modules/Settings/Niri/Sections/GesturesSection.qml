pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.Settings.Niri.Sections.Gestures

Column {
    readonly property string sectionId: "gestures"
    readonly property Component sidePane: Component {
        GestStage {
            gesture: gestures.gesture
            sentence: gestures.sentence
            replays: gestures.replays
        }
    }

    spacing: Theme.spacingM

    GesturesCard {
        id: gestures
    }
    CornersCard {}
    GestDragCard {}
}
