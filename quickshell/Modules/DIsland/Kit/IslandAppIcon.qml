pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.Common
import qs.DCommon.Widgets
import "../../../Common/IslandKit.js" as Kit

// Each poke() morphs the shape as DMS's expressive password field does, so a click on a bubble answers in the same voice.
Item {
    id: root

    property string source: ""
    property string iconName: "apps"
    property real size: Theme.avatarSize
    // On a bubble's own shape: no shape of its own, and the icon at the size every bubble's icon has there.
    property bool bare: false
    property real iconSize: Math.round(root.size * root.iconShare)
    // The icon's share of the size: on its shape, or bare on a bubble's.
    readonly property real iconShare: 0.7
    // The logo is decoded at this many times its drawn size, so it stays sharp on a scaled screen.
    readonly property real logoDecodeScale: 2
    readonly property real logoShadowLift: 1
    readonly property real glyphShare: 0.62
    // How soft the shadow lifting a logo off its shape is (MultiEffect blur, 0..1).
    readonly property real logoShadowBlur: 0.4
    // The pulse beats out in this share of its way back (expressiveFastSpatial), so it snaps out and eases home.
    readonly property real pulseOutShare: 0.5
    // Drawn smooth, so the symbol stays clean while its shape rocks (a ringing call).
    property bool smoothGlyph: false
    property color shapeColor: Theme.primaryContainer
    property color iconColor: Theme.onPrimaryContainer
    readonly property bool still: Theme.currentAnimationBaseDuration <= 0 || SettingsData.reduceMotion
    readonly property bool hasImage: image.visible

    // At rest the first one (an alert's own, IslandNoticeIcon), then the icon's own cycle (shorter than DTextField's,
    // without the oval).
    property string restShape: "cookie9"
    readonly property var shapes: [root.restShape, "cookie4", "clover4", "sunny", "softBurst", "pentagon", "cookie6"]
    property int step: 0

    function poke() {
        root.step++;
        if (!root.still)
            pulse.restart();
    }

    implicitWidth: root.size
    implicitHeight: root.size

    DMaterialShape {
        id: shape

        anchors.fill: parent
        visible: !root.bare
        shape: root.shapes[root.step % root.shapes.length]
        color: root.shapeColor

        SequentialAnimation {
            id: pulse

            NumberAnimation {
                target: shape
                property: "scale"
                to: 1 + Kit.morphPulse
                duration: Theme.expressiveDurations.expressiveFastSpatial * root.pulseOutShare
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
            }
            NumberAnimation {
                target: shape
                property: "scale"
                to: 1
                duration: Theme.expressiveDurations.expressiveFastSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }
    }

    Image {
        id: image

        anchors.centerIn: parent
        width: root.iconSize
        height: width
        source: root.source
        sourceSize: Qt.size(width * root.logoDecodeScale, height * root.logoDecodeScale)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: status === Image.Ready
        // Lifted off the shape by a soft shadow, so the logo reads on top of it, never under a veil.
        layer.enabled: visible
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Theme.shadowStrong
            shadowBlur: root.logoShadowBlur
            shadowVerticalOffset: root.logoShadowLift
        }
    }

    DIcon {
        anchors.centerIn: parent
        visible: !image.visible
        name: root.iconName
        size: root.bare ? root.iconSize : Math.round(root.size * root.glyphShare)
        color: root.iconColor
        smoothTransform: root.smoothGlyph
    }
}
