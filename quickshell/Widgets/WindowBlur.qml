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

    on_ActiveChanged: _apply()
    onTargetWindowChanged: _apply()

    Component.onCompleted: _apply()
    Component.onDestruction: {
        if (targetWindow && targetWindow.BackgroundEffect)
            targetWindow.BackgroundEffect.blurRegion = null;
    }
}
