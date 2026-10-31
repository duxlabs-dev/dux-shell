import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Modules.DIsland.Kit
import "../../Common/IslandKit.js" as Kit
import "../../Common/IslandLiquidSplit.js" as Split
import "../../Common/IslandTileSprings.js" as Springs

// Jelly: the width first on a stiff spring, the height 45 ms after with a bounce, the icon sliding up while the liquid turns from
// filling from the icon's side to filling from the bottom, sloshing as it goes. Springs and delays are tuned by eye;
// they tick only while one of them moves.
TileTransition {
    id: jelly

    // Extra inputs, bound by the wing.
    // The tile spring's target (0 pill, 1 tile): every jelly spring heads there, each with its own delay.
    property real goal: 0
    property bool reducedMotion: false
    property real level: -1
    property int side: -1
    property real radius: 0
    property real iconShift: 0
    property real trackGap: 3
    property real content: 1
    // The pill already shows its own liquid (wave dial style): this one takes over without fading in.
    property bool pillLiquid: false
    // The wing's gauge tones.
    property color trackColor
    property color liquidColor

    // Spring positions, 0 pill to 1 tile (they overshoot).
    property real w: 0
    property real h: 0
    property real ic: 0
    property real axis: 0
    property real lev: 0
    property real slosh: 0
    property real phase: 0

    length: Kit.mix(jelly.restLength, jelly.tileSide, jelly.w)
    thick: Kit.mix(jelly.pillThick, jelly.tileThick, jelly.h)
    iconY: Kit.mix(jelly.pillIconY, jelly.tileIconY, Kit.unit(jelly.ic))
    gaugeShown: false

    // How much the height's bounce and the level's speed kick the slosh, beside the axis turning (units a second).
    readonly property real heightKick: 0.6
    readonly property real levelKick: 6
    // name: [stiffness, damping ratio, delay opening (ms), delay closing (ms)], mass 1 (IslandTileSprings.stepDelayed).
    readonly property var springs: ({
            "w": [520, 0.5, 0, 0],
            "h": [300, 0.45, 45, 0],
            "ic": [420, 0.55, 20, 20],
            "axis": [200, 0.6, 80, 0],
            "lev": [260, 0.55, 0, 0]
        })
    readonly property var springNames: Object.keys(jelly.springs)
    property var sim: ({})

    function levelGoal() {
        return Kit.unit(jelly.level);
    }
    function goalOf(name) {
        return name === "lev" ? jelly.levelGoal() : jelly.goal;
    }
    function snap() {
        for (const name in jelly.springs) {
            jelly.sim[name] = {
                "x": jelly.goalOf(name),
                "v": 0,
                "t": jelly.goalOf(name),
                "next": jelly.goalOf(name),
                "at": 0
            };
            jelly[name] = jelly.sim[name].x;
        }
        jelly.slosh = 0;
        ticker.running = false;
    }
    // Queue a new target for each spring, after its delay, and start ticking. A spring with no state yet (a change landing
    // while the first snap fills them, as when the transition is made already active) snaps them all.
    function aim(names) {
        if (!jelly.active || jelly.reducedMotion || names.some(name => !jelly.sim[name])) {
            jelly.snap();
            return;
        }
        const now = ticker.clock;
        for (const name of names) {
            const c = jelly.springs[name];
            const opening = jelly.goalOf(name) > jelly.sim[name].next;
            jelly.sim[name].next = jelly.goalOf(name);
            jelly.sim[name].at = now + (opening ? c[2] : c[3]) / 1000;
        }
        ticker.running = true;
    }
    onGoalChanged: jelly.aim(["w", "h", "ic", "axis"])
    onLevelChanged: jelly.aim(["lev"])
    onActiveChanged: jelly.snap()
    onReducedMotionChanged: jelly.snap()
    Component.onCompleted: jelly.snap()

    // A1: the kit's Timer clock, so the island's window is not redrawn for the tile; it runs only while one spring moves
    // (K1), its step is IslandTileSprings.stepDelayed, shared with TilePivot.
    IslandDecorClock {
        id: ticker

        property real clock: 0

        onTick: frame => {
            const names = jelly.springNames;
            const dt = Math.min(Split.maxFrame, frame * jelly.pace);
            ticker.clock = Springs.stepDelayed(jelly.sim, jelly.springs, names, ticker.clock, dt);
            let moving = false;
            for (let i = 0; i < names.length; i++) {
                const s = jelly.sim[names[i]];
                if (!Springs.settled(s))
                    moving = true;
                jelly[names[i]] = s.x;
            }
            // Slosh: kicked by the axis turning, the height bouncing and the level moving, it rings down; the wave runs on.
            const kick = Math.abs(jelly.sim.axis.v) + Math.abs(jelly.sim.h.v) * jelly.heightKick;
            jelly.slosh = Springs.slosh(jelly.slosh, dt, kick * Springs.sloshGain + Math.abs(jelly.sim.lev.v) * jelly.levelKick);
            jelly.phase += dt * Springs.sloshWave;
            if (jelly.slosh > Springs.sloshRest)
                moving = true;
            else
                jelly.slosh = 0;
            ticker.running = moving;
        }
    }

    // The liquid's room: right of the icon on the pill, below it on the tile, mixed by the axis spring (outer end at x = 0).
    readonly property real ax: Kit.unit(jelly.axis)
    readonly property real inset: Theme.spacingXS
    readonly property real hx: jelly.pillThick + jelly.iconShift + jelly.trackGap
    readonly property real gx: Kit.mix(jelly.hx, jelly.inset, jelly.ax)
    readonly property real gy: Kit.mix(jelly.inset, jelly.tileSide + jelly.trackGap, jelly.ax)
    readonly property real gw: Math.max(0, Kit.mix(jelly.width - jelly.inset - jelly.hx, jelly.width - 2 * jelly.inset, jelly.ax))
    readonly property real gh: Math.max(0, Kit.mix(jelly.height - 2 * jelly.inset, jelly.height - jelly.gy - jelly.inset, jelly.ax))
    readonly property real corner: Math.min(jelly.gw / 2, jelly.gh / 2, Math.max(0, jelly.radius - jelly.inset))
    readonly property bool shown: jelly.active && jelly.carded && jelly.gauged && jelly.tileOf > 0 && jelly.gw > 1 && jelly.gh > 1

    function at(x, y) {
        return Qt.point(jelly.side < 0 ? x : jelly.width - x, y);
    }
    // Filling from the icon's side and from the bottom, mixed point by point, then held inside the rounded room.
    readonly property var outline: {
        if (!jelly.shown)
            return [];
        const n = 18, pts = [];
        const x0 = jelly.gx, y0 = jelly.gy, w = jelly.gw, hh = jelly.gh, lv = Kit.unit(jelly.lev);
        const wave = i => Kit.wave(2 * i / n, jelly.slosh, jelly.phase) * Math.sin(Math.PI * i / n); // A1
        const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
        // A point held to the rounded room.
        const room = (px, py) => {
            const r = jelly.corner;
            let x = clamp(px, x0, x0 + w), y = clamp(py, y0, y0 + hh);
            const cx = clamp(x, x0 + r, x0 + w - r), cy = clamp(y, y0 + r, y0 + hh - r);
            const ex = x - cx, ey = y - cy, d = Math.sqrt(ex * ex + ey * ey);
            if (d > r && d > 0) {
                x = cx + ex / d * r;
                y = cy + ey / d * r;
            }
            return jelly.at(x, y);
        };
        // The front turns about the liquid's corner: its top end goes to the icon's side (else, midway, it lies across that corner).
        const front = [];
        for (let i = 0; i <= n; i++) {
            const y = y0 + hh * i / n, x = x0 + w * i / n;
            front.push(Qt.point(Kit.mix(x0 + w * lv + wave(i), x, jelly.ax), Kit.mix(y, y0 + hh * (1 - lv) + wave(i), jelly.ax)));
        }
        // Midway the front is shorter than the room: its ends run on along it to the walls.
        const tx = front[n].x - front[0].x, ty = front[n].y - front[0].y, tn = Math.max(1e-6, Math.sqrt(tx * tx + ty * ty));
        front.unshift(Qt.point(front[0].x - tx / tn * 99, front[0].y - ty / tn * 99));
        front.push(Qt.point(front[n + 1].x + tx / tn * 99, front[n + 1].y + ty / tn * 99));
        // The back: the front pushed far into the liquid (toward the icon's side, turning to the bottom), held to the walls.
        const dx = -99 * Math.cos(jelly.ax * Math.PI / 2), dy = 99 * Math.sin(jelly.ax * Math.PI / 2);
        for (const p of front)
            pts.push(room(p.x, p.y));
        for (let i = front.length - 1; i >= 0; i--)
            pts.push(room(front[i].x + dx, front[i].y + dy));
        return pts;
    }

    Rectangle {
        x: jelly.side < 0 ? jelly.gx : jelly.width - jelly.gx - jelly.gw
        y: jelly.gy
        z: 0.5
        width: jelly.gw
        height: jelly.gh
        radius: jelly.corner
        visible: jelly.shown
        opacity: liquidShape.opacity
        color: jelly.trackColor
    }

    Shape {
        id: liquidShape

        anchors.fill: parent
        z: 0.5
        visible: jelly.shown
        opacity: jelly.content * (jelly.pillLiquid ? 1 : jelly.tileOf)
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: jelly.liquidColor
            strokeColor: "transparent"
            strokeWidth: 0

            PathPolyline {
                path: jelly.outline
            }
        }
    }
}
