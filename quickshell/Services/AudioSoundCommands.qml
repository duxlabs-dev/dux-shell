import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services

Item {
    id: root

    readonly property alias volumeChangeSound: volumeChangePlayer
    readonly property alias powerPlugSound: powerPlugPlayer
    readonly property alias powerUnplugSound: powerUnplugPlayer
    readonly property alias normalNotificationSound: normalNotificationPlayer
    readonly property alias criticalNotificationSound: criticalNotificationPlayer
    readonly property alias loginSound: loginPlayer

    component SoundCommand: Process {
        required property string soundEvent

        function play() {
            if (running)
                return;
            command = ["pw-play", "--volume", AudioService.notificationsVolume.toFixed(3), "-P", `{ node.name = "${AudioService.soundNodeName}" }`, Paths.strip(AudioService.getSoundPath(soundEvent))];
            running = true;
        }
    }

    SoundCommand {
        id: volumeChangePlayer
        soundEvent: "audio-volume-change"
    }

    SoundCommand {
        id: powerPlugPlayer
        soundEvent: "power-plug"
    }

    SoundCommand {
        id: powerUnplugPlayer
        soundEvent: "power-unplug"
    }

    SoundCommand {
        id: normalNotificationPlayer
        soundEvent: "message"
    }

    SoundCommand {
        id: criticalNotificationPlayer
        soundEvent: "message-new-instant"
    }

    SoundCommand {
        id: loginPlayer
        soundEvent: "desktop-login"
    }
}
