import QtQuick
import qs.Common
import qs.Modules.DIsland.Kit
import "../../Common/IslandKit.js" as Kit
import "../../Common/IslandLiquidPose.js" as Pose
import "../../Common/IslandLiquidSplit.js" as Split

// Liquid: the pill parts at its icon (the icon's end, the rest), a thread stretches and snaps, the parts fly apart on their own
// springs and merge again through a growing bridge (IslandLiquidSplit.js). The leaving part rides the wing's tile spring, the
// other one of its own drawn from it. Drawn by one shader (cached, stepped and redrawn at most 60 times a second) only while it
// moves, outlined while apart; at rest the wing's own body.
TileTransition {
    id: liquid

    // Inputs of this variant only.
    property real cardTarget: 0
    property bool reducedMotion: false
    // A hover card: the wing's own shape takes over.
    property bool blocked: false
    property int side: -1
    property real iconShift: 0
    property real cornerRadius: 0
    property real dropBy: 0
    property bool farEdge: false
    property real shapeLead: 1
    property real stiffness: 1
    property real mass: 1
    property real presence: 1
    property real level: -1
    property real gaugeOpacity: 1
    // The wing's tones: its gauge's track and liquid, its body's fill and edge.
    property color trackColor
    property color liquidColor
    property real inset: 4
    property real trackGap: 3
    property color fillColor
    property color edgeColor
    property real edgeWidth: 0

    property bool moving: false
    // The parts apart (or the seam open): outlined, so they read on any background.
    property bool apart: false
    property var st: Split.create(0)
    property var env: ({
            "s": 0,
            "L": 0,
            "sh": 0,
            "up": 0,
            "drop": 0,
            "far": false,
            "shapeLead": 1,
            "k": 1,
            "mass": 1,
            "tile": 0,
            "side": 1,
            "radius": 0,
            "inset": 0,
            "trackGap": 0,
            "level": -1,
            "area": null
        })
    property var area: ({
            "x0": 0,
            "x1": 1,
            "y0": 0,
            "y1": 1
        })
    property real poseIconX: 0
    property real poseIconY: 0
    // A hover taking over mid-trip: the last drawing fades out and the icon glides home from where it was.
    property real handoff: 0
    property real heldDx: 0
    property real heldDy: 0
    // The value (a level's percent) shows again once at rest.
    property real reveal: 1
    property bool revealing: false
    readonly property int fadeMs: Math.round(1000 * Split.fadeTime({
        "k": Math.max(1e-3, liquid.stiffness),
        "mass": Math.max(1e-3, liquid.mass)
    }))

    // How far the wing's box has moved down (up on a bottom bar) since the flat pill: frame to wing coordinates.
    readonly property real lift: liquid.farEdge ? -(liquid.dropBy * liquid.tile + Kit.mix(liquid.pillThick, liquid.tileThick, Kit.unit(liquid.tile * liquid.shapeLead)) - liquid.pillThick) : liquid.dropBy * liquid.tile
    readonly property real restIconX: Kit.mix(liquid.side < 0 ? liquid.pillThick / 2 : liquid.width - liquid.iconShift - liquid.pillThick / 2, liquid.width / 2, liquid.tileOf)
    readonly property real restIconY: Kit.mix(liquid.pillIconY, liquid.tileIconY, liquid.tileOf)

    bodyShown: !liquid.moving
    gaugeShown: !liquid.moving
    iconDx: liquid.moving ? (liquid.side < 0 ? liquid.width - liquid.poseIconX : liquid.poseIconX) - liquid.restIconX : liquid.handoff * liquid.heldDx
    iconY: liquid.moving ? liquid.poseIconY - liquid.lift : liquid.restIconY + liquid.handoff * liquid.heldDy
    valueOpacity: liquid.moving ? 0 : liquid.reveal
    z: 0.5

    function refresh() {
        const e = liquid.env;
        e.s = liquid.pillThick;
        e.L = liquid.restLength;
        e.sh = liquid.iconShift;
        e.up = liquid.tileThick;
        e.drop = liquid.dropBy;
        e.far = liquid.farEdge;
        e.shapeLead = liquid.shapeLead;
        e.k = Math.max(1e-3, liquid.stiffness);
        e.mass = Math.max(1e-3, liquid.mass);
        e.tile = liquid.tile;
        e.side = liquid.side;
        e.radius = liquid.cornerRadius;
        e.inset = liquid.inset;
        e.trackGap = liquid.trackGap;
        e.level = liquid.level;
    }

    function snap() {
        liquid.moving = false;
        liquid.apart = false;
        liquid.st = Split.create(liquid.cardTarget);
    }

    // Mid-trip, the wing's body takes over where it is: no jump, the drawing fades out over it and the icon glides home.
    function handOff() {
        if (!liquid.moving)
            return liquid.snap();
        liquid.heldDx = liquid.iconDx;
        liquid.heldDy = liquid.iconY - liquid.restIconY;
        liquid.snap();
        handoffFade.restart();
        liquid.reveal = 0;
        liquid.revealing = true;
    }

    function toggle() {
        if (liquid.reducedMotion) {
            liquid.snap();
            fadeIn.restart();
            return;
        }
        if (liquid.blocked || liquid.presence < 0.5)
            return liquid.handOff();
        liquid.refresh();
        if (!liquid.moving)
            liquid.st = Split.create(liquid.tile > 0.5 ? 1 : 0);
        Split.start(liquid.st, liquid.cardTarget, liquid.tile);
        liquid.area = Split.bounds(liquid.env);
        liquid.env.area = liquid.area;
        Split.step(liquid.st, 0, liquid.env);
        liquid.publish();
        handoffFade.stop();
        liquid.revealing = false;
        liquid.handoff = 0;
        liquid.reveal = 0;
        liquid.moving = true;
    }

    function publish() {
        const o = Pose.pose(liquid.st, liquid.env), names = Pose.uniforms;
        for (let i = 0; i < names.length; i++)
            fx[names[i]] = o[i];
        liquid.poseIconX = liquid.st.sh.iconX;
        liquid.poseIconY = liquid.st.sh.iconY;
        liquid.apart = liquid.st.sh.apart;
    }

    onCardTargetChanged: {
        if (liquid.active)
            liquid.toggle();
    }
    onActiveChanged: liquid.snap()
    onBlockedChanged: {
        if (liquid.blocked)
            liquid.handOff();
    }
    onReducedMotionChanged: liquid.snap()
    Component.onCompleted: liquid.snap()

    // A1: brief fades of the tile's own layers on DMS's durations, no kit part for them; each runs once and stops (K1).
    NumberAnimation {
        id: fadeIn

        target: liquid
        property: "fade"
        from: 0
        to: 1
        duration: Theme.shortDuration
    }
    NumberAnimation {
        id: handoffFade

        target: liquid
        property: "handoff"
        from: 1
        to: 0
        duration: liquid.fadeMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.expressiveCurves.emphasizedDecel
    }
    // A1: the kit's Timer clock, not a FrameAnimation, so the island's window is not redrawn for the liquid; it runs only
    // while the liquid moves or its value fades back in (K1).
    IslandDecorClock {
        running: liquid.active && (liquid.moving || liquid.revealing)
        onTick: dt => {
            if (!liquid.moving) {
                liquid.reveal = Math.min(1, liquid.reveal + 1000 * dt / liquid.fadeMs);
                liquid.revealing = liquid.reveal < 1;
                return;
            }
            liquid.refresh();
            Split.step(liquid.st, dt, liquid.env);
            liquid.publish();
            if (liquid.st.settled) {
                liquid.moving = false;
                liquid.apart = false;
                liquid.revealing = true;
            }
        }
    }

    ShaderEffect {
        id: fx

        // The uniforms Pose.pose() writes (Pose.uniforms), set one by one: nothing is built per frame.
        property real head0
        property real head1
        property real head2
        property real head3
        property real headR0
        property real headR1
        property real headR2
        property real headR3
        property real tail0
        property real tail1
        property real tail2
        property real tail3
        property real tailR0
        property real tailR1
        property real tailR2
        property real tailR3
        property real neck0
        property real neck1
        property real neck2
        property real neck3
        property real neckRadius
        property real goo
        property real bulge0
        property real bulge1
        property real bulge2
        property real track0
        property real track1
        property real track2
        property real track3
        property real trackRadius
        property real fill0
        property real fill1
        property real fill2
        property real fill3
        property real fillRadius
        property real trackUnder
        property real trackGap
        property vector2d itemSize: Qt.vector2d(width, height)
        property real gaugeOpacity: liquid.gauged && liquid.level >= 0 ? liquid.gaugeOpacity : 0
        property real edgeWidth: liquid.apart ? Math.max(1, liquid.edgeWidth) : liquid.edgeWidth
        property color fillColor: liquid.fillColor
        property color edgeColor: liquid.apart ? Theme.outlineVariant : liquid.edgeColor
        property color trackColor: liquid.trackColor
        property color liquidColor: liquid.liquidColor

        visible: liquid.active && (liquid.moving || liquid.handoff > 0)
        opacity: liquid.moving ? 1 : liquid.handoff
        x: liquid.side < 0 ? liquid.width - liquid.area.x1 : liquid.area.x0
        y: liquid.area.y0 - liquid.lift
        width: Math.ceil(liquid.area.x1 - liquid.area.x0)
        height: Math.ceil(liquid.area.y1 - liquid.area.y0)
        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/liquid_split.frag.qsb")
    }
}
