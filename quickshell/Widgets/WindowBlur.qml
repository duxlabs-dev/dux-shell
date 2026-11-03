import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Item {
    id: root

    visible: false

    required property var targetWindow
    property bool blurEnabled: true
    property color surfaceColor: "transparent"
    property real blurX: 0
    property real blurY: 0
    property real blurWidth: 0
    property real blurHeight: 0
    property real blurRadius: 0
    property real blurBottomRadius: blurRadius
    property bool clipEnabled: false
    property real clipX: blurX
    property real clipY: blurY
    property real clipWidth: blurWidth
    property real clipHeight: blurHeight

    readonly property bool _active: blurEnabled && surfaceColor.a < 1 && BlurService.enabled && !!targetWindow

    Region {
        id: blurRegion
        x: root.blurX
        y: root.blurY
        width: root.blurWidth
        height: root.blurHeight
        radius: root.blurRadius

        Region {
            readonly property bool needed: root.blurBottomRadius < root.blurRadius
            x: root.blurX
            y: root.blurY + root.blurRadius
            width: needed ? root.blurWidth : 0
            height: needed ? Math.max(0, root.blurHeight - root.blurRadius) : 0
            radius: root.blurBottomRadius
        }

        Region {
            intersection: Intersection.Intersect
            x: root.clipEnabled ? root.clipX : root.blurX
            y: root.clipEnabled ? root.clipY : root.blurY
            width: root.clipEnabled ? root.clipWidth : root.blurWidth
            height: root.clipEnabled ? root.clipHeight : root.blurHeight
        }

        // Hyprland blurs the whole surface when the region lies entirely outside it
        Region {
            intersection: Intersection.Intersect
            width: root.targetWindow?.width ?? 0
            height: root.targetWindow?.height ?? 0
        }
    }

    function _apply() {
        if (!targetWindow)
            return;
        targetWindow.BackgroundEffect.blurRegion = _active ? blurRegion : null;
    }

    function _clear() {
        if (targetWindow)
            targetWindow.BackgroundEffect.blurRegion = null;
    }

    // Re-publish blur region after wl_surface remaps (e.g. screen change).
    function kick() {
        if (!targetWindow)
            return;
        targetWindow.BackgroundEffect.blurRegion = null;
        targetWindow.BackgroundEffect.blurRegion = _active ? blurRegion : null;
    }

    // Republish after geometry settles, plus one trailing pass.
    onBlurXChanged: settleKickAction.restart()
    onBlurYChanged: settleKickAction.restart()
    onBlurWidthChanged: settleKickAction.restart()
    onBlurHeightChanged: settleKickAction.restart()
    onBlurRadiusChanged: settleKickAction.restart()
    onBlurBottomRadiusChanged: settleKickAction.restart()
    onClipEnabledChanged: settleKickAction.restart()
    onClipXChanged: settleKickAction.restart()
    onClipYChanged: settleKickAction.restart()
    onClipWidthChanged: settleKickAction.restart()
    onClipHeightChanged: settleKickAction.restart()

    function _runSettleKick() {
        if (!_active || !targetWindow?.visible)
            return;
        kick();
        settleRepeatTimer.restart();
    }

    DeferredAction {
        id: settleKickAction
        interval: 16
        onTriggered: root._runSettleKick()
    }

    Timer {
        id: settleRepeatTimer
        interval: 96
        repeat: false
        onTriggered: {
            if (!root._active || !root.targetWindow?.visible)
                return;
            root.kick();
        }
    }

    function _scheduleLifecycleKick() {
        lifecycleKickAction.restart();
    }

    function _runLifecycleKick() {
        if (!targetWindow)
            return;
        if (targetWindow.visible)
            kick();
        else
            _apply();
    }

    on_ActiveChanged: {
        if (_active)
            _scheduleLifecycleKick();
        else
            _clear();
    }
    onTargetWindowChanged: {
        lifecycleKickAction.cancel();
        _apply();
    }

    DeferredAction {
        id: lifecycleKickAction
        onTriggered: root._runLifecycleKick()
    }

    Connections {
        target: root.targetWindow ?? null
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (root.targetWindow && root.targetWindow.visible)
                root._scheduleLifecycleKick();
            else
                root._clear();
        }
        function onWidthChanged() {
            settleKickAction.restart();
        }
        function onHeightChanged() {
            settleKickAction.restart();
        }
        function onResourcesLost() {
            root._clear();
            // Re-arm so blur self-heals since instances are no longer recreated per open
            root._scheduleLifecycleKick();
        }
        function onWindowConnected() {
            root._scheduleLifecycleKick();
        }
    }

    Component.onCompleted: _scheduleLifecycleKick()
    Component.onDestruction: {
        lifecycleKickAction.cancel();
        if (targetWindow && targetWindow.BackgroundEffect)
            targetWindow.BackgroundEffect.blurRegion = null;
    }
}
