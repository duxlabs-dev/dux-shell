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
    // A page shown inside another page's column takes its content height and leaves scrolling to that page
    readonly property Item embedHost: {
        for (let p = parent; p; p = p.parent) {
            if (p.embedsSettingsPage === true)
                return p;
        }
        return null;
    }
    readonly property bool embedded: embedHost !== null

    anchors.fill: parent
    anchors.leftMargin: embedded ? 0 : -SettingsMetrics.focusGutter
    anchors.rightMargin: embedded ? 0 : -SettingsMetrics.focusGutter
    anchors.topMargin: embedded ? 0 : -SettingsMetrics.focusGutter
    clip: !embedded
    interactive: !embedded
    wheelEnabled: !embedded
    showScrollBar: !embedded
    fadeEdges: !embedded
    contentHeight: column.height + Theme.spacingXL
    contentWidth: width
    fadeSideInset: (width - column.width) / 2

    Binding {
        target: root.embedHost
        property: "pageHeight"
        value: column.height
        when: root.embedded
    }

    Column {
        id: column
        topPadding: root.embedded ? 0 : Theme.spacingXS + SettingsMetrics.focusGutter
        width: root.embedded ? parent.width : Math.min(root.contentMaxWidth, parent.width - SettingsMetrics.focusGutter * 2)
        bottomPadding: (root.embedded ? 0 : SettingsMetrics.pagePaddingV) + (root.fabBar?.reservedHeight ?? 0)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: SettingsMetrics.cardGap
    }
}
