pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Widgets

DOSD {
    id: root

    property string iconName: ""
    property color iconColor: Theme.primary
    property bool filled: false

    osdWidth: Theme.osdHeight
    osdHeight: Theme.osdHeight
    enableMouseInteraction: false

    content: Item {
        OsdIcon {
            tonal: false
            anchors.centerIn: parent
            iconName: root.iconName
            iconColor: root.iconColor
            filled: root.filled
        }
    }
}
