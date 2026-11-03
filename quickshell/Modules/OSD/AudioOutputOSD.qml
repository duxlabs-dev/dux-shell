import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

DOSD {
    id: root

    osdKind: "audioOutput"

    property string deviceName: ""
    property string deviceIcon: "speaker"

    osdWidth: Math.min(Math.max(120, Theme.buttonHeightS + textMetrics.width + Theme.spacingS * 4), screenWidth - Theme.spacingM * 2)
    osdHeight: Theme.osdHeight
    autoHideInterval: 2500
    enableMouseInteraction: false

    StyledTextMetrics {
        id: textMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: root.deviceName
    }

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

    content: Item {
        property int gap: Theme.spacingS

        anchors.centerIn: parent
        width: parent.width - Theme.spacingS * 2
        height: Theme.buttonHeightS

        OsdIcon {
            id: iconItem
            width: Theme.buttonHeightS
            height: width
            x: parent.gap
            anchors.verticalCenter: parent.verticalCenter
            iconName: root.deviceIcon
        }

        StyledText {
            id: textItem
            x: parent.gap * 2 + iconItem.width
            width: parent.width - iconItem.width - parent.gap * 3
            anchors.verticalCenter: parent.verticalCenter
            text: root.deviceName
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
        }
    }
}
