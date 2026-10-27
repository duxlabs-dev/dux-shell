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

        MediaArtView {
            id: art
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(parent.height, parent.width / 2 - Theme.spacingL))
            height: width
            player: root.player
            showLyrics: false
            visible: !root.player.lyricsOpen
        }

        Column {
            visible: !root.player.lyricsOpen
            anchors.left: parent.left
            anchors.right: art.left
            anchors.rightMargin: Theme.spacingL
            anchors.bottom: seekBlock.top
            anchors.bottomMargin: Theme.spacingM
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
            anchors.right: root.player.lyricsOpen ? parent.right : art.left
            anchors.rightMargin: root.player.lyricsOpen ? 0 : Theme.spacingL
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

                width: Math.ceil(reservedWidth)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Format.formatDuration(Math.max(0, Math.min(root.activePlayer?.position ?? 0, root.player.stableLength || Infinity))) + " / " + durationText
                reserveText: (durationText + " / " + durationText).replace(/\d/g, "8")
                isMonospace: false
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
            }
        }

        Loader {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: seekBlock.visible ? seekBlock.top : parent.bottom
            anchors.bottomMargin: seekBlock.visible ? Theme.spacingM : 0
            active: root.player.lyricsOpen && root.player.live
            onLoaded: item.forceActiveFocus(Qt.PopupFocusReason)
            sourceComponent: LyricsOverlay {
                player: root.player
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
}
