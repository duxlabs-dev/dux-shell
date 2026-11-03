.pragma library

function borderPath(g) {
    const f = canonical(g);
    if (!f)
        return "";
    return serialize(g.alongWings ? alongOps(f) : crossOps(f), g.position, g.width, g.height);
}

function canonical(g) {
    const body = g.body;
    const c = g.corners;
    switch (g.position) {
    case "top":
        return frame(g, body.x, body.x + body.width, body.height, c.topLeft, c.topRight, c.bottomLeft, c.bottomRight);
    case "bottom":
        return frame(g, body.x, body.x + body.width, body.height, c.bottomLeft, c.bottomRight, c.topLeft, c.topRight);
    case "left":
        return frame(g, body.y, body.y + body.height, body.width, c.topLeft, c.bottomLeft, c.topRight, c.bottomRight);
    case "right":
        return frame(g, body.y, body.y + body.height, body.width, c.topRight, c.bottomRight, c.topLeft, c.bottomLeft);
    default:
        return null;
    }
}

function frame(g, start, end, thickness, attachedStart, attachedEnd, farStart, farEnd) {
    if (end - start <= 0 || thickness <= 0)
        return null;
    const inset = g.inset;
    const shrink = radius => Math.max(0, radius - inset);
    const sides = g.alongWings || !g.open;
    const cover = reach => {
        if (g.alongWings)
            return 0;
        return Math.max(0, reach ?? 0);
    };
    return {
        start,
        end,
        thickness,
        inset,
        wing: Math.max(0, g.wing),
        wingCross: Math.max(0, g.wingCross ?? g.wing),
        attachedStart: shrink(attachedStart),
        attachedEnd: shrink(attachedEnd),
        farStart: shrink(farStart),
        farEnd: shrink(farEnd),
        attachedVisible: !g.open,
        startSide: sides && !(g.seamStart ?? false),
        endSide: sides && !(g.seamEnd ?? false),
        coverStart: cover(g.coverStart),
        coverEnd: cover(g.coverEnd),
        coverStartWing: Math.max(0, g.coverStartWing ?? 0),
        coverEndWing: Math.max(0, g.coverEndWing ?? 0)
    };
}

function crossOps(f) {
    const p = pen();
    const i = f.inset;
    const r = f.wing;
    const T = f.thickness;
    // the offset of a concave arc meets the offset side line 2*sqrt(r*i) short of the wing tip
    const tail = T + r - 2 * Math.sqrt(r * i);
    const farEdge = T - i;
    const endSideBottom = endSideStop(f, tail);
    const farEdgeStart = farEdgeStop(f);
    if (f.attachedVisible) {
        if (f.startSide)
            p.at(f.start + i + f.attachedStart, i);
        else
            p.at(f.start + i, i + f.attachedStart).corner(f.attachedStart, f.start + i + f.attachedStart, i);
        p.at(f.end - i - f.attachedEnd, i).corner(f.attachedEnd, f.end - i, i + f.attachedEnd);
        if (f.endSide)
            p.at(f.end - i, endSideBottom);
        else
            p.lift();
    }
    if (f.coverEnd > 0) {
        // carry the stroke onto the tucked neighbour's wing circle so both windows paint one band
        p.lift();
        if (f.coverEndWing > 0)
            p.at(f.end - f.coverEnd + f.coverEndWing + i, T + f.coverEndWing).arc(f.coverEndWing + i, 0, f.end - f.coverEnd, T - i);
        else
            p.at(f.end - f.coverEnd, T - i);
    } else if (r > 0) {
        if (!f.endSide)
            p.at(f.end + i, T + r);
        p.arc(r + i, 0, f.end - r, T - i);
    } else {
        if (!f.endSide)
            p.at(f.end - i, T - i - f.farEnd);
        p.corner(f.farEnd, f.end - i - f.farEnd, T - i);
    }
    p.at(farEdgeStart, farEdge);
    if (f.coverStart > 0) {
        if (f.coverStartWing > 0)
            p.arc(f.coverStartWing + i, 0, f.start + f.coverStart - f.coverStartWing - i, T + f.coverStartWing);
        p.lift();
        if (f.startSide)
            p.at(f.start + i, T - i);
    } else if (r > 0) {
        if (f.startSide)
            p.arc(r + i, 0, f.start + i, tail);
        else
            p.arc(r + i, 0, f.start - i, T + r).lift();
    } else {
        p.corner(f.farStart, f.start + i, T - i - f.farStart);
        if (!f.startSide)
            p.lift();
    }
    if (!f.startSide || !f.attachedVisible)
        return p.ops;
    p.at(f.start + i, i + f.attachedStart).corner(f.attachedStart, f.start + i + f.attachedStart, i).seal();
    return p.ops;
}

