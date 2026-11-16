pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash
import qs.Modules.Settings.Widgets
import "../../../DCommon/Common/FocusNavigation.js" as FocusNavigation

// Qt moves a focused control along the whole window's tab chain before its parents see Tab, so every
// control in here hands Tab to cycleFocus itself.
FocusScope {
    id: root

    required property var player
    property Item returnFocusItem: null
    property string shownPanel: ""
    property bool closedByKey: false

    readonly property var panels: ["players", "devices", "volume", "lyrics"]
    readonly property string requestedPanel: root.player.panel
    readonly property bool opened: root.player.live && panels.includes(requestedPanel)
    readonly property bool shown: opened || progress > 0
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    // Material's shared axis: the controls slide out and fade first, then the sheet slides in from the
    // other side and fades in, so the two never show at once. Closing plays it backwards.
    readonly property real progress: motion.value
    readonly property real slideDistance: DashMetrics.mediaSheetSlideDistance * (I18n.isRtl ? -1 : 1)
    readonly property real controlsOpacity: Math.max(0, 1 - progress / DashMetrics.mediaSheetFadeThreshold)
    readonly property real controlsShift: -slideDistance * progress
    readonly property real pageOpacity: Math.max(0, Math.min(1, (progress - DashMetrics.mediaSheetFadeThreshold) / (1 - DashMetrics.mediaSheetFadeThreshold)))
    readonly property real pageShift: slideDistance * (1 - progress)
    readonly property var spring: Theme.springPreset("default", Theme.expressiveDurations.expressiveDefaultSpatial)
    readonly property var sinks: shown && shownPanel === "devices" ? AudioService.getAvailableSinks() : []
    readonly property var players: shown && shownPanel === "players" ? root.player.selectablePlayers() : []
    readonly property var lyrics: LyricsService.controller
    readonly property bool listsLyrics: opened && shownPanel === "lyrics"
    // The closing spring can pass zero and come back, so the list loads on open only and
    // stays until the sheet is hidden.
    readonly property bool keepsLyrics: shown && shownPanel === "lyrics"
    readonly property var lyricsChoices: keepsLyrics && lyrics.choices?.length > 0 ? [
        {
            "source": ""
        }
    ].concat(lyrics.choices) : []
    readonly property string lyricsChosen: lyricsChoices.some(choice => choice.source === lyrics.chosen) ? lyrics.chosen : ""
    readonly property string emptyText: {
        switch (shownPanel) {
        case "devices":
            return sinks.length === 0 ? I18n.tr("No output devices found") : "";
        case "players":
            return players.length === 0 ? I18n.tr("No Active Players") : "";
        case "lyrics":
            if (!lyrics.choices)
                return I18n.tr("Loading...");
            return lyrics.choices.length === 0 ? I18n.tr("No results") : "";
        }
        return "";
    }
    readonly property var focusTargets: {
        const targets = [backButton];
        if (shownPanel === "volume")
            return targets.concat(volumeSlider);
        const repeater = {
            "devices": deviceRows,
            "lyrics": lyricsRows
        }[shownPanel] ?? playerRows;
        for (let i = 0; i < repeater.count; i++)
            targets.push(...(repeater.itemAt(i)?.focusTargets ?? []));
        return targets;
    }
    readonly property Item focusTarget: focusTargets[0] ?? null
    // The list's edge fade reads this to blend into the sheet instead of a darker ancestor.
    readonly property color surfaceColor: Theme.surfaceContainer

    visible: shown
    enabled: opened
    opacity: pageOpacity
    transform: Translate {
        x: root.pageShift
    }

    onRequestedPanelChanged: {
        if (!panels.includes(requestedPanel))
            return;
        shownPanel = requestedPanel;
        flickable.contentY = 0;
    }

    onListsLyricsChanged: {
        if (listsLyrics)
            lyrics.listChoices();
    }
    onKeepsLyricsChanged: {
        if (!keepsLyrics)
            lyrics.dropChoices();
    }
    Component.onDestruction: lyrics.dropChoices()

    onOpenedChanged: {
        motion.retarget(opened ? 1 : 0);
        if (opened) {
            closedByKey = false;
            root.forceActiveFocus(Qt.OtherFocusReason);
            return;
        }
        if (!FocusNavigation.containsFocus(root))
            return;
        // Only a sheet left by keyboard hands back a focus ring, and the controls it returns to turn
        // usable only once this change has gone through.
        const keyboard = closedByKey || (Window.activeFocusItem?.visualFocus ?? false);
        Qt.callLater(() => {
            if (keyboard)
                FocusNavigation.focusItem(returnFocusItem, false);
            else
                returnFocusItem?.forceActiveFocus(Qt.OtherFocusReason);
        });
    }

    function close() {
        root.player.panel = "";
    }

    function lyricsTitle(choice) {
        switch (choice.source) {
        case "":
            return I18n.tr("Auto");
        case "sidecar":
            return I18n.tr("Local");
        }
        return MediaOptions.lyricsProviderCatalog.find(provider => provider.id === choice.source)?.text ?? choice.attribution?.name ?? choice.source;
    }

    function lyricsPrecision(choice) {
        if (choice.instrumental)
            return I18n.tr("Instrumental", "Track has no lyrics because it is instrumental");
        switch (choice.sync) {
        case "word":
            return I18n.tr("Word synced", "Lyrics are timed per word");
        case "line":
            return I18n.tr("Line synced", "Lyrics are timed per line");
        }
        return I18n.tr("Unsynced", "Lyrics have no timestamps");
    }

    // Why Auto ranks a source below the others.
    function lyricsProblem(choice) {
        switch (choice.problem) {
        case "length":
            return I18n.tr("Different length", "Lyrics were timed for a recording of another length than the playing track");
        case "overrun":
            return I18n.tr("Runs past the end", "Lyrics have lines timed after the playing track ends");
        }
        return "";
    }

    function lyricsSubtitle(choice) {
        if (choice.source !== "")
            return lyricsPrecision(choice);
        if (lyricsChosen !== "")
            return "";
        const shown = (lyrics.choices ?? []).find(listed => listed.source === lyrics.source);
        return shown ? lyricsTitle(shown) + " · " + lyricsPrecision(shown) : lyrics.attributionName;
    }

    function lyricsIcon(choice) {
        switch (choice.source) {
        case "":
            return "auto_awesome";
        case "sidecar":
            return "description";
        }
        return "lyrics";
    }

    function cycleFocus(backwards) {
        if (FocusNavigation.moveFocus(focusTargets, backwards))
            return;
        const targets = focusTargets.filter(item => item?.visible && item.enabled);
        FocusNavigation.focusItem(backwards ? targets[targets.length - 1] : targets[0], backwards);
    }

    Keys.onPressed: event => {
        const volume = shownPanel === "volume" && root.player.volumeAvailable;
        switch (event.key) {
        case Qt.Key_K:
            if (!volume)
                return;
            root.player.adjustVolume(AudioService.wheelVolumeStep);
            break;
        case Qt.Key_J:
            if (!volume)
                return;
            root.player.adjustVolume(-AudioService.wheelVolumeStep);
            break;
        case Qt.Key_M:
            if (!volume)
                return;
            root.player.toggleMute();
            break;
        case Qt.Key_Escape:
            closedByKey = true;
            close();
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            cycleFocus(event.key === Qt.Key_Backtab);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    SpringMotion {
        id: motion
        enabled: !Theme.springMotionDisabled
        reducedMotion: !root.animationsEnabled
        stiffness: root.spring.stiffness
        damping: root.spring.damping
        positionEpsilon: DashMetrics.mediaSheetSettleProgress
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusXL
        color: root.surfaceColor
    }

    Item {
        id: header

        x: Theme.spacingL
        y: Theme.spacingL
        width: parent.width - Theme.spacingL * 2
        height: backButton.height

        DIconButton {
            id: backButton
            focusRingColor: MediaAccentService.focusRing
            width: buttonSize
            variant: "tonal"
            round: false
            iconName: I18n.isRtl ? "arrow_forward" : "arrow_back"
            containerColor: Theme.surfaceContainerHighest
            contentColor: Theme.onSurfaceVariant
            tooltipText: I18n.tr("Back")
            Keys.onTabPressed: root.cycleFocus(false)
            Keys.onBacktabPressed: root.cycleFocus(true)
            onClicked: root.close()
        }

        StyledText {
            anchors.left: backButton.right
            anchors.leftMargin: Theme.spacingM
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
                switch (root.shownPanel) {
                case "devices":
                    return I18n.tr("Play on", "Audio output selection sheet title");
                case "volume":
                    return root.player.usePlayerVolume ? I18n.tr("Media volume") : I18n.tr("Volume");
                case "lyrics":
                    return I18n.tr("Lyrics providers", "Lyrics source priority settings");
                }
                return I18n.tr("Players", "Media player selection");
            }
            color: Theme.onSurface
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            elide: Text.ElideRight
        }
    }

    DFlickable {
        id: flickable

        anchors.fill: parent
        anchors.margins: Theme.spacingL
        anchors.topMargin: header.y + header.height + Theme.spacingM
        contentHeight: content.implicitHeight
        clip: true

        Column {
            id: content

            width: flickable.width

            SettingsGroup {
                width: parent.width
                visible: root.shownPanel === "players" && root.players.length > 0
                slotColor: Theme.surfaceContainerHigh
                customPaddingH: Theme.spacingL
                customPaddingV: Theme.spacingM

                Repeater {
                    id: playerRows

                    model: root.players

                    ListRow {
                        id: playerRow

                        required property var modelData
                        readonly property bool isPinned: !!modelData?.identity && MprisController.pinnedIdentity === modelData.identity

                        iconName: "music_note"
                        title: modelData?.identity ?? ""
                        subtitle: [modelData?.trackTitle, modelData?.trackArtist].filter(Boolean).join(" · ")
                        active: modelData === root.player.activePlayer
                        onClicked: MprisController.setActivePlayer(modelData)
                        Keys.onTabPressed: root.cycleFocus(false)
                        Keys.onBacktabPressed: root.cycleFocus(true)

                        focusTargets: (clickable ? [playerRow] : []).concat(pinButton)

                        DActionButton {
                            id: pinButton

                            iconName: "push_pin"
                            iconFilled: playerRow.isPinned
                            iconColor: playerRow.isPinned ? playerRow.iconColor : playerRow.supportingContentColor
                            focusRingColor: MediaAccentService.focusRing
                            tooltipText: playerRow.isPinned ? I18n.tr("Unpin") : I18n.tr("Pin", "verb, keep an item pinned in place")
                            Accessible.name: tooltipText
                            Keys.onTabPressed: root.cycleFocus(false)
                            Keys.onBacktabPressed: root.cycleFocus(true)
                            onClicked: {
                                if (playerRow.modelData?.identity)
                                    MprisController.setPinned(playerRow.isPinned ? "" : playerRow.modelData.identity);
                            }
                        }
                    }
                }
            }

            SettingsGroup {
                width: parent.width
                visible: root.shownPanel === "devices" && root.sinks.length > 0
                slotColor: Theme.surfaceContainerHigh
                customPaddingH: Theme.spacingL
                customPaddingV: Theme.spacingM

                Repeater {
                    id: deviceRows

                    model: root.sinks

                    ListRow {
                        id: deviceRow

                        required property var modelData

                        iconName: AudioService.sinkIcon(modelData)
                        title: AudioService.displayName(modelData)
                        subtitle: root.player.outputStatus(modelData)
                        active: modelData === AudioService.sink
                        onClicked: AudioService.setSink(modelData)
                        Keys.onTabPressed: root.cycleFocus(false)
                        Keys.onBacktabPressed: root.cycleFocus(true)

                        focusTargets: clickable ? [deviceRow] : volumeLoader.item?.focusTargets ?? []

                        body: Loader {
                            id: volumeLoader
                            width: parent.width
                            active: deviceRow.active && !!deviceRow.modelData?.audio
                            visible: active

                            sourceComponent: MediaSinkVolume {
                                node: deviceRow.modelData
                                hostCyclesFocus: true
                                onCycleFocusRequested: backwards => root.cycleFocus(backwards)
                                label: deviceRow.title
                                contentColor: deviceRow.titleColor
                                rowColor: deviceRow.rowColor
                                insetColor: Theme.surfaceContainerHighest
                            }
                        }
                    }
                }
            }

            SettingsGroup {
                width: parent.width
                visible: root.lyricsChoices.length > 0
                slotColor: Theme.surfaceContainerHigh
                customPaddingH: Theme.spacingL
                customPaddingV: Theme.spacingM

                Repeater {
                    id: lyricsRows

                    model: root.lyricsChoices

                    ListRow {
                        required property var modelData

                        iconName: root.lyricsIcon(modelData)
                        title: root.lyricsTitle(modelData)
                        subtitle: root.lyricsSubtitle(modelData)
                        trailingBadge: root.lyricsProblem(modelData)
                        trailingBadgeColor: active ? supportingContentColor : Theme.warning
                        active: modelData.source === root.lyricsChosen
                        onClicked: root.lyrics.choose(modelData.source)
                        Keys.onTabPressed: root.cycleFocus(false)
                        Keys.onBacktabPressed: root.cycleFocus(true)
                    }
                }
            }

            Column {
                width: parent.width
                visible: root.shownPanel === "volume"
                spacing: Theme.spacingM

                StyledText {
                    width: parent.width
                    text: root.player.usePlayerVolume ? root.player.activePlayer?.identity ?? "" : AudioService.displayName(AudioService.sink)
                    color: Theme.onSurfaceVariant
                    font.pixelSize: Theme.fontSizeMedium
                    elide: Text.ElideRight
                }

                MediaVolumeSlider {
                    id: volumeSlider
                    width: parent.width
                    volume: root.player.currentVolume
                    muted: root.player.usePlayerVolume ? volume === 0 : AudioService.sinkSilent
                    maximumVolume: root.player.maxVolumePercent
                    enabled: root.player.volumeAvailable
                    Keys.onTabPressed: root.cycleFocus(false)
                    Keys.onBacktabPressed: root.cycleFocus(true)
                    onVolumeChangedByUser: volume => root.player.setVolume(volume)
                    onMuteRequested: root.player.toggleMute()
                }
            }

            StyledText {
                width: parent.width
                visible: text !== ""
                text: root.emptyText
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    // The active row has nothing to do on click, so the selected output is reached through its volume controls.
    component ListRow: SettingsRow {
        id: listRow

        property var focusTargets: clickable ? [listRow] : []

        paddingH: Theme.spacingL
        paddingV: Theme.spacingM
        rowColor: Theme.surfaceContainerHigh
        selectedRowColor: MediaAccentService.artAccent ? MediaAccentService.accentContainer : Theme.selectedContainer
        selectedContentColor: MediaAccentService.artAccent ? MediaAccentService.onAccentContainer : Theme.onSelectedContainer
        iconColor: active ? (MediaAccentService.artAccent ? MediaAccentService.onAccentContainer : Theme.accentOnSelectedContainer) : MediaAccentService.accent
        clickable: !active
        Accessible.selected: active
    }
}
