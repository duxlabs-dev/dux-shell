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

    readonly property real contentWidth: Math.max(0, width - padding * 2)
    readonly property bool compact: width < Theme.smallBreakpoint
    // Whole pixels throughout: the lyrics draw through a layer, and a layer placed between pixels
    // resamples every glyph.
    readonly property real artColumnWidth: compact ? contentWidth : Math.round((contentWidth - Theme.spacingXL) * DashMetrics.mediaArtColumnRatio)
    readonly property real deckWidth: compact ? contentWidth : contentWidth - artColumnWidth - Theme.spacingXL
    readonly property real artworkSize: Math.round(Math.min(artColumnWidth, artSize))
    readonly property bool lyricsShown: root.player.lyricsOpen && root.player.live
    // The transport takes what the artwork leaves over, so both columns end up about as tall.
    readonly property real deckFixedHeight: sourceRow.height + titleBlock.height + seekBlock.height + optionRow.height + Theme.spacingXL * 2 + Theme.spacingL * 2
    readonly property real transportSize: Math.round(Math.max(Theme.buttonHeightM, Math.min(DashMetrics.mediaTransportMaxHeight, artworkSize - deckFixedHeight)))
    readonly property real stageWidth: lyricsShown && !compact ? artColumnWidth : artworkSize
    readonly property real stageHeight: lyricsShown && !compact ? Math.max(artworkSize, deck.height) : artworkSize
    readonly property real columnHeight: compact ? stageHeight + Theme.spacingXL + deck.height : Math.max(stageHeight, deck.height)

    surfaceColor: Theme.foregroundColor(Theme.hostSurface)
    baseHeight: Math.max(DashMetrics.tabMinHeight, padding * 2 + columnHeight)
    focusTargets: [playerButton].concat(seekbar.canSeek && root.hasSeekbar ? [seekbar] : [], transport.focusTargets, optionRow.focusTargets)
    panelButtons: [playerButton, outputButton]
    inlinePanels: ["players", "devices"]
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
                    font.pixelSize: Theme.fontSizeMedium
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

                        MediaTimeLabel {
                            id: elapsed
                            anchors.left: parent.left
                            text: Format.formatDuration(seekbar.value * (root.presentation?.length ?? 0))
                            reserveText: duration.text.replace(/\d/g, "8")
                        }

                        MediaTimeLabel {
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

                Row {
                    id: optionRow

                    readonly property var focusTargets: [lyricsButton, shuffleButton.button, repeatButton.button, outputButton]

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.groupedListGap
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true

                    Keys.onPressed: event => event.accepted = FocusNavigation.handleHorizontalKey(event, focusTargets, false)

                    GroupButton {
                        id: lyricsButton

                        groupStart: true
                        visible: root.player.lyricsEnabled
                        enabled: !!root.presentation
                        iconName: "lyrics"
                        checkable: true
                        checked: root.player.lyricsOpen
                        tooltipText: I18n.tr("Lyrics", "Media player lyrics button")
                        onClicked: root.player.toggleLyrics(lyricsButton)
                    }

                    ModeButton {
                        id: shuffleButton
                        mediaAction: "shuffle"
                        groupStart: !lyricsButton.visible
                    }

                    ModeButton {
                        id: repeatButton
                        mediaAction: "repeat"
                    }

                    GroupButton {
                        id: outputButton

                        readonly property string panelId: "devices"

                        groupStart: !lyricsButton.visible && !root.presentation
                        groupEnd: true
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

    // A connected group: the outer ends stay round, the inner corners follow radius so its Behavior
    // animates press and toggle. ModeButton repeats this because it needs MediaTransportButton's logic.
    component GroupButton: DIconButton {
        property bool groupStart: false
        property bool groupEnd: false
        readonly property real outerRadius: Theme.fullRadius(width, height)

        widthMode: "wide"
        variant: "tonal"
        iconFilled: checked
        radius: pressed ? Theme.cornerRadiusXS : (checked ? outerRadius : Theme.cornerRadiusS)
        topLeftRadius: groupStart ? outerRadius : radius
        bottomLeftRadius: groupStart ? outerRadius : radius
        topRightRadius: groupEnd ? outerRadius : radius
        bottomRightRadius: groupEnd ? outerRadius : radius
        containerColor: checked ? MediaAccentService.accent : MediaAccentService.accentContainer
        contentColor: checked ? MediaAccentService.onAccent : MediaAccentService.onAccentContainer
    }

    // Shown even when unsupported. A disabled button takes no hover, so a sibling area drives the tooltip.
    component ModeButton: Item {
        id: mode

        property string mediaAction: ""
        property bool groupStart: false
        readonly property alias button: modeButton

        implicitWidth: modeButton.width
        implicitHeight: modeButton.height
        visible: !!root.presentation

        MediaTransportButton {
            id: modeButton

            readonly property real outerRadius: Theme.fullRadius(width, height)

            player: root.player
            mediaAction: mode.mediaAction
            visible: true
            widthMode: "wide"
            variant: "tonal"
            iconFilled: checked
            radius: pressed ? Theme.cornerRadiusXS : (checked ? outerRadius : Theme.cornerRadiusS)
            topLeftRadius: mode.groupStart ? outerRadius : radius
            bottomLeftRadius: mode.groupStart ? outerRadius : radius
            containerColor: checked ? MediaAccentService.accent : MediaAccentService.accentContainer
            contentColor: checked ? MediaAccentService.onAccent : MediaAccentService.onAccentContainer
        }

        MouseArea {
            id: unsupportedHover
            anchors.fill: parent
            // MouseArea.enabled: false is different from Item.enabled: false and still takes mouseevents although not handling them
            // That causes the cursor to not change to pointer over the button when it is enabled.
            visible: !modeButton.enabled
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        DTooltipHost {
            target: modeButton
            hoverArea: unsupportedHover
            text: modeButton.enabled ? "" : I18n.tr("Not supported by this player", "Tooltip on a disabled media shuffle or repeat button")
        }
    }
}
