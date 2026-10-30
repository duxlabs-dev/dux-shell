pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Notifications
import qs.Modules.DIsland.Kit
import "../../../Common/IslandArrival.js" as Arrival
import "../../../Common/IslandKit.js" as Kit
import "../../../DCommon/Common/Contrast.js" as Contrast

// One info on the arrival card (ArrivalCard): its icon and rings, title, detail and buttons, rolled in or out by the card.
Item {
    id: page

    // The card this page sits on (ArrivalCard): its size, places and flights.
    required property ArrivalCard card

    property var info: null
    property real shift: 0
    readonly property real titleCenter: texts.y + title.height / 2

    width: page.card.width
    height: page.card.height
    // A newcomer rolls in from below, going through the burst rolls sideways.
    x: page.card.rollVertical ? 0 : page.shift
    y: (page.card.rollVertical ? page.shift : 0) + page.card.lift

    IslandAlertWave {
        id: ring

        base: icon.width
        reach: page.card.ringReach
        rings: 2
        // A light stock theme's error falls back to a pale tone (Theme.error): the rings keep 3:1 on the island's surface.
        color: page.ringing ? Theme.primary : Contrast.readableOnAll([Theme.surface, Theme.surfaceContainer, Theme.surfaceContainerHigh, Theme.surfaceContainerHighest], [Theme.error, Theme.surfaceText], 3)
        cycles: page.ringing ? 0 : 1
        spring: page.ringing ? page.card.ringSpring : null
        x: icon.x + (icon.width - width) / 2
        y: icon.y + (icon.height - height) / 2
        opacity: page.card.hand.shared
        scale: page.card.iconFly?.scale ?? 1
        transform: Translate {
            x: page.card.iconFly?.x ?? 0
            y: page.card.iconFly?.y ?? 0
        }
    }

    // An incoming call rings until it goes, its shape rocking on each ring.
    readonly property bool ringing: page.info?.call === true

    // An important info as it shows: a critical one rings twice out of its shape, like a phone; a call keeps ringing.
    function announce() {
        if (icon.critical || page.ringing)
            ring.play();
        else
            ring.stop();
    }

    function silence() {
        ring.stop();
    }

    IslandNoticeIcon {
        id: icon

        x: page.card.pad
        y: page.card.pad
        width: NotificationMetrics.appIconSize
        height: width
        imageSource: page.info?.image ?? ""
        fallbackIcon: page.info?.icon ?? "material:notifications"
        fallbackText: page.info?.fallbackText ?? ""
        alert: Arrival.alertOf(page.info)
        rotation: ring.swing * Kit.ringTilt
        opacity: page.card.hand.shared
        scale: page.card.iconFly?.scale ?? 1
        transform: Translate {
            x: page.card.iconFly?.x ?? 0
            y: page.card.iconFly?.y ?? 0
        }
    }

    Column {
        id: texts

        anchors.verticalCenter: icon.verticalCenter
        x: icon.x + icon.width + NotificationMetrics.iconSpacing
        width: page.width - x - page.card.pad - page.card.closeWidth - Theme.spacingXS
        spacing: NotificationMetrics.contentSpacing / 2

        StyledText {
            id: title

            width: parent.width
            transformOrigin: Item.Left
            scale: page.card.titleFly?.scale ?? 1
            transform: Translate {
                x: page.card.titleFly?.x ?? 0
                y: page.card.titleFly?.y ?? 0
            }
            text: page.info?.title ?? ""
            color: Theme.blendAlpha(Theme.surfaceText, page.card.hand.shared)
            font.pixelSize: NotificationMetrics.summarySize
            font.weight: Theme.fontWeightMedium
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        StyledText {
            width: parent.width
            visible: text !== ""
            // Popups hide the message until expanded (DMS's privacy mode): the card shows unasked, so it keeps the
            // popup's placeholder; the body shows once the user opens the notification.
            text: page.info?.wrapper && SettingsData.notificationPopupPrivacyMode ? I18n.tr("Message Content", "notification privacy mode placeholder") : (page.info?.detail ?? "")
            color: Theme.blendAlpha(Theme.surfaceVariantText, page.card.hand.cardOwn)
            font.pixelSize: NotificationMetrics.bodySize
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }
    }

    IslandButtonRow {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: page.card.pad
            // Fades in at its own place: only the rows above ride the lift.
            bottomMargin: page.card.pad + page.card.lift
        }
        height: Theme.buttonHeightS
        visible: (page.info?.action ?? "") !== ""
        opacity: page.card.hand.cardOwn

        // In reading order, which is also the Tab order: the main action at the end.
        IslandButton {
            role: "plain"
            text: I18n.tr("Dismiss", "island notification face: dismiss button")
            onClicked: page.card.notificationModel.dismiss()
        }

        IslandButton {
            role: "primary"
            text: page.info?.action ?? ""
            onClicked: page.card.notificationModel.activate()
        }
    }
}
