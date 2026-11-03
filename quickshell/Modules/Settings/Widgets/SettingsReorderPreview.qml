import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    required property var group

    visible: group.active && group.target !== group.source
    x: group.source?.mapToItem(group.coordinateItem, 0, 0).x ?? 0
    y: group.position.y - (group.source?.pressOffset ?? 0)
    width: group.source?.width ?? 0
    height: group.sourceItem?.height ?? 0
    title: group.sourceItem?.title ?? ""
    subtitle: group.sourceItem?.subtitle ?? ""
    iconName: group.sourceItem?.iconName ?? ""
    rowColor: Theme.blend(SettingsMetrics.rowColor, Theme.onSurface, Theme.stateLayerDrag)
    topRadius: Theme.groupedListOuterRadius
    bottomRadius: Theme.groupedListOuterRadius
    z: 100

    leading: Item {
        width: Theme.iconButtonSize
        height: Theme.iconButtonSize

        DIcon {
            anchors.centerIn: parent
            name: "drag_indicator"
            size: Theme.iconSizeMedium
            color: Theme.onSurfaceVariant
        }
    }
}
