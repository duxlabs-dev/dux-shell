import QtQuick
import qs.Common
import qs.Services

LevelOSD {
    id: root

    osdKind: "brightness"

    readonly property var device: BrightnessService.getCurrentDeviceInfo()
    property int displayLevel: BrightnessService.brightnessLevel

    iconName: BrightnessService.brightnessIconName(device, displayLevel)
    insetIconName: BrightnessService.brightnessIconName(device)
    endIconName: {
        switch (device?.class) {
        case "backlight":
        case "ddc":
        case "software":
            return "monitor";
        default:
            return BrightnessService.brightnessIconName(device);
        }
    }
    endIconLabel: I18n.tr("Brightness")
    iconColor: Theme.onPrimary
    value: displayLevel
    minimum: BrightnessService.brightnessMinimum(device)
    maximum: BrightnessService.brightnessMaximum(device)
    unit: BrightnessService.brightnessUnit(device)
    available: BrightnessService.brightnessAvailable

    sheetSource: Qt.resolvedUrl("BrightnessOsdSheet.qml")

    onLevelRequested: level => {
        displayLevel = level;
        BrightnessService.setGroupBrightness(level, BrightnessService.lastIpcTargets(), true);
    }

    Connections {
        target: BrightnessService

        function onBrightnessChanged(showOsd, deviceIds) {
            root.displayLevel = BrightnessService.brightnessLevel;
            if (showOsd && BrightnessService.screenShowsOsd(root.screen, deviceIds))
                root.show();
        }
    }
}
