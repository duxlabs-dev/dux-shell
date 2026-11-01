pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modules.ControlCenter

CcTileContent {
    id: root

    property var actions: []
    readonly property int capacity: Math.max(0, Math.floor((height + Theme.groupedListGap) / (CcMetrics.rowHeight + Theme.groupedListGap)))

    CcGroup {
        width: parent.width

        Repeater {
            model: root.actions.slice(0, root.capacity)

            CcListRow {
                required property var modelData

                title: modelData.text
                singleLineTitle: true
                rowColor: Theme.foregroundColor(Theme.chipSurface)
                Accessible.role: modelData.active === undefined ? Accessible.Button : modelData.toggle ? Accessible.CheckBox : Accessible.RadioButton
                Accessible.checkable: modelData.active !== undefined
                Accessible.checked: active
                Accessible.onToggleAction: {
                    if (enabled)
                        modelData.trigger();
                }
                iconName: modelData.icon || ""
                active: modelData.active ?? false
                enabled: modelData.enabled !== false
                clickable: true
                paddingH: Theme.spacingM
                onClicked: modelData.trigger()
            }
        }
    }
}
