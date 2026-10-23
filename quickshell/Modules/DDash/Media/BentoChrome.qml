pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import "../../../Common/Format.js" as Format

MediaChromeBase {
    id: root

    readonly property real contentWidth: Math.max(0, width - padding * 2)
    readonly property bool compact: width < Theme.smallBreakpoint
    readonly property real artColumnWidth: compact ? contentWidth : (contentWidth - Theme.spacingXL) * DashMetrics.mediaArtColumnRatio
    readonly property real deckWidth: compact ? contentWidth : contentWidth - artColumnWidth - Theme.spacingXL
    readonly property real artworkSize: Math.round(Math.min(artColumnWidth, artSize))
    readonly property bool lyricsShown: root.player.lyricsOpen && root.player.live
    readonly property bool boxed: root.player.controlsContainer
    readonly property real deckInset: boxed ? Theme.spacingXL : 0
    // The transport takes what the artwork leaves over, so both columns end up about as tall.
    readonly property real deckFixedHeight: sourceRow.height + titleBlock.height + seekBlock.height + actionRow.implicitHeight + deckInset * 2 + Theme.spacingXL * 2 + Theme.spacingL * 2
    readonly property real transportSize: Math.round(Math.max(Theme.buttonHeightM, Math.min(DashMetrics.mediaTransportMaxHeight, artworkSize - deckFixedHeight)))
    readonly property real stageWidth: lyricsShown && !compact ? artColumnWidth : artworkSize
    readonly property real stageHeight: lyricsShown && !compact ? Math.max(artworkSize, deck.height) : artworkSize
    readonly property real columnHeight: compact ? stageHeight + Theme.spacingXL + deck.height : Math.max(stageHeight, deck.height)

    surfaceColor: Theme.foregroundColor(Theme.hostSurface)
    baseHeight: Math.max(DashMetrics.tabMinHeight, padding * 2 + columnHeight)
    focusTargets: [playerButton].concat(seekbar.canSeek && root.hasSeekbar ? [seekbar] : [], transport.focusTargets, actionRow.focusTargets)
    panelButtons: [playerButton].concat(actionRow.panelButtons)
    inlineVolume: true

    MediaArtView {
        id: stage

        x: {
            const start = root.compact || !I18n.isRtl ? 0 : parent.width - root.artColumnWidth;
            return start + (root.artColumnWidth - width) / 2;
        }
        y: root.compact ? 0 : (parent.height - height) / 2
        width: root.stageWidth
        height: root.stageHeight
        player: root.player
        holdArt: TrackArtService.loading && TrackArtService.resolvedArtUrl === ""
    }

    Column {
        id: deck

        x: root.compact || I18n.isRtl ? 0 : parent.width - width
        y: root.compact ? stage.height + Theme.spacingXL : (parent.height - height) / 2
        width: root.deckWidth
        spacing: Theme.spacingXL

        Item {
            id: sourceRow

            width: parent.width
            height: Theme.buttonHeightXS

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingM
                visible: !!root.presentation

                StyledText {
                    id: sourceLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, sourceRow.width / 2)
                    text: I18n.tr("Listening from", "Label before the active media player")
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeMedium
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                DButton {
                    id: playerButton

                    readonly property string panelId: "playback"

                    anchors.verticalCenter: parent.verticalCenter
                    maximumWidth: Math.max(0, sourceRow.width - sourceLabel.width - parent.spacing)
                    buttonHeight: Theme.buttonHeightXS
                    horizontalPadding: Theme.spacingL
                    text: root.presentation?.identity ?? ""
                    backgroundColor: MediaAccentService.accentSecondaryContainer
                    textColor: MediaAccentService.onAccentSecondaryContainer
                    tooltipText: I18n.tr("Players", "Media player selection")
                    Accessible.name: tooltipText + ": " + text
                    onClicked: root.player.togglePanel(panelId, playerButton)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: controls.height + root.deckInset * 2
            radius: Theme.cornerRadiusXL
            color: root.boxed ? Theme.surfaceContainer : "transparent"

            Column {
                id: controls

                x: root.deckInset
                y: root.deckInset
                width: parent.width - root.deckInset * 2
                spacing: Theme.spacingXL

                Column {
                    id: titleBlock

                    width: parent.width
                    spacing: Theme.spacingXS

                    TextMetrics {
                        id: fullSizeTitle
                        text: root.title
                        font: Qt.font({
                            family: titleText.font.family,
                            weight: titleText.font.weight,
                            variableAxes: titleText.font.variableAxes,
                            pixelSize: Theme.fontSizeDisplay
                        })
                    }

                    FontMetrics {
                        id: fullSizeTitleFont
                        font: fullSizeTitle.font
                    }

                    ScrollingText {
                        id: titleText

                        readonly property bool expressiveFont: root.titleFontToken === "ui"
                        readonly property real fittedPixelSize: {
                            if (fullSizeTitle.advanceWidth <= width)
                                return Theme.fontSizeDisplay;
                            return Math.max(Theme.fontSizeXXLarge, Math.floor(Theme.fontSizeDisplay * width / fullSizeTitle.advanceWidth));
                        }

                        width: parent.width
                        height: Math.ceil(fullSizeTitleFont.height)
                        text: root.title
                        fontToken: root.titleFontToken
                        color: MediaAccentService.highlight
                        font.pixelSize: fittedPixelSize
                        // The bundled static weights share the family name and carry no axes, so
                        // the regular weight selects the variable font and wght sets the weight.
                        font.weight: Font.Normal
                        font.variableAxes: expressiveFont ? DashMetrics.mediaTitleFontAxes : ({})
                        horizontalAlignment: Text.AlignHCenter
                        active: root.scrolling
                        loop: true
                        fadeEdges: true
                        pxPerMs: DashMetrics.mediaTextScrollSpeed / 1000
                        stepInterval: DashMetrics.mediaTextScrollStep
                    }

                    ScrollingText {
                        width: parent.width
                        text: [root.artist, root.album].filter(Boolean).join(" · ") || " "
                        color: Theme.onSurfaceVariant
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        active: root.scrolling
                        loop: true
                        fadeEdges: true
                        pxPerMs: DashMetrics.mediaTextScrollSpeed / 1000
                        stepInterval: DashMetrics.mediaTextScrollStep
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingL

                    // Kept for a length-less stream, so the deck does not resize when one comes up.
                    Column {
                        id: seekBlock

                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.seekbarEnabled && !!root.presentation
                        LayoutMirroring.enabled: false
                        LayoutMirroring.childrenInherit: true

                        MediaSeekbar {
                            id: seekbar
                            width: parent.width
                            opacity: root.hasSeekbar ? 1 : 0
                            height: DashMetrics.mediaSeekbarExpressiveHeight
                            player: root.player
                            accentTrackColor: MediaAccentService.accentRail
                            waveLineWidth: DashMetrics.mediaSeekbarExpressiveLineWidth
                            waveAmplitude: DashMetrics.mediaSeekbarExpressiveAmplitude
                            wavelength: DashMetrics.mediaSeekbarExpressiveWavelength
                            showHandle: true
                            handleSize: DashMetrics.mediaSeekbarHandleSize
                            handleDragWidth: DashMetrics.mediaSeekbarHandleDragWidth
                            handleDragHeight: DashMetrics.mediaSeekbarHandleDragHeight
                            handleGap: DashMetrics.mediaSeekbarHandleGap
                        }

                        Item {
                            width: parent.width
                            height: elapsed.implicitHeight
                            opacity: root.hasSeekbar ? 1 : 0

                            TimeLabel {
                                id: elapsed
                                anchors.left: parent.left
                                text: Format.formatDuration(seekbar.value * (root.presentation?.length ?? 0))
                                reserveText: duration.text.replace(/\d/g, "8")
                            }

                            TimeLabel {
                                id: duration
                                anchors.right: parent.right
                                horizontalAlignment: Text.AlignRight
                                text: Format.formatDuration(root.presentation?.length ?? 0)
                                reserveText: text.replace(/\d/g, "8")
                            }
                        }
                    }

                    MediaTransport {
                        id: transport
                        width: parent.width
                        player: root.player
                        presentation: root.presentation
                        buttonSize: root.transportSize
                        visible: hasControls
                    }

                    MediaActionRow {
                        id: actionRow
                        width: parent.width
                        player: root.player
                    }
                }
            }
        }
    }

    component TimeLabel: NumericText {
        width: Math.ceil(reservedWidth)
        isMonospace: false
        color: Theme.onSurfaceVariant
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
    }
}
