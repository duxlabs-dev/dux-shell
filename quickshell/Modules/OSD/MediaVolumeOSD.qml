import QtQuick
import qs.Common
import qs.Services

LevelOSD {
    id: root

    osdKind: "mediaVolume"

    readonly property var player: MprisController.activePlayer
    readonly property bool volumeSupported: player?.volumeSupported ?? false
    readonly property real playerVolume: player?.volume ?? 0
    property bool _suppressNewPlayer: false

    iconName: playerVolume === 0 && player ? "music_off" : "music_note"
    insetIconName: "music_note"
    endIconName: "equalizer"
    iconInteractive: true
    iconLabel: playerVolume === 0 ? I18n.tr("Unmute") : I18n.tr("Mute")
    value: Math.min(100, Math.round(playerVolume * 100))
    available: volumeSupported

    onIconClicked: {
        if (player)
            player.volume = player.volume > 0 ? 0 : 1;
    }
    onLevelRequested: level => player.volume = level / 100

    onPlayerChanged: {
        _suppressNewPlayer = true;
        _suppressTimer.restart();
    }

    Timer {
        id: _suppressTimer
        interval: 2000
        onTriggered: root._suppressNewPlayer = false
    }

    Connections {
        target: root.player

        function onVolumeChanged() {
            if (SettingsData.osdMediaVolumeEnabled && root.volumeSupported && !root._suppressNewPlayer)
                root.show();
        }
    }
}
