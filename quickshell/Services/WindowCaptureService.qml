pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import "../Common/WindowModel.js" as WindowModel

Singleton {
    id: root

    // Screencopy and ExtToplevelList only exist on dux-qt-base; upstream quickshell captures toplevels on Hyprland alone.
    readonly property bool hasCapabilityProbe: typeof Screencopy !== "undefined"
    readonly property bool capturesToplevels: hasCapabilityProbe ? Screencopy.canCaptureToplevels : CompositorService.isHyprland
    readonly property bool capturesExtToplevels: hasCapabilityProbe && Screencopy.canCaptureExtToplevels
    readonly property bool available: capturesToplevels || capturesExtToplevels

    function captureSource(window) {
        if (!window)
            return null;
        const toplevel = window.sourceToplevel ?? window.wayland ?? window;
        if (capturesToplevels)
            return toplevel;
        if (!capturesExtToplevels)
            return null;
        // niri uses its window id as the ext-foreign-toplevel identifier.
        const identifier = window.niriWindowId !== undefined ? String(window.niriWindowId) : "";
        return WindowModel.extToplevelFor(ExtToplevelList.toplevels.values, ToplevelManager.toplevels.values, toplevel, identifier);
    }
}
