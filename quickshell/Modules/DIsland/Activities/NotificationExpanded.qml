pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.DIsland.Kit
import "../../../Common/IslandArrival.js" as Arrival

Item {
    id: root

    required property var notificationModel

    Item {
        anchors {
            fill: parent
            margins: 22
        }

        Row {
            id: header

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 46
            spacing: Theme.spacingM

            IslandNoticeIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 46
                imageSource: root.notificationModel.imageSource
                fallbackIcon: root.notificationModel.fallbackIcon
                fallbackText: root.notificationModel.fallbackText
                alert: Arrival.alertOf(root.notificationModel)
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 46 - closeButton.width - parent.spacing * 2
                spacing: Theme.spacingXXS

                StyledText {
                    width: parent.width
                    text: root.notificationModel.appName
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: root.notificationModel.timeText
                    color: Theme.surfaceTextSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }

            IslandButton {
                id: closeButton

                anchors.verticalCenter: parent.verticalCenter
                role: "plain"
                iconName: "close"
                Accessible.name: I18n.tr("Dismiss")
                onClicked: root.notificationModel.dismiss()
            }
        }

        Column {
            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                topMargin: Theme.spacingM
                bottom: actions.top
                bottomMargin: Theme.spacingM
            }
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: root.notificationModel.summary
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.notificationModel.body
                color: Theme.surfaceTextMedium
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }

        // Shown only when the app announced freedesktop inline reply; Enter sends.
        DTextField {
            id: replyField

            anchors {
                left: parent.left
                right: actions.left
                rightMargin: Theme.spacingS
                verticalCenter: actions.verticalCenter
            }
            visible: root.notificationModel.canReply
            placeholderText: root.notificationModel.replyPlaceholder
            onAccepted: root.notificationModel.reply(text)
            onVisibleChanged: {
                text = "";
                if (visible)
                    Qt.callLater(forceActiveFocus);
            }
        }

        Row {
            id: actions

            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            spacing: Theme.spacingS

            IslandButton {
                role: "plain"
                text: I18n.tr("Dismiss", "island notification face: dismiss button")
                onClicked: root.notificationModel.dismiss()
            }

            IslandButton {
                visible: root.notificationModel.hasAction
                role: "primary"
                text: root.notificationModel.actionLabel
                onClicked: root.notificationModel.activate()
            }
        }
    }
}
