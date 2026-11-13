import QtQuick
import qs.Common
import qs.Services

LabelOSD {
    id: root

    osdKind: "audioOutput"
    iconName: deviceIcon
    label: deviceName

    property string deviceName: ""
    property string deviceIcon: "speaker"

    Connections {
        target: AudioService

        function onAudioOutputCycled(name, icon) {
            if (!SettingsData.osdAudioOutputEnabled)
                return;
            root.deviceName = name;
            root.deviceIcon = icon;
            root.show();
        }
    }
}
