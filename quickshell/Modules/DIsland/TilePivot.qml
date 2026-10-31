import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Modules.DIsland.Kit
import "../../Common/IslandKit.js" as Kit
import "../../Common/IslandLiquidSplit.js" as Split
import "../../Common/IslandTileSprings.js" as Springs

// Pivot: the bubble turns a quarter round its icon as it lands (the icon stays upright), then the liquid falls to the bottom
// on a slow spring and sloshes. Only a level tile pivots (its icon tops it, as it ends the pill); the others keep the plain morph.
// While it pivots the wing is laid out as the upright tile, turned back flat at the start: same outline as the pill, and the
// validated tile at the end, where it hands back to the stock layout and gauge.
TileTransition {
    id: pivot

    // Extra inputs, bound by the wing.
    property bool open: false
    property int side: -1
    property real level: 0
    // The wing's gauge tones.
    property color trackColor
    property color liquidColor
    property real trackGap: 3
    property real radius: 0
    property real content: 1
    property bool reduced: false
    property bool farEdge: false

    property real rotX: 0
    property real sizeX: 0
    property real fallX: 0
    property real slosh: 0
    property real phase: 0
    property real clock: 0
    property bool moving: false

    readonly property bool pivoting: pivot.active && pivot.carded && pivot.gauged && (pivot.moving || pivot.slosh > Springs.sloshRest || (pivot.open ? pivot.tileShape < 1 : pivot.tile >= Kit.shownFrom))
    readonly property real pillLong: pivot.restLength
    readonly property real side0: pivot.side < 0 ? -1 : 1
    // Upright frame: width is the pill's thickness growing to the tile's side, height its length growing to the tile's height.
    readonly property real frameW: Math.max(0, Kit.mix(pivot.pillThick, pivot.tileSide, pivot.sizeX))
    readonly property real frameH: Math.max(0, Kit.mix(pivot.pillLong, pivot.tileThick, pivot.sizeX))
    // The wing's box keeps its inner edge; this brings the icon from the pill's outer end to the tile's top as it flies.
    readonly property real flatShift: pivot.pivoting ? (pivot.pillLong - pivot.pillThick) * (1 - Kit.unit(pivot.tile)) : 0
    readonly property real shiftX: pivot.side0 * pivot.flatShift
    // On a bar at the far edge the box keeps its bottom, so the icon is brought down to the pill's middle too.
    readonly property real shiftY: pivot.farEdge ? pivot.flatShift : 0

    length: pivot.pivoting ? pivot.frameW : Kit.mix(pivot.restLength, pivot.tileSide, pivot.tileShape)
    thick: pivot.pivoting ? pivot.frameH : Kit.mix(pivot.pillThick, pivot.tileThick, pivot.tileShape)
    iconY: pivot.pivoting ? pivot.frameW / 2 : Kit.mix(pivot.pillIconY, pivot.tileIconY, pivot.tileOf)
    // Left wing: the upright frame turned back a quarter counterclockwise lies flat with its icon at the outer (left) end.
    turn: pivot.pivoting ? pivot.side0 * 90 * (1 - pivot.rotX) : 0
    gaugeShown: !pivot.pivoting
    z: 0.5

    // name: [stiffness, damping ratio, delay opening (s), delay closing (s)], mass 1 (IslandTileSprings.stepDelayed): the
    // turn, the size and the fall, tuned by eye. The flight itself stays on the wing's tile spring.
    readonly property var springs: ({
            "rot": [300, 0.55, 0.03, 0.06],
            "size": [340, 0.55, 0.04, 0.04],
            "fall": [150, 0.4, 0.22, 0]
        })
    readonly property var springNames: Object.keys(pivot.springs)
    property var sim: ({})
    // How much the fall's and the turn's speed kick the slosh (units a second).
    readonly property real fallKick: 1.4
    readonly property real turnKick: 0.3

    function snap() {
        const t = pivot.open ? 1 : 0;
        for (const name of pivot.springNames) {
            pivot.sim[name] = {
                "x": t,
                "v": 0,
                "t": t,
                "next": t,
                "at": 0
            };
        }
        pivot.rotX = pivot.sizeX = pivot.fallX = t;
        pivot.slosh = 0;
        pivot.moving = false;
    }
    onOpenChanged: {
        if (!pivot.active || pivot.reduced || !pivot.gauged || !pivot.sim.rot) {
            pivot.snap();
            return;
        }
        const t = pivot.open ? 1 : 0;
        for (const name of pivot.springNames) {
            const c = pivot.springs[name];
            pivot.sim[name].next = t;
            pivot.sim[name].at = pivot.clock + (pivot.open ? c[2] : c[3]);
        }
        pivot.moving = true;
    }
    onActiveChanged: pivot.snap()
    onReducedChanged: pivot.snap()
    Component.onCompleted: pivot.snap()

    // A1: the kit's Timer clock, so the island's window is not redrawn for the tile; it runs only while the tile turns or
    // sloshes (K1), its step is IslandTileSprings.stepDelayed, shared with TileJelly.
    IslandDecorClock {
        running: pivot.active && pivot.gauged && (pivot.moving || pivot.slosh > Springs.sloshRest)
        onTick: frame => {
            const dt = Math.min(Split.maxFrame, frame * pivot.pace);
            const sim = pivot.sim, names = pivot.springNames;
            pivot.clock = Springs.stepDelayed(sim, pivot.springs, names, pivot.clock, dt);
            // Slosh: kicked by the fall and the turn, it rings down; the wave's phase runs on.
            pivot.slosh = Springs.slosh(pivot.slosh, dt, (Math.abs(sim.fall.v) * pivot.fallKick + Math.abs(sim.rot.v) * pivot.turnKick) * Springs.sloshGain);
            pivot.phase += dt * Springs.sloshWave;
            let moving = false;
            for (let i = 0; i < names.length; i++) {
                if (!Springs.settled(sim[names[i]]))
                    moving = true;
            }
            pivot.rotX = sim.rot.x;
            pivot.sizeX = sim.size.x;
            pivot.fallX = sim.fall.x;
            pivot.moving = moving;
        }
    }

    // The liquid in the upright frame: its long axis runs down from the icon. Flat on the pill it lies against the icon's end;
    // once upright it falls to the bottom, where it is the stock gauge.
    Item {
        id: well

        readonly property real inset: Theme.spacingXS
        readonly property real gx: well.inset
        readonly property real gy: pivot.frameW + pivot.trackGap
        readonly property real gw: Math.max(0, pivot.width - 2 * well.inset)
        readonly property real gh: Math.max(0, pivot.height - well.gy - well.inset)
        readonly property real fall: Math.max(-0.1, Math.min(1.1, pivot.fallX))
        readonly property real len: well.gh * Kit.unit(pivot.level)
        readonly property real start: well.gy + (well.gh - well.len) * Kit.unit(well.fall)
        readonly property var outline: {
            if (!pivot.pivoting)
                return [];
            const pts = [];
            const n = 14;
            const top = well.gy, bottom = well.gy + well.gh;
            // A1: the kit's wave along the well (i / n, 0 to 1), the well being `fronts` kit fronts wide: half a radian a point.
            const fronts = n / (2 * Math.PI);
            const clampY = y => Math.max(top, Math.min(bottom, y));
            for (let i = 0; i <= n; i++) {
                const k = Math.sin(Math.PI * i / n);
                // The leading end waves while it falls, and lies flat on the floor once it is there.
                pts.push(Qt.point(well.gx + well.gw * i / n, clampY(well.start + well.len + Kit.wave(fronts * i / n, pivot.slosh, pivot.phase) * k * Math.max(0, 1 - well.fall))));
            }
            for (let i = n; i >= 0; i--) {
                const k = Math.sin(Math.PI * i / n);
                pts.push(Qt.point(well.gx + well.gw * i / n, clampY(well.start - Kit.wave(fronts * i / n, pivot.slosh, pivot.phase + 1) * k * well.fall)));
            }
            return pts;
        }

        anchors.fill: parent
        visible: pivot.pivoting
        opacity: pivot.content

        Rectangle {
            x: well.gx
            y: well.gy
            width: well.gw
            height: well.gh
            radius: Math.max(0, pivot.radius - well.inset)
            color: pivot.trackColor
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: pivot.liquidColor
                strokeColor: "transparent"
                strokeWidth: 0

                PathPolyline {
                    path: well.outline
                }
            }
        }
    }
}
