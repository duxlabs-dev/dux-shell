pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Common

Singleton {
    id: root

    readonly property int _effect: (typeof SettingsData === "undefined") ? 0 : SettingsData.motionEffect

    readonly property var _cleanupPaddings: [50, 8, 24, 50]
    readonly property var _effectScaleCollapsed: [0.96, 1.0, 0.88, 0.96]
    readonly property var _effectAnimOffsets: [16, 144, 56, 16]

    function variantExitCleanupPadding() {
        return _cleanupPaddings[_effect] !== undefined ? _cleanupPaddings[_effect] : 50;
    }

    function variantCloseInterval(baseDuration) {
        return Math.max(0, Math.round(baseDuration)) + variantExitCleanupPadding();
    }

    readonly property bool isDirectionalEffect: isConnectedEffect || _effect === SettingsData.AnimationEffect.Directional
    readonly property bool isFluidEffect: _effect === SettingsData.AnimationEffect.Fluid
    readonly property bool isDepthEffect: _effect === SettingsData.AnimationEffect.Depth
    readonly property bool isConnectedEffect: (typeof FrameTransitionState !== "undefined") && FrameTransitionState.effectiveConnectedFrameModeActive

    readonly property real effectScaleCollapsed: _effectScaleCollapsed[_effect] !== undefined ? _effectScaleCollapsed[_effect] : 0.96
    readonly property real effectAnimOffset: _effectAnimOffsets[_effect] !== undefined ? _effectAnimOffsets[_effect] : 16
}
