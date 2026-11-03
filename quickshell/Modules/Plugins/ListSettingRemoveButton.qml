import QtQuick
import qs.Common
import qs.DCommon.Widgets

Rectangle {
    id: root

    signal clicked

    anchors.right: parent.right
    anchors.rightMargin: Theme.spacingM
    anchors.verticalCenter: parent.verticalCenter
    width: 60
    height: 28
    color: removeArea.containsMouse ? Theme.errorHover : Theme.error
    radius: Theme.cornerRadius

    StyledText {
        anchors.centerIn: parent
        text: I18n.tr("Remove")
        color: Theme.onError
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }

    MouseArea {
        id: removeArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