function endSideStop(f, tail) {
    const farEdge = f.thickness - f.inset;
    if (f.coverEnd > 0)
        return farEdge;
    if (f.wing > 0)
        return tail;
    return farEdge - f.farEnd;
}

function farEdgeStop(f) {
    if (f.coverStart > 0)
        return f.start + f.coverStart;
    if (f.wing > 0)
        return f.start + f.wing;
    return f.start + f.inset + f.farStart;
}

function alongOps(f) {
    const p = pen();
    const i = f.inset;
    const r = f.wing;
    const rc = f.wingCross;
    const T = f.thickness;
    // the offset of a wing arc meets the offset attached edge 2*sqrt(rc*i) short of the tip, stretched by the along/cross ratio
    const reach = rc + i > 0 ? (r + i) * 2 * Math.sqrt(rc * i) / (rc + i) : 0;
    const startTip = f.start - r;
    const endTip = f.end + r;
    if (r > 0) {
        if (f.attachedVisible)
            p.at(startTip + reach, i).at(endTip - reach, i);
        else
            p.at(endTip, -i);
        p.arc(r + i, 0, f.end - i, rc, rc + i);
    } else {
        if (f.attachedVisible)
            p.at(f.start + i + f.attachedStart, i);
        p.at(f.end - i - f.attachedEnd, i).corner(f.attachedEnd, f.end - i, i + f.attachedEnd);
    }
    p.at(f.end - i, T - i - f.farEnd).corner(f.farEnd, f.end - i - f.farEnd, T - i);
    p.at(f.start + i + f.farStart, T - i).corner(f.farStart, f.start + i, T - i - f.farStart);
    if (r > 0) {
        p.at(f.start + i, rc);
        if (f.attachedVisible)
            p.arc(r + i, 0, startTip + reach, i, rc + i);
        else
            p.arc(r + i, 0, startTip, -i, rc + i);
    } else {
        p.at(f.start + i, i + f.attachedStart).corner(f.attachedStart, f.start + i + f.attachedStart, i);
    }
    if (f.attachedVisible)
        p.seal();
    return p.ops;
}

function pen() {
    const self = {
        ops: [],
        down: false,
        lifted: false,
        at(a, c) {
            self.ops.push({
                op: self.down ? "L" : "M",
                a,
                c
            });
            self.down = true;
            return self;
        },
        arc(radius, sweep, a, c, crossRadius) {
            self.ops.push({
                op: "A",
                radius,
                crossRadius: crossRadius ?? radius,
                sweep,
                a,
                c
            });
            return self;
        },
        corner(radius, a, c) {
            return radius > 0 ? self.arc(radius, 1, a, c) : self;
        },
        lift() {
            self.down = false;
            self.lifted = true;
            return self;
        },
        seal() {
            if (!self.lifted)
                self.ops.push({
                    op: "Z"
                });
            self.down = false;
            return self;
        }
    };
    return self;
}

function serialize(ops, position, width, height) {
    const map = mapper(position, width, height);
    const flipSweep = position === "bottom" || position === "left";
    const vertical = position === "left" || position === "right";
    return ops.map(op => {
        if (op.op === "Z")
            return "Z";
        const point = map(op.a, op.c);
        const target = `${num(point.x)} ${num(point.y)}`;
        if (op.op !== "A")
            return `${op.op} ${target}`;
        const sweep = flipSweep ? 1 - op.sweep : op.sweep;
        const rx = vertical ? op.crossRadius : op.radius;
        const ry = vertical ? op.radius : op.crossRadius;
        return `A ${num(rx)} ${num(ry)} 0 0 ${sweep} ${target}`;
    }).join(" ");
}

function mapper(position, width, height) {
    switch (position) {
    case "bottom":
        return (a, c) => ({
                    x: a,
                    y: height - c
                });
    case "left":
        return (a, c) => ({
                    x: c,
                    y: a
                });
    case "right":
        return (a, c) => ({
                    x: width - c,
                    y: a
                });
    default:
        return (a, c) => ({
                    x: a,
                    y: c
                });
    }
}

function num(value) {
    return String(Math.round(value * 100) / 100);
}
