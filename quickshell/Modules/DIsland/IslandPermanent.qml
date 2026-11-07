pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.DCommon.Widgets
import qs.Common
import qs.Modules.SurfaceWidgets
import qs.Services
import qs.Widgets
import "../../Common/IslandKit.js" as IslandKit

// shortcut: horizontal bars only, a vertical bar shows no permanent bubble; add a vertical layout if a plugin needs one.
// A plugin's bubble that always stays (IslandActivityService.setPermanent): small (a mini bubble, just its icon) beside
// the island on its side, floating with no outline. A file dragged over the bar swells it into a normal bubble that takes it, its icon pulsing on that spring
// and drawing a ring in; an event on the same side shrinks it into a dot tucked at the bottom left corner of that event's
// bubble, like a badge, and it grows back in its place when the event leaves. After each move it drifts a few seconds, then
// rests. Its corners are the wings' (DMS's corner setting), scaled to its size.
// Three numbers on the island's own spring (as tuned by DMS) drive it all, so every change starts from what is on screen.
Item {
    id: perm

    required property var bubbles
    // The wing of the side it lives on: its event turns the bubble into a dot on that wing's corner.
    required property var wing

    // The entry this side shows (IslandActivityService.permanentOn), null while it leaves.
    required property var spec
    readonly property int side: perm.wing.side
    readonly property bool on: !!perm.spec && !perm.bubbles.isVertical && perm.bubbles.controller.bubblesEnabled
    readonly property bool receiving: perm.on && perm.spec.receiving === true
    readonly property bool tucked: perm.on && perm.wing.has

    // Its icon alone says whose it is: the plugin's name, and what it does with a file when it says.
    Accessible.role: Accessible.Graphic
    Accessible.name: PluginService.availablePlugins[perm.spec?.pluginId]?.name || perm.spec?.pluginId || ""
    Accessible.description: perm.spec?.label ?? ""
    readonly property var tone: perm.bubbles.toneOf("media")
    readonly property color glyphColor: perm.tone[1]

    readonly property real full: perm.bubbles.size
    // Its sizes as shares of a bubble's: at rest (a mini bubble) and as a dot.
    readonly property real miniShare: 0.72
    readonly property real dotShare: 0.3
    readonly property real mini: perm.full * perm.miniShare
    readonly property real dotSize: Math.round(perm.full * perm.dotShare)

    // width = presence, height = growth for a drop, offsetCross = how far into the dot, all in springUnit.
    VectorSpringMotion {
        id: spring

        reducedMotion: perm.bubbles.reducedMotion
        mass: perm.bubbles.motion.mass
    }
    // Loaded with its entry: born from nothing on its spring, then it drifts, as when it comes back to rest.
    Component.onCompleted: {
        spring.snapTo(perm.target(false));
        perm.retarget();
        if (perm.resting && !perm.bubbles.reducedMotion)
            driftRun.restart();
    }
    function target(shown) {
        const u = perm.bubbles.springUnit;
        return {
            "width": shown && perm.on ? u : 0,
            "height": shown && perm.receiving && !perm.tucked ? u : 0,
            "offsetAlong": 0,
            "offsetCross": shown && perm.tucked ? u : 0,
            "topLeftRadius": 0,
            "topRightRadius": 0,
            "bottomLeftRadius": 0,
            "bottomRightRadius": 0
        };
    }
    // Same spring as a wing being born (the island's stiffness, softened, with its overshoot); shrinking into the dot is
    // fully damped so the badge lands clean.
    function retarget() {
        const b = perm.bubbles;
        const ratio = perm.tucked ? b.outDampingRatio : b.inDampingRatio;
        spring.stiffness = b.motion.stiffness * b.inStiffness;
        spring.damping = 2 * ratio * Math.sqrt(spring.stiffness * spring.mass);
        spring.setTarget(perm.target(true));
    }
    onOnChanged: perm.retarget()
    onReceivingChanged: perm.retarget()
    onTuckedChanged: perm.retarget()

    readonly property real presence: Math.max(0, spring.currentWidth / perm.bubbles.springUnit)
    readonly property real grow: spring.currentHeight / perm.bubbles.springUnit
    readonly property real dotness: IslandKit.unit(spring.currentOffsetCross / perm.bubbles.springUnit)
    // How fast it swells, a few units a second at the start of a drop; the icon's pulse rides it.
    readonly property real growSpeed: spring.velocityHeight / perm.bubbles.springUnit

    // Drift (from concept B): one and a half slow loops that fade out, started by whatever brings it back to rest beside
    // the island, then nothing runs.
    property real drift: 1
    // The drift's loops at the breath's own pace, never longer than maxDriftMs however slow the breath is set.
    readonly property int driftMs: 5000
    // Motion that starts on its own stops within 5 s (WCAG 2.2.2).
    readonly property int maxDriftMs: 5000
    readonly property real driftLoops: 1.5
    // How high the loop rises, as a share of how far it reaches out.
    readonly property real driftRise: 0.6
    readonly property bool resting: perm.on && !perm.receiving && !perm.tucked
    onRestingChanged: {
        if (perm.resting && !perm.bubbles.reducedMotion)
            driftRun.restart();
    }
    // A1: a one-shot drift after a move, capped at maxDriftMs, no kit part for it; nothing runs once it is done (K1).
    NumberAnimation {
        id: driftRun

        target: perm
        property: "drift"
        from: 0
        to: 1
        duration: Math.min(perm.maxDriftMs, perm.driftMs / perm.bubbles.breathPace)
    }
    readonly property real driftFade: (1 - perm.drift) * (1 - perm.dotness) * IslandKit.unit(1 - perm.grow)
    readonly property real driftPhase: perm.drift * 2 * Math.PI * perm.driftLoops
    // A small loop seen from above: away from the island and back (never into it), rising and dipping.
    readonly property real reach: Theme.spacingXS
    readonly property real driftAlong: perm.side * perm.reach * 0.5 * (1 - Math.cos(perm.driftPhase)) * perm.driftFade
    readonly property real driftCross: -perm.reach * perm.driftRise * Math.sin(perm.driftPhase) * perm.driftFade

    // At rest: beside the island's edge, where a wing of this side would start, one slit away, centered on the island's row.
    readonly property real restH: IslandKit.mix(perm.mini, perm.full, perm.grow)
    readonly property real restW: IslandKit.mix(perm.mini, perm.full + label.implicitWidth + Theme.spacingM, perm.grow)
    readonly property real leadEdge: Math.min(perm.bubbles.leadEdge, perm.bubbles.surface.currentAlongPos)
    readonly property real trailEdge: Math.max(perm.bubbles.trailEdge, perm.bubbles.surface.currentAlongPos + perm.bubbles.surface.currentVisualAlong)
    readonly property real restCx: (perm.side < 0 ? perm.leadEdge - perm.bubbles.slit - perm.restW / 2 : perm.trailEdge + perm.bubbles.slit + perm.restW / 2) + perm.driftAlong
    readonly property real restCy: perm.bubbles.crossOf(perm.bubbles.nearCross + perm.bubbles.rowOffset, perm.bubbles.size) + perm.bubbles.size / 2 + perm.driftCross

    // Tucked: on the outline of the event bubble's bottom left corner (45 degrees round its radius), following the wing's
    // birth scale (from half its size at the island's edge) so the dot rides the bubble as it grows.
    readonly property real wingScale: IslandKit.appearScale(perm.wing.presence)
    // Read only while tucked: at rest the corner has no say, and a wing not laid out yet has no radius.
    readonly property real cornerInset: perm.dotness > 0 ? perm.wing.radius * (1 - Math.SQRT1_2) : 0
    readonly property real cornerX: perm.wing.x + (perm.wing.side < 0 ? perm.wing.width : 0) + (perm.cornerInset - (perm.wing.side < 0 ? perm.wing.width : 0)) * perm.wingScale
    readonly property real cornerY: perm.wing.y + perm.wing.height / 2 + (perm.wing.height / 2 - perm.cornerInset) * perm.wingScale

    readonly property real h: IslandKit.mix(perm.restH, perm.dotSize, perm.dotness)
    readonly property real w: IslandKit.mix(perm.restW, perm.dotSize, perm.dotness)
    readonly property real cx: IslandKit.mix(perm.restCx, perm.cornerX, perm.dotness)
    readonly property real cy: IslandKit.mix(perm.restCy, perm.cornerY, perm.dotness)

    // Round when small (rest and dot); the wings' corner comes in as it swells for a file.
    readonly property real wingRadius: Math.min(perm.h / 2, perm.w / 2, perm.bubbles.pillRadius)
    readonly property real radius: IslandKit.mix(perm.h / 2, perm.wingRadius, IslandKit.unit(perm.grow) * (1 - perm.dotness))

    x: perm.cx - perm.w / 2
    y: perm.cy - perm.h / 2
    width: perm.w
    height: perm.h
    visible: perm.presence > IslandKit.shownFrom
    opacity: IslandKit.appearOpacity(perm.presence)
    scale: IslandKit.appearScale(perm.presence)

    // Drawn in: one ring closing on the bubble while it swells for a file, read from the same spring (gone at rest).
    Rectangle {
        // It closes in from this many times the bubble's size.
        readonly property real ringFrom: 1.7
        readonly property real k: IslandKit.mix(ringFrom, 1, IslandKit.unit(perm.grow))
        anchors.centerIn: parent
        width: perm.w + perm.h * (k - 1)
        height: perm.h * k
        radius: perm.radius * k
        color: "transparent"
        border.width: 1.5
        border.color: perm.tone[0]
        opacity: (perm.receiving ? 0.5 : 0) * IslandKit.unit(4 * perm.grow * (1 - perm.grow)) * (1 - perm.dotness)
        visible: opacity > IslandKit.shownFrom
    }

    // The capsule in the island's color, floating with no outline; as a dot it turns to the app's accent, ringed by the
    // island's color so it reads clean on the event bubble as on the wallpaper.
    Rectangle {
        anchors.fill: parent
        radius: perm.radius
        // A touch lighter than the island so it still reads on a dark wallpaper with no outline.
        color: Qt.tint(Qt.tint(perm.bubbles.color, Theme.surfaceTextHover), Theme.withAlpha(perm.tone[0], perm.dotness))
        border.width: 1.5 * IslandKit.unit(2 * perm.dotness - 1)
        border.color: perm.bubbles.color
    }

    // The icon on its backdrop, as on a wing (corner one rim inside the capsule's); it goes as the bubble becomes a dot.
    Item {
        id: face

        readonly property real d: perm.h - 2 * perm.bubbles.rim
        // Gone this far on the way to a dot.
        readonly property real goneAt: 0.4
        x: (perm.side < 0 ? 0 : perm.w - perm.h) + perm.bubbles.rim
        y: perm.bubbles.rim
        width: face.d
        height: face.d
        opacity: IslandKit.unit(1 - perm.dotness / face.goneAt)
        visible: opacity > IslandKit.shownFrom

        // An app's icon backdrop stays round; only the bubble takes the wings' corners.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: perm.tone[0]
        }

        // The icon: squeezed as the bubble starts to swell, then stretched toward the file while it is held open; all from
        // the growth spring, so it settles with it.
        Item {
            id: glyph

            // Squeeze per unit of swelling speed, kept under pulseMax; stretchMax once fully swollen; its share of the face.
            readonly property real pulseGain: 0.02
            readonly property real pulseMax: 0.14
            readonly property real stretchMax: 0.12
            readonly property real share: 0.78
            readonly property real pulse: Math.max(-glyph.pulseMax, Math.min(glyph.pulseMax, glyph.pulseGain * perm.growSpeed))
            anchors.centerIn: parent
            width: face.d * glyph.share
            height: width
            transform: Scale {
                origin.x: glyph.width / 2
                origin.y: 0
                xScale: 1 + glyph.pulse
                yScale: 1 - glyph.pulse + glyph.stretchMax * IslandKit.unit(perm.grow)
            }

            // The app's own icon, one colour, tinted like a wing's glyph.
            Image {
                id: appImage

                anchors.fill: parent
                sourceSize: Qt.size(64, 64)
                source: perm.spec?.image ?? ""
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: appImage
                colorization: 1
                colorizationColor: perm.glyphColor
                visible: appImage.status === Image.Ready
            }

            // Without an icon: a plugin's, as its activity bubble shows it.
            DIcon {
                anchors.centerIn: parent
                visible: appImage.status !== Image.Ready
                name: "extension"
                size: glyph.width
                color: perm.glyphColor
            }
        }
    }

    // Only the swollen bubble says what it does with the file.
    StyledText {
        id: label

        x: perm.side < 0 ? perm.h + Theme.spacingXS : Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: perm.spec?.label ?? ""
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceText
        opacity: IslandKit.unit((perm.grow - 0.6) / 0.4) * (1 - perm.dotness)
        visible: opacity > IslandKit.shownFrom
    }
}
