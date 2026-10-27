pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import qs.Modules.DDash.Media
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

Card {
    id: root

    property MprisPlayer activePlayer: MprisController.activePlayer
    property bool live: Window.window?.visible ?? false
    property bool isSeeking: false

    readonly property bool playing: activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property bool compact: height < DashMetrics.heightForRows(2)
    readonly property bool narrow: width - pad * 2 < DashMetrics.overviewTransportWidth
    readonly property bool tiny: compact && width - pad * 2 < DashMetrics.overviewTransportWidth + Theme.iconButtonSize
    readonly property bool showArtwork: !compact && !narrow && height >= DashMetrics.heightForRows(3)
    readonly property string titleText: MprisController.stableTitle || I18n.tr("Unknown Track")
    readonly property string artistText: MprisController.stableArtist || I18n.tr("Unknown Artist")
    readonly property string artUrl: TrackArtService.resolvedArtUrl
    readonly property color accent: MediaAccentService.accent
    readonly property bool showSeekbar: options.seekbar !== false && !tiny
    readonly property bool bento: options.playerStyle === "bento"
    readonly property bool inlineMetadata: compact && titleLabel.implicitHeight + artistLabel.implicitHeight + trackText.spacing > transport.y - Theme.spacingXS
    readonly property var playbackFocusTargets: [playButton, previousButton, nextButton].concat(seekbar.canSeek ? [seekbar] : [])

    entryId: "media"
    clickable: true
    pad: Theme.spacingM

    Keys.onShortcutOverride: event => {
        if (!root.interactive || event.key !== Qt.Key_F6)
            return;
        const targets = root.playbackFocusTargets.filter(item => item.visible && item.enabled);
        const boundary = event.modifiers & Qt.ShiftModifier ? targets[0] : targets[targets.length - 1];
        event.accepted = targets.length > 0 && !FocusNavigation.containsFocus(boundary);
    }

    function handleKeyEvent(event) {
        if (!interactive || event.key !== Qt.Key_F6)
            return false;
        return FocusNavigation.moveFocus(playbackFocusTargets, !!(event.modifiers & Qt.ShiftModifier));
    }

    Timer {
        interval: DashMetrics.mediaPositionPollInterval
        running: root.live && root.visible && root.interactive && root.showSeekbar && root.playing && !root.isSeeking
        repeat: true
        onTriggered: MprisController.refreshPosition(root.activePlayer)
    }

    Loader {
        anchors.fill: parent
        anchors.margins: -root.pad
        active: root.live && MediaOptions.albumArtBackdrop && !!root.activePlayer

        sourceComponent: MediaArtBackdrop {
            radius: root.radius
            activePlayer: root.activePlayer
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.spacingXS
        visible: !root.activePlayer

        DIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "music_note"
            size: Theme.iconSizeLarge
            color: root.accentColor
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: I18n.tr("No Media")
            font.pixelSize: Theme.fontSizeSmall
            color: root.mutedColor
        }
    }

    Item {
        id: content
        anchors.fill: parent
        visible: !!root.activePlayer
        enabled: root.interactive

        MediaArtSurface {
            id: artwork
            anchors.right: parent.right
            anchors.top: parent.top
            width: root.showArtwork ? Math.max(0, Math.min(DashMetrics.overviewArtHero, parent.width / 3, seekBlock.y - Theme.spacingM)) : 0
            height: width
            artStyle: root.options.artStyle ?? "rounded"
            visible: root.showArtwork

            MediaArtwork {
                anchors.fill: parent
                cornerRadius: 0
                artUrl: root.artUrl
            }
        }

        Column {
            id: trackText
            anchors.left: parent.left
            anchors.right: artwork.visible ? artwork.left : parent.right
            anchors.rightMargin: artwork.visible ? Theme.spacingM : 0
            anchors.top: parent.top
            spacing: Theme.spacingXXS
            visible: !root.tiny

            StyledText {
                id: titleLabel
                width: parent.width
                text: root.inlineMetadata ? root.titleText + " · " + root.artistText : root.titleText
                fontToken: root.options.titleFont ?? MediaOptions.defaultTitleFont
                font.pixelSize: root.compact ? Theme.fontSizeMedium : Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                color: root.contentColor
                elide: Text.ElideRight
                maximumLineCount: root.showArtwork ? 2 : 1
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }

            StyledText {
                id: artistLabel
                width: parent.width
                visible: !root.inlineMetadata
                text: root.artistText
                font.pixelSize: Theme.fontSizeSmall
                color: root.mutedColor
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Item {
            id: seekBlock
            anchors.left: parent.left
            anchors.right: root.compact && !root.tiny ? transport.left : parent.right
            anchors.rightMargin: root.compact && !root.tiny ? Theme.spacingS : 0
            y: root.compact ? transport.y + (transport.height - height) / 2 : transport.y - height - Theme.spacingS
            height: DashMetrics.overviewSeekHeight
            visible: root.showSeekbar

            DSeekbar {
                id: seekbar
                anchors.fill: parent
                activePlayer: root.activePlayer
                stableLength: MprisController.activePlayerStableLength
                accentColor: root.accent
                accentTrackColor: MediaAccentService.accentTrack
                accentSubtleColor: MediaAccentService.accentSubtle
                isSeeking: root.isSeeking
                onIsSeekingChanged: root.isSeeking = isSeeking
            }
        }

        Item {
            id: transport

            readonly property bool stacked: root.narrow && !root.tiny
            readonly property bool centered: root.bento && !stacked && !root.tiny
            readonly property bool medium: !root.compact && width >= Theme.buttonHeightM * 4
            readonly property real buttonHeight: medium ? Theme.buttonHeightM : Theme.buttonHeightS
            readonly property real spacing: root.compact || stacked ? Theme.spacingXS : Theme.spacingS

            anchors.right: parent.right
            width: root.tiny ? parent.width : (root.compact ? DashMetrics.overviewTransportWidth : parent.width)
            height: stacked ? buttonHeight * 2 + spacing : buttonHeight
            y: root.tiny ? (parent.height - height) / 2 : parent.height - height

            DIconButton {
                id: playButton
                x: transport.centered ? previousButton.width + transport.spacing : 0
                anchors.top: parent.top
                size: transport.medium ? "m" : "s"
                width: {
                    if (root.tiny || transport.stacked)
                        return parent.width;
                    if (root.compact)
                        return DashMetrics.overviewPlayWidth;
                    return (parent.width - transport.spacing * 2) / 2;
                }
                variant: "filled"
                round: false
                checkable: true
                checked: root.playing
                iconFilled: false
                radius: Theme.buttonRadius(width, height, buttonSize, pressed, !root.bento && checked)
                iconName: root.playing ? "pause" : "play_arrow"
                Accessible.name: root.playing ? I18n.tr("Pause") : I18n.tr("Play")
                enabled: !!root.activePlayer?.canTogglePlaying
                contentColor: MediaAccentService.onAccentContainer
                containerColor: MediaAccentService.accentContainer
                onClicked: root.activePlayer.togglePlaying()
            }

            DIconButton {
                id: previousButton
                x: transport.stacked || transport.centered ? 0 : playButton.width + transport.spacing
                anchors.bottom: parent.bottom
                size: transport.medium ? "m" : "s"
                width: transport.stacked ? (parent.width - transport.spacing) / 2 : (parent.width - playButton.width - transport.spacing * 2) / 2
                variant: root.bento ? "tonal" : "standard"
                round: !root.bento
                radius: Theme.buttonRadius(width, height, buttonSize, pressed, round)
                containerColor: MediaAccentService.accentSecondaryContainer
                contentColor: root.bento ? MediaAccentService.onAccentSecondaryContainer : Theme.onSecondaryContainer
                iconName: "skip_previous"
                Accessible.name: I18n.tr("Previous")
                enabled: !!root.activePlayer?.canGoPrevious || (!!root.activePlayer?.canSeek && root.activePlayer.position > 8)
                visible: !root.tiny
                onClicked: MprisController.previousOrRewind()
            }

            DIconButton {
                id: nextButton
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                size: transport.medium ? "m" : "s"
                width: previousButton.width
                variant: previousButton.variant
                round: previousButton.round
                radius: Theme.buttonRadius(width, height, buttonSize, pressed, round)
                containerColor: previousButton.containerColor
                contentColor: previousButton.contentColor
                iconName: "skip_next"
                Accessible.name: I18n.tr("Next")
                enabled: !!root.activePlayer?.canGoNext
                visible: !root.tiny
                onClicked: MprisController.next()
            }
        }
    }
}
