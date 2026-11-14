import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Item {
    id: root

    visible: false

    required property var targetWindow
    property bool applyToWindow: true
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
    // A second surface beside the body, blurred on its own so the gap between them stays clear.
    property Item sideItem: null
    property real sideRadius: 0
    // Where the side item's ancestors sit: a Region follows only its item's own geometry, so a change here rebuilds it.
    property point sideOrigin: Qt.point(blurX, blurY)

    readonly property bool _active: blurEnabled && surfaceColor.a < 1 && BlurService.enabled && !!targetWindow
    readonly property var effectiveRegion: _active ? blurRegion : null

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

        Region {
            item: root.sideItem
            radius: root.sideRadius
            x: root.sideOrigin.x
            y: root.sideOrigin.y
        }

        // Hyprland blurs the whole surface when the region lies entirely outside it
        Region {
            intersection: Intersection.Intersect
            width: root.targetWindow?.width ?? 0
            height: root.targetWindow?.height ?? 0
        }
    }

    function _apply() {
        if (!applyToWindow || !targetWindow)
            return;
        targetWindow.BackgroundEffect.blurRegion = _active ? blurRegion : null;
    }

    on_ActiveChanged: _apply()
    onTargetWindowChanged: _apply()

    Component.onCompleted: _apply()
    Component.onDestruction: {
        if (applyToWindow && targetWindow && targetWindow.BackgroundEffect)
            targetWindow.BackgroundEffect.blurRegion = null;
    }
}
