pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Notifications
import qs.Modules.DIsland.Kit
import "../../../Common/IslandArrival.js" as Arrival
import "../../../Common/IslandArrivalGestures.js" as Gestures
import "../../../Common/IslandKit.js" as Kit

// The island's card while infos arrive: the shown info rolls over the last one sideways, page dots top right with the
// countdown dot. Sized by the controller (arrival.bigTarget); the surface fades it in with the island's growth.
Item {
    id: root

    required property var controller
    required property var notificationModel
    property bool reducedMotion: false
    // The finger's way sideways while it drags the card.
    property real dragX: 0

    readonly property real pad: NotificationMetrics.cardPadding
    readonly property real reach: Theme.spacingXL * Gestures.rollReach
    readonly property int rollMs: root.reducedMotion ? 0 : Kit.beat("roll", Theme.currentAnimationBaseDuration)
    readonly property int rollOutMs: root.reducedMotion ? 0 : Kit.beat("rollOut", Theme.currentAnimationBaseDuration)

    width: root.controller.arrival.cardWidth
    height: root.controller.arrival.cardHeight
    // Taps reach the card once it owns the island.
    enabled: root.hand.cardOwn >= 0.5

    // How far the island has grown into this card (IslandArrival.grow) and the compact face's places of the icon and
    // title: they fly from there on the island's spring while the compact face hands them over; the card's own lines
    // (detail, buttons, dots, close) come in late and leave first.
    property real grow: 1
    property real reveal: 0.35
    property var from: null
    readonly property var hand: Arrival.handover(root.grow, root.reveal)
    // While the card's own rows below (the buttons) are hidden, what is left sits in the middle of the card, then rises
    // to its place as they come in: the visible content stays centred in the island.
    readonly property real lift: (1 - root.hand.cardOwn) * (root.height / 2 - root.pad - NotificationMetrics.appIconSize / 2)
    readonly property var places: ({
            "icon": {
                "x": root.pad + NotificationMetrics.appIconSize / 2,
                "y": root.pad + NotificationMetrics.appIconSize / 2 + root.lift,
                "size": NotificationMetrics.appIconSize,
                "w": root.width,
                "h": root.height
            },
            "title": {
                "x": root.pad + NotificationMetrics.appIconSize + NotificationMetrics.iconSpacing,
                "y": incoming.titleCenter + root.lift,
                "size": NotificationMetrics.summarySize,
                "w": root.width,
                "h": root.height
            }
        })
    readonly property var iconFly: root.from && root.grow !== 1 ? Arrival.fly(root.places.icon, root.from.icon, 1 - root.grow) : null
    readonly property var titleFly: root.from && root.grow !== 1 ? Arrival.fly(root.places.title, root.from.title, 1 - root.grow) : null

    // An important info's rings reach this many times its icon, inside the card's padding.
    readonly property real ringReach: 1 + 2 * root.pad / NotificationMetrics.appIconSize
    // What its pages read of the roll and of the close button.
    readonly property bool rollVertical: roll.vertical
    readonly property real closeWidth: closeButton.width
    // The spring a ringing call's shape rocks back on (IslandAlertWave.spring), the wing's.
    property var ringSpring: null

    property var shownInfo: root.controller.arrival.current
    property var leavingInfo: null
    readonly property int shownRevision: root.controller.arrival.shown
    Component.onCompleted: incoming.announce()
    onShownRevisionChanged: {
        const next = root.controller.arrival.current;
        if (!next) {
            incoming.silence();
            return;
        }
        Qt.callLater(incoming.announce);
        const dir = root.controller.arrival.burst.dir;
        root.leavingInfo = dir !== 0 && root.shownInfo !== next ? root.shownInfo : null;
        root.shownInfo = next;
        if (!root.leavingInfo || root.rollMs <= 0) {
            roll.stop();
            incoming.shift = 0;
            incoming.opacity = 1;
            root.leavingInfo = null;
            return;
        }
        roll.dir = dir;
        roll.vertical = root.controller.arrival.burst.axis === "y";
        roll.restart();
    }

    ArrivalPage {
        id: outgoing

        card: root
        info: root.leavingInfo
        visible: !!root.leavingInfo
        enabled: false
    }

    ArrivalPage {
        id: incoming

        card: root
        info: root.shownInfo
        x: (roll.vertical ? 0 : incoming.shift) + root.dragX * Gestures.follow
    }

    // A1: one page rolling into the next (M34) on the kit's beats (rollMs, rollOutMs); no kit part rolls pages, and it runs
    // once per page (K1).
    ParallelAnimation {
        id: roll

        property int dir: 1
        property bool vertical: false

        onFinished: root.leavingInfo = null

        NumberAnimation {
            target: incoming
            property: "shift"
            from: roll.dir * root.reach
            to: 0
            duration: root.rollMs
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: incoming
            property: "opacity"
            from: 0
            to: 1
            duration: root.rollMs
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: outgoing
            property: "shift"
            from: 0
            to: -roll.dir * root.reach * Gestures.rollOutReach
            duration: root.rollOutMs
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: outgoing
            property: "opacity"
            from: 1
            to: 0
            duration: root.rollOutMs
            easing.type: Easing.InCubic
        }
    }

    // As on every open card (BubbleCardBase): closes it and the info goes.
    IslandButton {
        id: closeButton

        anchors.right: parent.right
        anchors.rightMargin: root.pad
        y: Math.round(incoming.titleCenter + root.lift - height / 2)
        opacity: root.hand.cardOwn
        role: "quiet"
        iconName: "close"
        buttonHeight: Theme.iconSize + Theme.spacingXS
        activeFocusOnTab: true
        Accessible.name: I18n.tr("Close", "island arrival card: close button, dismisses the info")
        onClicked: root.notificationModel.dismiss()
    }

    IslandPager {
        id: pager

        anchors {
            right: closeButton.left
            top: parent.top
            rightMargin: Theme.spacingXS
            topMargin: (root.pad - height) / 2
        }
        opacity: root.hand.cardOwn
        count: root.controller.arrival.count
        index: root.controller.arrival.burst.index
        countdown: root.controller.arrival.phase === "big" ? root.controller.arrival.countdown : null
        reducedMotion: root.reducedMotion
        onPicked: index => root.controller.arrival.go(index)
    }
}
