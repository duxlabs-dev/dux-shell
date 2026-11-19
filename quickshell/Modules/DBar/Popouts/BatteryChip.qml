import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property color labelColor: Theme.surfaceVariantText
    property color valueColor: Theme.surfaceText
    property color borderColor: Theme.withAlpha(Theme.outline, borderAlpha)
    property real maximumWidth: Infinity
    default property alias leading: leadingRow.data

    readonly property real borderAlpha: 0.16

    implicitWidth: content.implicitWidth + Theme.spacingS * 2
    implicitHeight: Theme.buttonHeightXS
    width: Math.min(implicitWidth, maximumWidth)
    radius: Theme.cornerRadiusS
    color: Theme.floatingWindowFieldColor
    border.width: Theme.outlineWidth
    border.color: borderColor
    Accessible.role: Accessible.StaticText
    Accessible.name: label !== "" ? label + ": " + value : value

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        spacing: Theme.spacingXS

        Row {
            id: leadingRow
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacingXS
            visible: children.length > 0
        }

        StyledText {
            Layout.fillWidth: root.label !== ""
            Layout.alignment: Qt.AlignVCenter
            visible: root.label !== ""
            text: root.label
            font.pixelSize: Theme.fontSizeSmall
            color: root.labelColor
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: root.label === ""
            Layout.alignment: Qt.AlignVCenter
            text: root.value
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            font.features: {
                "tnum": 1
            }
            color: root.valueColor
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }
}
