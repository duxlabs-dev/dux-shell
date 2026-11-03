pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../Common/BlurStrength.js" as BlurStrength

Singleton {
    id: root
    readonly property var log: Log.scoped("BlurService")

    property bool compositorSupported: false
    property bool _probed: false
    property bool probed: false
    readonly property bool available: compositorSupported
    readonly property bool blurRequested: SettingsData.blurEnabled ?? false
    onBlurRequestedChanged: {
        if (blurRequested)
            probe();
    }
    readonly property bool enabled: available && (SettingsData.blurEnabled ?? false)
    readonly property int defaultStrength: BlurStrength.defaultReach(CompositorService.configKey)
    readonly property int strength: SettingsData.blurStrength || defaultStrength

    // These settings predate non-blurred surface borders, so keep their keys for compatibility.
    readonly property color borderColor: {
        if (!(SettingsData.blurBorderEnabled ?? false))
            return "transparent";
        const opacity = SettingsData.blurBorderOpacity ?? 0.35;
        switch (SettingsData.blurBorderColor ?? "outline") {
        case "primary":
            return Theme.withAlpha(Theme.primary, opacity);
        case "secondary":
            return Theme.withAlpha(Theme.secondary, opacity);
        case "surfaceText":
            return Theme.withAlpha(Theme.surfaceText, opacity);
        case "custom":
            return Theme.withAlpha(Qt.color(SettingsData.blurBorderCustomColor ?? "#ffffff"), opacity);
        default:
            return Theme.withAlpha(Theme.outline, opacity);
        }
    }
    readonly property int borderWidth: (SettingsData.blurBorderEnabled ?? false) ? 1 : 0

    function hoverColor(baseColor, hoverAlpha) {
        if (!enabled)
            return baseColor;
        return Theme.withAlpha(baseColor, hoverAlpha ?? 0.15);
    }

    Binding {
        target: Theme
        property: "blurLayersActive"
        value: root.enabled
    }

    Process {
        id: blurProbe
        running: false
        command: ["dms", "blur", "check"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.compositorSupported = text.trim() === "supported";
                root.probed = true;
                if (root.compositorSupported)
                    log.info("Compositor supports ext-background-effect-v1");
                else
                    log.info("Compositor does not support ext-background-effect-v1");
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                log.warn("blur probe failed with code:", exitCode);
        }
    }

    Component.onCompleted: {
        if (blurRequested)
            probe();
    }

    function probe() {
        if (_probed)
            return;
        _probed = true;
        blurProbe.running = true;
    }
}
