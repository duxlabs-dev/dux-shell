pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Item {
    id: root
    property bool shown: true
    property bool ready: false
    property int duration: Theme.shortDuration
    readonly property bool retained: shown || opacity > 0.001
    opacity: ready && shown ? 1 : 0
    visible: retained
    enabled: shown
    Component.onCompleted: ready = true

    Behavior on opacity {
        NumberAnimation {
            duration: SettingsData.reduceMotion ? 0 : root.duration
            easing.type: Easing.OutCubic
        }
    }
}
