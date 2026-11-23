import QtQuick
import Quickshell.Wayland
import qs.Common

FadeOverlayWindow {
    WlrLayershell.namespace: "dms:fade-to-lock"
    fadeEnabled: !Theme.reduceMotion
    fadeDurationMs: Theme.expressiveDurations.expressiveEffects
    overlayColor: "transparent"
    holdsAfterCompletion: true
}
