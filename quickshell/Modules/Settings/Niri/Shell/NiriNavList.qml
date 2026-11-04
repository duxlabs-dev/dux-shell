pragma ComponentBehavior: Bound

import QtQuick
import qs.Common

Column {
    id: root

    property var sections: []
    property string current: ""
    property var counts: ({})

    signal picked(string id)

    spacing: Theme.spacingXXS

    Repeater {
        model: root.sections

        NiriNavItem {
            required property var modelData
            width: root.width
            iconName: modelData.icon
            text: modelData.text
            active: root.current === modelData.id
            count: root.counts[modelData.id] ?? 0
            iconColor: active ? Theme.onPrimaryContainer : modelData.warn ? Theme.warning : Theme.surfaceText
            onClicked: root.picked(modelData.id)
        }
    }
}
