import QtQuick
import qs.Common
import qs.DCommon.Widgets

SettingsRow {
    id: root

    property string text: ""
    property string noteIconName: "warning"
    property color tint: Theme.warning
    property color tintBackground: Theme.warningHover
    property bool monospace: false
    property real maxHeight: 0

    body: Rectangle {
        readonly property real naturalHeight: noteRow.implicitHeight + Theme.spacingS * 2

        width: parent.width
        height: root.maxHeight > 0 ? Math.min(root.maxHeight, naturalHeight) : naturalHeight
        radius: Theme.cornerRadius
        color: root.tintBackground

        DFlickable {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            contentHeight: noteRow.implicitHeight
            interactive: contentHeight > height
            wheelEnabled: interactive
            clip: interactive

            Row {
                id: noteRow
                width: parent.width
                spacing: Theme.spacingS

                DIcon {
                    visible: root.noteIconName !== ""
                    name: root.noteIconName
                    size: Theme.iconSizeSmall
                    color: root.tint
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: root.noteIconName !== "" ? parent.width - parent.spacing - Theme.iconSizeSmall : parent.width
                    text: root.text
                    font.pixelSize: Theme.fontSizeSmall
                    isMonospace: root.monospace
                    color: root.tint
                    wrapMode: root.monospace ? Text.Wrap : Text.WordWrap
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
