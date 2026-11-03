import QtQuick
import qs.Common
import qs.DCommon.Widgets

Column {
    id: root

    property string headerText: ""
    property string detailsText: ""
    // !TODO: plugin API only, popouts no longer draw a close button; drop once plugins stop setting it
    property bool showCloseButton: false
    property var closePopout: null
    property var parentPopout: null
    property alias headerActions: headerActionsLoader.sourceComponent

    readonly property int headerHeight: popoutHeader.visible ? popoutHeader.height : 0
    readonly property int detailsHeight: popoutDetails.visible ? popoutDetails.implicitHeight : 0

    spacing: 0

    Item {
        id: popoutHeader
        width: parent.width
        height: 40
        visible: headerText.length > 0

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerText
            font.pixelSize: Theme.fontSizeLarge + 4
            color: Theme.surfaceText
        }

        Loader {
            id: headerActionsLoader
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StyledText {
        id: popoutDetails
        width: parent.width
        leftPadding: Theme.spacingS
        bottomPadding: Theme.spacingS
        text: root.detailsText
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        visible: detailsText.length > 0
        wrapMode: Text.WordWrap
    }
}
