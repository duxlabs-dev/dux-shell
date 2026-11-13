pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    property string iconName: ""
    property string label: ""
    property real minWidth: 180
    property real horizontalPadding: Theme.spacingL
    property real itemSpacing: Theme.spacingM
    property real extraWidthReserve: 0
    readonly property real labelWidth: Math.ceil(labelMetrics.width)

    osdWidth: Math.min(screenWidth - Theme.spacingM * 2, Math.max(minWidth, horizontalPadding * 2 + Theme.buttonHeightS + itemSpacing + labelWidth + extraWidthReserve))
    osdHeight: Theme.osdHeight
    autoHideInterval: 2000
    enableMouseInteraction: false

    StyledTextMetrics {
        id: labelMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: root.label
    }

    content: Item {
        anchors.fill: parent

        RowLayout {
            anchors {
                fill: parent
                leftMargin: root.horizontalPadding
                rightMargin: root.horizontalPadding
            }
            spacing: root.itemSpacing

            OsdIcon {
                Layout.alignment: Qt.AlignVCenter
                iconName: root.iconName
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
