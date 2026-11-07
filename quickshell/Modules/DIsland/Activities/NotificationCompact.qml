pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.DIsland.Kit
import "../../../Common/IslandArrival.js" as Arrival
import "../../../Common/IslandKit.js" as Kit

Item {
    id: root

    required property var notificationModel
    required property var controller
    property bool dense: false
    property real iconSize: 36
    // How far the island has grown into the arrival card (IslandArrival.grow), and the card's places of the icon and
    // title: they fly there on the island's spring while handing over to the card's; the header line leaves first.
    property real grow: 0
    property real reveal: 0.35
    property var to: null
    readonly property var hand: Arrival.handover(root.grow, root.reveal)
    readonly property var places: ({
            "icon": {
                "x": Theme.spacingS + root.iconSize / 2,
                "y": root.height / 2,
                "size": root.iconSize,
                "w": root.width,
                "h": root.height
            },
            "title": {
                "x": Theme.spacingS * 2 + root.iconSize,
                "y": texts.y + summaryLabel.y + summaryLabel.height / 2,
                "size": summaryLabel.font.pixelSize,
                "w": root.width,
                "h": root.height
            }
        })
    readonly property var iconFly: root.to && root.grow !== 0 ? Arrival.fly(root.places.icon, root.to.icon, root.grow) : null
    readonly property var titleFly: root.to && root.grow !== 0 ? Arrival.fly(root.places.title, root.to.title, root.grow) : null

    readonly property bool isVertical: root.controller.isVertical
    readonly property string headerText: root.notificationModel.appName + (root.notificationModel.timeText ? " · " + root.notificationModel.timeText : "")
    readonly property string summaryText: root.dense && root.notificationModel.appName ? root.notificationModel.appName + " · " + root.notificationModel.summary : root.notificationModel.summary
    readonly property real measuredWidth: Theme.spacingS * 3 + root.iconSize + Theme.spacingXS + Math.max(root.dense ? 0 : headerLabel.implicitWidth, summaryLabel.implicitWidth)

    function pushMeasuredLength() {
        root.controller.setNotificationContentLength(root.isVertical ? root.iconSize + Theme.spacingS * 2 : root.measuredWidth);
    }

    onMeasuredWidthChanged: root.pushMeasuredLength()
    onIsVerticalChanged: root.pushMeasuredLength()
    Component.onCompleted: {
        root.pushMeasuredLength();
        // A face made while the call already rings (back from a system face) never sees ringing change.
        if (root.ringing)
            rocker.play();
    }

    // The spring a ringing call's shape rocks back on (IslandAlertWave.spring), the wing's.
    property var ringSpring: null
    readonly property bool ringing: root.notificationModel.call === true
    onRingingChanged: root.ringing ? rocker.play() : rocker.stop()

    // A ringing call keeps rocking its shape folded too; no rings, the face is too thin for them.
    IslandAlertWave {
        id: rocker

        visible: root.ringing
        base: root.iconSize
        reach: 1
        rings: 2
        cycles: 0
        ringsShown: false
        spring: root.ringSpring
    }

    // A side strip only fits the sender's icon; the text lives in the expanded face.
    IslandNoticeIcon {
        anchors.centerIn: parent
        visible: root.isVertical
        width: root.iconSize
        height: width
        imageSource: root.notificationModel.imageSource
        fallbackIcon: root.notificationModel.fallbackIcon
        fallbackText: root.notificationModel.fallbackText
        alert: Arrival.alertOf(root.notificationModel)
        rotation: rocker.swing * Kit.ringTilt
    }

    Row {
        visible: !root.isVertical
        anchors {
            fill: parent
            leftMargin: Theme.spacingS
            rightMargin: Theme.spacingS
        }
        spacing: Theme.spacingS

        IslandNoticeIcon {
            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: width
            imageSource: root.notificationModel.imageSource
            fallbackIcon: root.notificationModel.fallbackIcon
            fallbackText: root.notificationModel.fallbackText
            alert: Arrival.alertOf(root.notificationModel)
            rotation: rocker.swing * Kit.ringTilt
            opacity: 1 - root.hand.shared
            scale: root.iconFly?.scale ?? 1
            transform: Translate {
                x: root.iconFly?.x ?? 0
                y: root.iconFly?.y ?? 0
            }
        }

        Column {
            id: texts

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - root.iconSize - parent.spacing
            spacing: 1

            StyledText {
                id: headerLabel

                width: parent.width
                visible: !root.dense
                text: root.headerText
                color: Theme.blendAlpha(Theme.surfaceTextSecondary, root.hand.compactOwn)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            StyledText {
                id: summaryLabel

                width: parent.width
                transformOrigin: Item.Left
                scale: root.titleFly?.scale ?? 1
                transform: Translate {
                    x: root.titleFly?.x ?? 0
                    y: root.titleFly?.y ?? 0
                }
                text: root.summaryText
                color: Theme.blendAlpha(Theme.surfaceText, 1 - root.hand.shared)
                font.pixelSize: root.dense ? Theme.fontSizeSmall : Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }
    }
}
