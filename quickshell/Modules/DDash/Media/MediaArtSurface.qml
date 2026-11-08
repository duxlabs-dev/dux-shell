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
    property bool suspended: false
    property real spin: 0

    readonly property var spinShape: ({
            "cookie": {
                "shape": "cookie12",
                "lobes": 12,
                "duration": DashMetrics.mediaArtRotationDuration
            },
            // A square spun all the way round has to shrink into the inscribed circle; a sway lets it fill the box.
            "squircle": {
                "shape": "square",
                "lobes": 4,
                "sway": DashMetrics.mediaArtSwayAngle * Math.PI / 180,
                "duration": DashMetrics.mediaArtSwayDuration
            },
            "disc": {
                "shape": "circle",
                "lobes": 1,
                "disc": true,
                "duration": DashMetrics.mediaArtDiscRotationDuration
            }
        })[artStyle] ?? null
    readonly property bool shaped: spinShape !== null
    readonly property real sway: spinShape?.sway ?? 0
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    readonly property bool spinning: shaped && playing && visible && !suspended && animationsEnabled && live
    readonly property var morphSpring: Theme.springPreset("fast", Theme.expressiveDurations.expressiveFastSpatial)
    // Off-centre terms of the Material path are left out so the spin does not wobble.
    readonly property vector4d shapeTerms: {
        if (!shaped || spinShape.disc)
            return Qt.vector4d(0.5, 0, 0, 0);
        const radii = Shapes.polarProfile(spinShape.shape, 256);
        const scale = sway > 0 ? swayScale(radii, sway) : Shapes.morphScale([radii]);
        const terms = [scale * radii.reduce((sum, radius) => sum + radius, 0) / radii.length];
        for (let harmonic = 1; harmonic <= 3; harmonic++) {
            let sum = 0;
            for (let i = 0; i < radii.length; i++)
                sum += radii[i] * Math.cos(spinShape.lobes * harmonic * (-Math.PI + 2 * Math.PI * i / radii.length));
            terms.push(2 * scale * sum / radii.length);
        }
        return Qt.vector4d(terms[0], terms[1], terms[2], terms[3]);
    }

    function swayScale(radii, amplitude) {
        const steps = 24;
        let scale = 1;
        for (let i = 0; i < radii.length; i++) {
            const angle = -Math.PI + 2 * Math.PI * i / radii.length;
            for (let step = 0; step <= steps; step++) {
                const tilted = angle - amplitude + 2 * amplitude * step / steps;
                const boxEdge = 0.5 / Math.max(Math.abs(Math.cos(tilted)), Math.abs(Math.sin(tilted)));
                scale = Math.min(scale, boxEdge / radii[i]);
            }
        }
        return scale;
    }

    radius: {
        if (shaped)
            return 0;
        switch (artStyle) {
        case "circle":
            return width / 2;
        case "square":
            return width * DashMetrics.mediaArtSoftRadiusRatio * Theme.shapeScale;
        case "slanted":
            return 0;
        }
        return DashMetrics.mediaInnerRadius;
    }
    color: "transparent"
    antialiasing: true
    layer.enabled: shaped || artStyle === "slanted"
    layer.effect: shaped ? shapeEffect : slantedEffect

    onPlayingChanged: morphMotion.retarget(playing ? 1 : 0)
    onSpinningChanged: {
        if (!spinning) {
            if (spinMotion.running)
                spinMotion.pause();
            return;
        }
        if (spinMotion.paused)
            spinMotion.resume();
        else
            spinMotion.start();
    }
    // A running animation keeps the old duration, and a sway angle carried over into a spin would jump.
    onSpinShapeChanged: {
        spinMotion.stop();
        spin = 0;
        spinMotion.duration = spinShape?.duration ?? DashMetrics.mediaArtRotationDuration;
        if (spinning)
            spinMotion.start();
    }

    SpringMotion {
        id: morphMotion
        enabled: !Theme.springMotionDisabled
        stiffness: root.morphSpring.stiffness
        damping: root.morphSpring.damping
        Component.onCompleted: snapTo(root.playing ? 1 : 0)
    }

    NumberAnimation {
        id: spinMotion
        target: root
        property: "spin"
        from: 0
        to: 2 * Math.PI
        duration: DashMetrics.mediaArtRotationDuration
        loops: Animation.Infinite
    }

    Component {
        id: shapeEffect

        ShaderEffect {
            property real morph: morphMotion.value
            property real spinAngle: root.sway > 0 ? root.sway * Math.sin(root.spin) : root.spin
            property real sizePx: root.width
            property real lobes: root.spinShape?.lobes ?? 1
            property vector4d terms: root.shapeTerms
            property real disc: root.spinShape?.disc ? 1 : 0
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
