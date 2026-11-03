pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets

Item {
    id: root

    required property var notificationModel
    required property var controller
    property bool dense: false
    property real iconSize: 36

    readonly property bool isVertical: root.controller.isVertical
    readonly property string headerText: root.notificationModel.appName + (root.notificationModel.timeText ? " · " + root.notificationModel.timeText : "")
    readonly property string summaryText: root.dense && root.notificationModel.appName ? root.notificationModel.appName + " · " + root.notificationModel.summary : root.notificationModel.summary
    readonly property real measuredWidth: Theme.spacingS * 3 + root.iconSize + Theme.spacingXS + Math.max(root.dense ? 0 : headerLabel.implicitWidth, summaryLabel.implicitWidth)

    function pushMeasuredLength() {
        root.controller.setNotificationContentLength(root.isVertical ? root.iconSize + Theme.spacingS * 2 : root.measuredWidth);
    }

    onMeasuredWidthChanged: root.pushMeasuredLength()
    onIsVerticalChanged: root.pushMeasuredLength()
    Component.onCompleted: root.pushMeasuredLength()

    // A side strip only fits the sender's icon; the text lives in the expanded face.
    DCircularImage {
        anchors.centerIn: parent
        visible: root.isVertical
        width: root.iconSize
        height: width
        imageSource: root.notificationModel.imageSource
        fallbackIcon: root.notificationModel.fallbackIcon
        fallbackText: root.notificationModel.fallbackText
        cacheImages: false
    }

    Row {
        visible: !root.isVertical
        anchors {
            fill: parent
            leftMargin: Theme.spacingS
            rightMargin: Theme.spacingS
        }
        spacing: Theme.spacingS

        DCircularImage {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: width
            imageSource: root.notificationModel.imageSource
            fallbackIcon: root.notificationModel.fallbackIcon
            fallbackText: root.notificationModel.fallbackText
            cacheImages: false
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - root.iconSize - parent.spacing
            spacing: 1

            StyledText {
                id: headerLabel

                width: parent.width
                visible: !root.dense
                text: root.headerText
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            StyledText {
                id: summaryLabel

                width: parent.width
                text: root.summaryText
                color: Theme.surfaceText
                font.pixelSize: root.dense ? Theme.fontSizeSmall : Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
