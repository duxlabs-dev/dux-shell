pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.DDash
import "../../../Common/Format.js" as Format

MediaChromeBase {
    id: root

    artSize: DashMetrics.mediaArtSizeMaterial
    baseHeight: Math.max(DashMetrics.tabMinHeight, padding * 2 + sourceGroup.height + Theme.spacingL * 2 + artSize + transport.height)
    focusTargets: transport.focusTargets.concat(seekbar.canSeek ? [seekbar] : [], sourceGroup.focusTargets)
    panelButtons: sourceGroup.panelButtons
    inlinePanel: playbackSheet

    StyledText {
        anchors.left: parent.left
        anchors.right: sourceGroup.left
        anchors.rightMargin: Theme.spacingM
        y: (sourceGroup.height - height) / 2
        text: root.presentation?.identity ?? ""
        color: Theme.onSurfaceVariant
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
    }

    MaterialSourceGroup {
        id: sourceGroup
        anchors.right: parent.right
        player: root.player
        presentation: root.presentation
    }

    Item {
        id: hero
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: sourceGroup.bottom
        anchors.topMargin: Theme.spacingL
        anchors.bottom: transport.top
        anchors.bottomMargin: Theme.spacingL
        opacity: playbackSheet.controlsOpacity
        visible: opacity > 0 || !playbackSheet.opened
        enabled: !playbackSheet.opened
        transform: Translate {
            x: playbackSheet.controlsShift
        }

        // Lyrics take the art's column rather than the card, so the title and seekbar stay put.
        MediaArtView {
            id: art

            readonly property real columnWidth: Math.max(0, parent.width / 2 - Theme.spacingL)

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.player.lyricsOpen ? columnWidth : Math.max(0, Math.min(parent.height, columnWidth))
            height: root.player.lyricsOpen ? parent.height : width
            player: root.player
        }

        // Beside the lyrics the title block holds the column's middle rather than the gap above the
        // seekbar. Positioned by one binding either way: an anchor would write y and leave it stale.
        Column {
            anchors.left: parent.left
            anchors.right: art.left
            anchors.rightMargin: Theme.spacingL
            y: Math.round(root.player.lyricsOpen ? (seekBlock.y - height) / 2 : seekBlock.y - Theme.spacingM - height)
            spacing: Theme.spacingXS

            StyledText {
                width: parent.width
                text: root.title
                fontToken: root.titleFontToken
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeXXLarge
                elide: Text.ElideRight
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
            }

            StyledText {
                width: parent.width
                text: root.artist
                color: Theme.onSurfaceVariant
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.album
                color: Theme.onSurfaceVariant
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }

        Item {
            id: seekBlock
            anchors.left: parent.left
            anchors.right: art.left
            anchors.rightMargin: Theme.spacingL
            anchors.bottom: parent.bottom
            height: Math.max(DashMetrics.mediaSeekbarHeight, timeReadout.implicitHeight)
            visible: root.hasSeekbar

            MediaSeekbar {
                id: seekbar
                anchors.left: parent.left
                anchors.right: timeReadout.left
                anchors.rightMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                player: root.player
            }

            NumericText {
                id: timeReadout

                readonly property string durationText: (root.presentation?.length ?? 0) > 0 ? Format.formatDuration(root.presentation.length) : "--:--"

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Format.formatDuration(Math.max(0, Math.min(root.activePlayer?.position ?? 0, root.player.stableLength || Infinity))) + " / " + durationText
                reserveText: durationText + " / " + durationText
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
            }
        }
    }

    MaterialTransport {
        id: transport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        player: root.player
    }

    // Takes the hero's place, so opening it never moves the source row or the transport.
    MediaPlaybackSheet {
        id: playbackSheet
        anchors.fill: hero
        player: root.player
        returnFocusItem: root.buttonForPanel(shownPanel)
    }
}
