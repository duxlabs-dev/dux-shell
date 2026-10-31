pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import "../../../Common/Format.js" as Format
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

MediaChromeBase {
    id: root

    readonly property real contentWidth: Math.max(0, width - (padding + Theme.layerOutlineWidth) * 2)
    readonly property bool compact: width < Theme.smallBreakpoint
    // Whole pixels throughout: the lyrics draw through a layer, and a layer placed between pixels
    // resamples every glyph.
    readonly property real artColumnWidth: compact ? contentWidth : Math.round((contentWidth - Theme.spacingXL) * DashMetrics.mediaArtColumnRatio)
    readonly property real deckWidth: compact ? contentWidth : contentWidth - artColumnWidth - Theme.spacingXL
    readonly property real artworkSize: Math.round(Math.min(artColumnWidth, artSize))
    readonly property bool lyricsShown: root.player.lyricsOpen && root.player.live
    // The transport takes what the artwork leaves over, so both columns end up about as tall.
    readonly property real deckFixedHeight: sourceRow.height + titleBlock.height + seekBlock.height + optionGroup.height + Theme.spacingXL * 2 + Theme.spacingL * 2
    readonly property real transportSize: Math.round(Math.max(Theme.buttonHeightM, Math.min(DashMetrics.mediaTransportMaxHeight, artworkSize - deckFixedHeight)))
    readonly property real stageWidth: lyricsShown && !compact ? artColumnWidth : artworkSize
    readonly property real stageHeight: lyricsShown && !compact ? Math.max(artworkSize, deck.height) : artworkSize
    readonly property real columnHeight: compact ? stageHeight + Theme.spacingXL + deck.height : Math.max(stageHeight, deck.height)

    surfaceColor: Theme.foregroundColor(Theme.hostSurface)
    baseHeight: Math.max(DashMetrics.tabMinHeight, padding * 2 + columnHeight)
    focusTargets: [playerButton].concat(seekbar.canSeek && root.hasSeekbar ? [seekbar] : [], transport.focusTargets, optionGroup.segments)
    panelButtons: [playerButton, volumeButton, outputButton]
    inlinePanel: playbackSheet

    MediaArtView {
        id: stage

        x: {
            const start = root.compact || !I18n.isRtl ? 0 : parent.width - root.artColumnWidth;
            return Math.round(start + (root.artColumnWidth - width) / 2);
        }
        y: root.compact ? 0 : Math.round((parent.height - height) / 2)
        width: root.stageWidth
        height: root.stageHeight
        player: root.player
        holdArt: TrackArtService.loading && TrackArtService.resolvedArtUrl === ""
    }

    Item {
        id: deck

        x: root.compact || I18n.isRtl ? 0 : parent.width - width
        y: root.compact ? stage.height + Theme.spacingXL : Math.round((parent.height - height) / 2)
        width: root.deckWidth
        height: controls.height

        Column {
            id: controls

            width: parent.width
            spacing: Theme.spacingXL
            opacity: playbackSheet.controlsOpacity
            visible: opacity > 0 || !playbackSheet.opened
            enabled: !playbackSheet.opened
            transform: Translate {
                x: playbackSheet.controlsShift
            }

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

                        readonly property string panelId: "players"

                        focusRingColor: MediaAccentService.focusRing
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

            Column {
                id: titleBlock

                width: parent.width
                spacing: Theme.spacingXS

                // Measured from the token, not from titleText's font, which takes its size from here.
                StyledTextMetrics {
                    id: fullSizeTitle
                    text: root.title
                    fontToken: root.titleFontToken
                    font.weight: Font.Normal
                    font.variableAxes: titleText.expressiveFont ? DashMetrics.mediaTitleFontAxes : ({})
                    font.pixelSize: Theme.fontSizeDisplay
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
                    color: MediaAccentService.readableHighlight
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
                    frameDriven: true
                }

                ScrollingText {
                    width: parent.width
                    text: [root.artist, root.album].filter(Boolean).join(" · ") || " "
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeMedium
                    horizontalAlignment: Text.AlignHCenter
                    active: root.scrolling
                    loop: true
                    fadeEdges: true
                    pxPerMs: DashMetrics.mediaTextScrollSpeed / 1000
                    frameDriven: true
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

                        MediaTimeLabel {
                            id: elapsed
                            anchors.left: parent.left
                            text: Format.formatDuration(seekbar.value * (root.presentation?.length ?? 0))
                            reserveText: duration.text
                        }

                        MediaTimeLabel {
                            id: duration
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignRight
                            text: Format.formatDuration(root.presentation?.length ?? 0)
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

                Row {
                    id: optionGroup

                    readonly property var segments: [lyricsButton, shuffleButton, repeatButton, volumeButton, outputButton]
                    readonly property var shownSegments: segments.filter(segment => segment.visible)
                    readonly property real segmentWidth: Theme.buttonHeightM
                    readonly property real outerRadius: Theme.fullRadius(Theme.buttonHeightS, Theme.buttonHeightS)
                    readonly property real innerRadius: Math.min(Theme.innerRadius("s"), outerRadius)
                    readonly property real pressedInnerRadius: Math.min(Theme.innerRadius("xs"), outerRadius)

                    function joinRadius(segment) {
                        if (!Theme.shapeMorph)
                            return innerRadius;
                        if (segment.pressed)
                            return pressedInnerRadius;
                        return segment.checked ? outerRadius : innerRadius;
                    }

                    function leadingRadius(segment) {
                        return segment === shownSegments[0] ? outerRadius : joinRadius(segment);
                    }

                    function trailingRadius(segment) {
                        return segment === shownSegments[shownSegments.length - 1] ? outerRadius : joinRadius(segment);
                    }

                    anchors.horizontalCenter: parent.horizontalCenter
                    height: Theme.buttonHeightS
                    spacing: Theme.groupedListGap
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true

                    Keys.onPressed: event => event.accepted = FocusNavigation.handleHorizontalKey(event, segments, false)

                    OptionButton {
                        id: lyricsButton

                        visible: root.player.lyricsEnabled
                        enabled: !!root.presentation
                        iconName: "lyrics"
                        checkable: true
                        checked: root.player.lyricsOpen
                        tooltipText: I18n.tr("Lyrics", "Media player lyrics button")
                        onClicked: root.player.toggleLyrics(lyricsButton)
                    }

                    MediaTransportButton {
                        id: shuffleButton
                        player: root.player
                        mediaAction: "shuffle"
                        width: optionGroup.segmentWidth
                        variant: "tonal"
                        iconFilled: checked
                        containerColor: checked ? MediaAccentService.accent : MediaAccentService.accentContainer
                        contentColor: checked ? MediaAccentService.onAccent : MediaAccentService.onAccentContainer

                        MediaSegmentShape {
                            group: optionGroup
                        }
                    }

                    MediaTransportButton {
                        id: repeatButton
                        player: root.player
                        mediaAction: "repeat"
                        width: optionGroup.segmentWidth
                        variant: "tonal"
                        iconFilled: checked
                        containerColor: checked ? MediaAccentService.accent : MediaAccentService.accentContainer
                        contentColor: checked ? MediaAccentService.onAccent : MediaAccentService.onAccentContainer

                        MediaSegmentShape {
                            group: optionGroup
                        }
                    }

                    OptionButton {
                        id: volumeButton

                        readonly property string panelId: "volume"
                        readonly property bool muted: root.player.usePlayerVolume ? root.player.currentVolume === 0 : AudioService.sinkSilent
                        readonly property real volumeRatio: root.player.maxVolumePercent > 0 ? root.player.currentVolume * 100 / root.player.maxVolumePercent : 0

                        enabled: root.player.volumeAvailable
                        iconName: root.player.getVolumeIcon()
                        iconSize: Theme.iconSizeSmall
                        tooltipText: (root.player.usePlayerVolume ? I18n.tr("Media volume") : I18n.tr("Volume")) + ": " + Math.round(root.player.currentVolume * 100) + "%"
                        onClicked: root.player.togglePanel(panelId, volumeButton)

                        DRingGauge {
                            anchors.centerIn: parent
                            width: parent.height - Theme.spacingXS * 2
                            height: width
                            value: !root.player.volumeAvailable || volumeButton.muted ? 0 : volumeButton.volumeRatio
                            startAngle: 135
                            spanAngle: 270
                            strokeWidth: Theme.outlineWidthFocused + Theme.dividerWidth
                            trackGap: Theme.spacingXXS
                            ringColor: MediaAccentService.accent
                            trackColor: MediaAccentService.accentTrack
                            animated: root.player.live
                        }

                        MediaVolumeWheel {
                            player: root.player
                            button: volumeButton
                        }
                    }

                    OptionButton {
                        id: outputButton

                        readonly property string panelId: "devices"

                        iconName: AudioService.sinkIcon(AudioService.sink)
                        tooltipText: I18n.tr("Devices", "Media player output device picker") + ": " + AudioService.displayName(AudioService.sink)
                        onClicked: root.player.togglePanel(panelId, outputButton)
                    }
                }
            }
        }

        // Takes the controls' place, so opening it never moves the deck or the artwork.
        MediaPlaybackSheet {
            id: playbackSheet
            anchors.fill: parent
            player: root.player
            returnFocusItem: root.buttonForPanel(shownPanel)
        }
    }

    component OptionButton: DIconButton {
        width: optionGroup.segmentWidth
        height: optionGroup.height
        focusRingColor: MediaAccentService.focusRing
        variant: "tonal"
        iconFilled: checked
        containerColor: checked ? MediaAccentService.accent : MediaAccentService.accentContainer
        contentColor: checked ? MediaAccentService.onAccent : MediaAccentService.onAccentContainer

        MediaSegmentShape {
            group: optionGroup
        }
    }
}
