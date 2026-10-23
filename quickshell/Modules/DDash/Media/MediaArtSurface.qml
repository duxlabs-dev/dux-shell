pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Widgets
import qs.Common
import qs.Modules.DDash
import "../../../DCommon/Widgets/MaterialShapes.js" as Shapes

ClippingRectangle {
    id: root

    property string artStyle: MediaOptions.defaultArtStyle
    property bool playing: false
    property bool live: true
    property bool rotate: false
    property bool suspended: false
    property real spin: 0

    readonly property bool expressive: artStyle === "expressive"
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    readonly property bool spinning: expressive && rotate && playing && visible && !suspended && animationsEnabled && live
    readonly property var morphSpring: Theme.springPreset("fast", Theme.expressiveDurations.expressiveFastSpatial)
    // The 12-fold cosine terms of the cookie's polar radius. The off-centre terms of the Material
    // path are left out, so the shape spins about the artwork's centre without wobbling.
    readonly property vector4d cookieTerms: {
        const radii = Shapes.polarProfile("cookie12", 256);
        const terms = [radii.reduce((sum, radius) => sum + radius, 0) / radii.length];
        for (let harmonic = 1; harmonic <= 3; harmonic++) {
            let sum = 0;
            for (let i = 0; i < radii.length; i++)
                sum += radii[i] * Math.cos(12 * harmonic * (-Math.PI + 2 * Math.PI * i / radii.length));
            terms.push(2 * sum / radii.length);
        }
        return Qt.vector4d(terms[0], terms[1], terms[2], terms[3]);
    }

    radius: {
        switch (artStyle) {
        case "circle":
            return width / 2;
        case "square":
            return width * DashMetrics.mediaArtSoftRadiusRatio * Theme.shapeScale;
        case "slanted":
        case "expressive":
            return 0;
        }
        return DashMetrics.mediaInnerRadius;
    }
    color: "transparent"
    antialiasing: true
    layer.enabled: expressive || artStyle === "slanted"
    layer.effect: expressive ? shapeEffect : slantedEffect

    onPlayingChanged: morphMotion.retarget(playing ? 1 : 0)

    SpringMotion {
        id: morphMotion
        enabled: !Theme.springMotionDisabled
        stiffness: root.morphSpring.stiffness
        damping: root.morphSpring.damping
        Component.onCompleted: snapTo(root.playing ? 1 : 0)
    }

    NumberAnimation on spin {
        from: 0
        to: 2 * Math.PI
        duration: DashMetrics.mediaArtRotationDuration
        loops: Animation.Infinite
        running: root.expressive && root.rotate
        paused: !root.spinning
    }

    Component {
        id: shapeEffect

        ShaderEffect {
            property real morph: morphMotion.value
            property real spinAngle: root.spin
            property real sizePx: root.width
            property real lobes: 12
            property vector4d terms: root.cookieTerms
            fragmentShader: Qt.resolvedUrl("../../../Shaders/qsb/art_shape.frag.qsb")
        }
    }

    Component {
        id: slantedEffect

        MultiEffect {
            maskEnabled: true
            maskSource: slantedShapeMask.item
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Loader {
        id: slantedShapeMask
        anchors.fill: parent
        active: root.artStyle === "slanted"
        visible: false

        sourceComponent: Item {
            layer.enabled: true

            Shape {
                id: slantedShape

                readonly property real scaleX: boundingRect.width > 0 ? root.width / boundingRect.width : 1
                readonly property real scaleY: boundingRect.height > 0 ? root.height / boundingRect.height : 1

                x: -boundingRect.x * scaleX
                y: -boundingRect.y * scaleY
                width: root.width
                height: root.height
                preferredRendererType: Shape.CurveRenderer
                transform: Scale {
                    xScale: slantedShape.scaleX
                    yScale: slantedShape.scaleY
                }

                ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: Theme.withAlpha(Theme.surface, 1)

                    PathSvg {
                        path: Shapes.buildPath("slanted", root.width, root.height, Theme.shapeScale === 0)
                    }
                }
            }
        }
    }
}
