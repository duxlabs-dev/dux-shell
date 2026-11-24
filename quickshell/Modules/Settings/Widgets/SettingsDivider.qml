import QtQuick
import qs.Widgets

DDivider {
    height: vertical ? SettingsMetrics.splitDividerHeight : thickness
    visible: !(parent?.isSettingsGroupHost ?? false)
    anchors.verticalCenter: vertical ? parent?.verticalCenter : undefined
}
