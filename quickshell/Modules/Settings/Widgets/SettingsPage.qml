import QtQuick
import qs.Common
import qs.DCommon.Widgets

DFlickable {
    id: root

    default property alias content: column.data
    property alias spacing: column.spacing
    property alias columnWidth: column.width
    property real contentMaxWidth: SettingsMetrics.contentMaxWidth
    property Item fabBar: null

    anchors.fill: parent
    anchors.leftMargin: -SettingsMetrics.focusGutter
    anchors.rightMargin: -SettingsMetrics.focusGutter
    anchors.topMargin: -SettingsMetrics.focusGutter
    clip: true
    contentHeight: column.height + Theme.spacingXL
    contentWidth: width
    fadeSideInset: (width - column.width) / 2

    Column {
        id: column
        topPadding: Theme.spacingXS + SettingsMetrics.focusGutter
        width: Math.min(root.contentMaxWidth, parent.width - SettingsMetrics.focusGutter * 2)
        bottomPadding: SettingsMetrics.pagePaddingV + (root.fabBar?.reservedHeight ?? 0)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: SettingsMetrics.cardGap
    }
}
