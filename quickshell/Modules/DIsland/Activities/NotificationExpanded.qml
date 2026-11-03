pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

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

            DCircularImage {
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 46
                imageSource: root.notificationModel.imageSource
                fallbackIcon: root.notificationModel.fallbackIcon
                fallbackText: root.notificationModel.fallbackText
                cacheImages: false
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

            DActionButton {
                id: closeButton

                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                Accessible.name: I18n.tr("Dismiss")
                iconSize: 21
                buttonSize: 38
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

        Row {
            id: actions

            anchors {
                right: parent.right
                bottom: parent.bottom
            }
            height: 34
            spacing: Theme.spacingS

            DButton {
                height: parent.height
                radius: Theme.fullRadius(width, height)
                text: I18n.tr("Dismiss", "island notification face: dismiss button")
                backgroundColor: "transparent"
                textColor: Theme.surfaceText
                buttonHeight: parent.height
                horizontalPadding: Theme.spacingL
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.5)
                onClicked: root.notificationModel.dismiss()
            }

            DButton {
                visible: root.notificationModel.hasAction
                height: parent.height
                radius: Theme.fullRadius(width, height)
                text: root.notificationModel.actionLabel
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                buttonHeight: parent.height
                horizontalPadding: Theme.spacingL
                onClicked: root.notificationModel.activate()
            }
        }
    }
}
