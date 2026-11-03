import QtQuick
import qs.Common
import qs.Modules.ControlCenter
import qs.DCommon.Widgets

Item {
    id: root

    property string iconName: ""
    property string title: ""
    property string subtitle: ""
    property bool spinning: false
    property color iconColor: Theme.surfaceVariantText
    default property alias content: column.data

    width: parent?.width ?? 0
    implicitHeight: Math.max(CcMetrics.emptyStateMinHeight, column.implicitHeight + Theme.spacingL * 2)
    height: implicitHeight

    Column {
        id: column
        anchors.centerIn: parent
        width: parent.width - Theme.spacingL * 2
        spacing: Theme.spacingS

        DSpinner {
            anchors.horizontalCenter: parent.horizontalCenter
            size: CcMetrics.emptyStateIconSize
            strokeWidth: CcMetrics.spinnerStroke
            color: Theme.primary
            visible: root.spinning
            running: visible
        }

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.iconName
            size: CcMetrics.emptyStateIconSize
            color: root.iconColor
            visible: !root.spinning && root.iconName !== ""
        }

        StyledText {
            width: parent.width
            text: root.title
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.title !== ""
        }

        StyledText {
            width: parent.width
            text: root.subtitle
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.subtitle !== ""
        }
    }
}
