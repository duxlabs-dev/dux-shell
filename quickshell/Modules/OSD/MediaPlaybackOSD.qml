import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import Quickshell.Services.Mpris
import Quickshell.Widgets

DOSD {
    id: root

    osdKind: "mediaPlayback"

    readonly property bool useVertical: isVerticalLayout
    readonly property bool playing: player?.isPlaying ?? false
    readonly property var player: MprisController.activePlayer

    osdWidth: useVertical ? Theme.osdHeight : Math.min(Theme.osdMediaWidth, screenWidth - Theme.spacingM * 2)
    osdHeight: Theme.osdHeight
    surfaceColor: useVertical ? MediaAccentService.accent : Theme.hostSurface
    surfaceRadius: useVertical ? (contentLoader.item?.surfaceRadius ?? Theme.cornerRadiusM) : Theme.fullRadius(alignedWidth, alignedHeight)
    autoHideInterval: 3000
    enableMouseInteraction: true

    property string _displayIcon: "music_note"

    function updatePlaybackIcon() {
        if (!player) {
            _displayIcon = "music_note";
            iconDebounce.stop();
            return false;
        }
        let icon = "music_note";
        switch (player.playbackState) {
        case MprisPlaybackState.Playing:
            icon = "pause";
            break;
        case MprisPlaybackState.Paused:
        case MprisPlaybackState.Stopped:
            icon = "play_arrow";
            break;
        }
        if (icon === _displayIcon) {
            iconDebounce.stop();
            return false;
        }
        iconDebounce.pendingIcon = icon;
        iconDebounce.restart();
        return true;
    }

    function togglePlaying() {
        if (player?.canTogglePlaying) {
            player.togglePlaying();
        }
    }

    property bool _pendingShow: false
    property string _displayTitle: ""
    property string _displayArtist: ""
    property string _displayAlbum: ""

    function _showPending() {
        _pendingShow = false;
        pendingShowFallback.stop();
        show();
    }

    function _evaluateShow() {
        // art url can land in a later metadata update than the title
        if (TrackArtService.getArtworkUrl(player) === "") {
            _pendingShow = true;
            pendingShowFallback.interval = 600;
            pendingShowFallback.restart();
            return;
        }
        if (TrackArtService.artReadyFor(player) && artPreloader.status === Image.Ready) {
            _showPending();
            return;
        }
        _pendingShow = true;
        pendingShowFallback.interval = 1500;
        pendingShowFallback.restart();
    }

    Timer {
        id: iconDebounce
        interval: 150
        property string pendingIcon: "music_note"
        onTriggered: root._displayIcon = pendingIcon
    }

    Timer {
        id: pendingShowFallback
        interval: 1500
        onTriggered: {
            if (!root._pendingShow)
                return;
            root._pendingShow = false;
            root.show();
        }
    }

    Image {
        id: artPreloader
        source: SettingsData.osdMediaPlaybackEnabled ? TrackArtService.resolvedArtUrl : ""
        visible: false
        asynchronous: true
        cache: true

        onStatusChanged: {
            if (!root._pendingShow || TrackArtService.loading || !TrackArtService.artReadyFor(root.player))
                return;
            switch (status) {
            case Image.Ready:
            case Image.Error:
                root._showPending();
                break;
            }
        }
    }

    onPlayerChanged: {
        if (!player) {
            _pendingShow = false;
            pendingShowFallback.stop();
            hide();
        }
    }

    readonly property bool trackArtLoading: TrackArtService.loading

    onTrackArtLoadingChanged: {
        if (!_pendingShow)
            return;
        if (trackArtLoading) {
            pendingShowFallback.interval = 1500;
            pendingShowFallback.restart();
            return;
        }
        if (!TrackArtService.resolvedArtUrl) {
            _showPending();
            return;
        }
        if (TrackArtService.artReadyFor(player) && artPreloader.status === Image.Ready)
            _showPending();
    }

    Connections {
        target: player
        enabled: SettingsData.osdMediaPlaybackEnabled

        function handleUpdate() {
            if (!root.player?.trackTitle)
                return;
            if (!SettingsData.osdMediaPlaybackEnabled)
                return;
            if (MprisController.isFirefoxYoutubeHoverPreview(player))
                return;

            const metaPlayer = MprisController.bestMetadataPlayer(player);
            const newTitle = MprisController.displayTrackTitle(metaPlayer);
            const newArtist = metaPlayer.trackArtist || "";
            const newAlbum = metaPlayer.trackAlbum || "";
            const trackChanged = newTitle !== root._displayTitle || newArtist !== root._displayArtist || newAlbum !== root._displayAlbum;

            root._displayTitle = newTitle;
            root._displayArtist = newArtist;
            root._displayAlbum = newAlbum;

            const iconChanged = root.updatePlaybackIcon();

            // live streams re-emit metadata as mpris:length grows - ignore churn
            if (!trackChanged && !iconChanged)
                return;

            // vertical layout has no art background
            if (root.useVertical) {
                root.show();
                return;
            }
            if (trackChanged) {
                root._evaluateShow();
                return;
            }
            if (!root._pendingShow)
                root.show();
        }

        function onTrackArtUrlChanged() {
            handleUpdate();
        }
        function onMetadataChanged() {
            handleUpdate();
        }
        function onIsPlayingChanged() {
            handleUpdate();
        }
        function onTrackChanged() {
            if (!useVertical)
                handleUpdate();
        }
    }

    content: Loader {
        readonly property real surfaceRadius: item?.radius ?? Theme.cornerRadiusM
        anchors.fill: parent
        sourceComponent: useVertical ? verticalContent : horizontalContent
    }

    Component {
        id: horizontalContent

        Item {
            property int gap: Theme.spacingS

            anchors.centerIn: parent
            width: parent.width - Theme.spacingS * 2
            height: Theme.buttonHeightS

            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }

            Item {
                id: bgContainer
                anchors.fill: parent
                visible: TrackArtService.resolvedArtUrl !== ""

                Image {
                    id: bgImage
                    anchors.centerIn: parent
                    width: Math.max(parent.width, parent.height)
                    height: width
                    source: TrackArtService.resolvedArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    retainWhileLoading: true
                    cache: true
                    visible: false
                }

                ClippingRectangle {
                    anchors.fill: parent
                    radius: Theme.fullRadius(width, height)
                    color: "transparent"
                    opacity: 0.7

                    MultiEffect {
                        anchors.centerIn: parent
                        width: bgImage.width
                        height: bgImage.height
                        source: bgImage
                        blurEnabled: true
                        blurMax: 64
                        blur: 0.3
                        saturation: -0.2
                        brightness: -0.25
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.fullRadius(width, height)
                    color: Theme.hostSurface
                    opacity: 0.3
                }
            }

            Row {
                id: transportControls

                x: parent.gap
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                DActionButton {
                    buttonSize: Theme.buttonHeightXS
                    anchors.verticalCenter: parent.verticalCenter
                    objectName: "previousTrack"
                    iconName: "skip_previous"
                    iconSize: Theme.iconSizeSmall
                    iconColor: Theme.onSurface
                    Accessible.name: I18n.tr("Previous")
                    enabled: root.player?.canGoPrevious ?? false
                    onClicked: {
                        MprisController.previousOrRewind();
                        root.resetHideTimer();
                    }
                }

                DIconButton {
                    width: Theme.buttonHeightS
                    buttonSize: Theme.buttonHeightS
                    variant: "filled"
                    round: false
                    checkable: true
                    checked: root.playing
                    iconFilled: false
                    iconName: root._displayIcon
                    containerColor: MediaAccentService.accentContainer
                    contentColor: MediaAccentService.onAccentContainer
                    enabled: root.player?.canTogglePlaying ?? false
                    Accessible.name: root.playing ? I18n.tr("Pause") : I18n.tr("Play")
                    onClicked: {
                        root.togglePlaying();
                        root.resetHideTimer();
                    }
                }

                DActionButton {
                    buttonSize: Theme.buttonHeightXS
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "skip_next"
                    iconSize: Theme.iconSizeSmall
                    iconColor: Theme.onSurface
                    Accessible.name: I18n.tr("Next")
                    enabled: root.player?.canGoNext ?? false
                    onClicked: {
                        MprisController.next();
                        root.resetHideTimer();
                    }
                }
            }

            Column {
                x: parent.gap * 2 + transportControls.width
                width: parent.width - transportControls.width - parent.gap * 3
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                StyledText {
                    id: topText
                    width: parent.width
                    text: player ? (root._displayTitle || I18n.tr("Unknown Title")) : ""
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                StyledText {
                    id: bottomText
                    width: parent.width
                    text: player ? ((root._displayArtist || I18n.tr("Unknown Artist")) + (root._displayAlbum ? ` • ${root._displayAlbum}` : "")) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeight
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    Component {
        id: verticalContent

        DIconButton {
            anchors.fill: parent
            size: "m"
            round: false
            checkable: true
            checked: root.playing
            iconFilled: false
            backgroundColor: "transparent"
            iconColor: MediaAccentService.onAccent
            iconName: root._displayIcon
            enabled: root.player?.canTogglePlaying ?? false
            Accessible.name: root.playing ? I18n.tr("Pause") : I18n.tr("Play")
            onClicked: {
                root.togglePlaying();
                root.resetHideTimer();
            }
        }
    }
}
