import QtQuick
import Quickshell.Wayland
import qs.Common

FadeOverlayWindow {
    WlrLayershell.namespace: "dms:fade-to-lock"
    fadeEnabled: SettingsData.fadeToLockEnabled
    fadeDurationMs: Theme.expressiveDurations.expressiveEffects
    overlayColor: "transparent"
    holdsAfterCompletion: true
}
