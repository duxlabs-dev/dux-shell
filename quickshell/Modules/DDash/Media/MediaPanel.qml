pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

DBottomSheet {
    id: root

    required property var player
    property string displayedPanel: ""
    readonly property string requestedPanel: player.panel
    readonly property var sinks: root.active ? AudioService.getAvailableSinks() : []
    readonly property var players: root.active ? root.player.selectablePlayers() : []

    // The playback panel is a popup of its own, see MediaPlaybackPopup.
    readonly property bool sheetPanel: ["volume", "devices", "players"].includes(requestedPanel)

    opened: root.player.live && sheetPanel
    initialFocusItem: panelLoader.item?.focusTarget ?? null
    maximumWidth: DashMetrics.optionSheetWidth
    title: {
        switch (displayedPanel) {
        case "volume":
            return root.player.usePlayerVolume ? I18n.tr("Media volume") : I18n.tr("Volume");
        case "devices":
            return I18n.tr("Play on", "Audio output selection sheet title");
        case "players":
            return I18n.tr("Players", "Media player selection");
        }
        return "";
    }
    onRequestedPanelChanged: {
        if (sheetPanel)
            displayedPanel = requestedPanel;
    }
    onDismissRequested: root.player.panel = ""

    Keys.onPressed: event => {
        if (displayedPanel !== "volume" || !root.player.volumeAvailable) {
            event.accepted = handleKeyEvent(event);
            return;
        }
        switch (event.key) {
        case Qt.Key_K:
            root.player.adjustVolume(AudioService.wheelVolumeStep);
            break;
        case Qt.Key_J:
            root.player.adjustVolume(-AudioService.wheelVolumeStep);
            break;
        case Qt.Key_M:
            root.player.toggleMute();
            break;
        default:
            event.accepted = handleKeyEvent(event);
            return;
        }
        event.accepted = true;
    }

    Loader {
        id: panelLoader
        width: parent.width
        active: root.active
        sourceComponent: {
            switch (root.displayedPanel) {
            case "volume":
                return volumePanel;
            case "devices":
                return devicesPanel;
            case "players":
                return playersPanel;
            }
            return null;
        }
    }

    Component {
        id: volumePanel

        Column {
            readonly property Item focusTarget: volumeSlider
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
                onVolumeChangedByUser: volume => root.player.setVolume(volume)
                onMuteRequested: root.player.toggleMute()
            }
        }
    }

    Component {
        id: devicesPanel

        Column {
            spacing: Theme.spacingM

            Repeater {
                model: root.sinks

                MediaDeviceRow {
                    required property var modelData

                    width: parent.width
                    node: modelData
                    selected: modelData === AudioService.sink
                    subtitle: root.player.outputStatus(modelData)
                    onActivated: AudioService.setSink(modelData)
                }
            }

            StyledText {
                width: parent.width
                visible: root.sinks.length === 0
                text: I18n.tr("No output devices found")
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    Component {
        id: playersPanel

        Column {
            spacing: Theme.spacingS

            Repeater {
                model: root.players

                MediaPanelRow {
                    required property var modelData

                    width: parent.width
                    accent: root.player.accent
                    iconName: "music_note"
                    title: modelData?.identity ?? ""
                    subtitle: [modelData?.trackTitle, modelData?.trackArtist].filter(Boolean).join(" · ")
                    selected: modelData === root.player.activePlayer
                    onActivated: {
                        MprisController.setActivePlayer(modelData);
                        root.player.panel = "";
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: root.players.length === 0
                text: I18n.tr("No Active Players")
                color: Theme.onSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }
}
