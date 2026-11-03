pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

Item {
    id: root

    required property var player

    readonly property bool compact: width < Theme.smallBreakpoint
    readonly property var focusTargets: [playButton, previousButton, nextButton, shuffleButton, repeatButton]

    implicitHeight: Theme.buttonHeightM
    implicitWidth: playback.width + modes.width + Theme.spacingL
    height: implicitHeight

    Keys.onPressed: event => event.accepted = FocusNavigation.handleHorizontalKey(event, focusTargets, I18n.isRtl)

    Row {
        id: playback
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        MediaTransportButton {
            id: playButton
            player: root.player
            mediaAction: "play"
            size: root.compact ? "s" : "m"
            widthMode: "wide"
            variant: "filled"
            round: false
            containerColor: MediaAccentService.accentContainer
            contentColor: MediaAccentService.onAccentContainer
        }

        MediaTransportButton {
            id: previousButton
            player: root.player
            mediaAction: "previous"
            size: root.compact ? "s" : "m"
        }

        MediaTransportButton {
            id: nextButton
            player: root.player
            mediaAction: "next"
            size: root.compact ? "s" : "m"
        }
    }

    Row {
        id: modes
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        ModeButton {
            id: shuffleButton
            mediaAction: "shuffle"
        }

        ModeButton {
            id: repeatButton
            mediaAction: "repeat"
        }
    }

    component ModeButton: MediaTransportButton {
        player: root.player
        containerColor: MediaAccentService.accentContainer
        contentColor: MediaAccentService.onAccentContainer
    }
}
