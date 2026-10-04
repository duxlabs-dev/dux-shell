pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common

// Drawing surface sized to the content in content units. Hosts supply the content and handle export.
Item {
    id: root

    property string tool: "pen"
    property color strokeColor: Theme.error
    property int sizeLevel: 1
    // On-screen pixels per content unit, so sizes and hit slop stay constant on screen.
    property real viewScale: 1
    // Presses outside this rect fall through to whatever is beneath; null accepts everywhere.
    property var drawArea: null

    // Undoable state, replaced as a whole so undo/redo are snapshot swaps.
    property var shapes: []
    property var crop: null
    property var undoStack: []
    property var redoStack: []
    property int revision: 0
    property int savedRevision: 0

    property var draft: null
    property var textAnchor: null

    readonly property bool dirty: revision !== savedRevision
    readonly property bool editingText: textAnchor !== null
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    readonly property bool drawingTool: ["pen", "highlighter", "arrow", "rect", "text", "eraser"].includes(tool)
    readonly property real strokeWidth: [2, 4, 8][sizeLevel] / viewScale
    readonly property real fontSize: [14, 20, 32][sizeLevel] / viewScale

    function reset() {
        textAnchor = null;
        draft = null;
        shapes = [];
        crop = null;
        undoStack = [];
        redoStack = [];
        revision = 0;
        savedRevision = 0;
    }

    function commit(nextShapes, nextCrop) {
        undoStack = undoStack.concat([{
                shapes: shapes,
                crop: crop
            }]);
        redoStack = [];
        shapes = nextShapes;
        crop = nextCrop;
        revision++;
    }

    function undo() {
        commitText();
        if (!canUndo)
            return;
        redoStack = redoStack.concat([{
                shapes: shapes,
                crop: crop
            }]);
        const prev = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        shapes = prev.shapes;
        crop = prev.crop;
        revision++;
    }

    function redo() {
        if (!canRedo)
            return;
        undoStack = undoStack.concat([{
                shapes: shapes,
                crop: crop
            }]);
        const next = redoStack[redoStack.length - 1];
        redoStack = redoStack.slice(0, -1);
        shapes = next.shapes;
        crop = next.crop;
        revision++;
    }

    function markSaved() {
        savedRevision = revision;
    }

    function commitText() {
        if (!textAnchor)
            return;
        const text = textInput.text;
        const anchor = textAnchor;
        textAnchor = null;
        if (text.trim() === "")
            return;
        commit(shapes.concat([{
                type: "text",
                color: root.strokeColor.toString(),
                size: fontSize,
                text: text,
                x: anchor.x,
                y: anchor.y,
                w: textInput.contentWidth,
                h: textInput.contentHeight
            }]), crop);
    }

    function distanceToSegment(p, a, b) {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len2 = dx * dx + dy * dy;
        const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
        return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
    }

    function hits(shape, p, tolerance) {
        if (shape.type === "text")
            return p.x >= shape.x - tolerance && p.x <= shape.x + shape.w + tolerance && p.y >= shape.y - tolerance && p.y <= shape.y + shape.h + tolerance;
        const pts = outline(shape);
        const reach = shape.width / 2 + tolerance;
        for (let i = 1; i < pts.length; i++) {
            if (distanceToSegment(p, pts[i - 1], pts[i]) <= reach)
                return true;
        }
        return pts.length === 1 && Math.hypot(p.x - pts[0].x, p.y - pts[0].y) <= reach;
    }

    function eraseAt(p) {
        const tolerance = 6 / viewScale;
        for (let i = shapes.length - 1; i >= 0; i--) {
            if (!hits(shapes[i], p, tolerance))
                continue;
            commit(shapes.slice(0, i).concat(shapes.slice(i + 1)), crop);
            return;
        }
    }

    function outline(shape) {
        const pts = shape.points;
        if (shape.type === "rect") {
            const a = pts[0];
            const b = pts[pts.length - 1];
            return [a, Qt.point(b.x, a.y), b, Qt.point(a.x, b.y), a];
        }
        if (shape.type === "arrow") {
            const a = pts[0];
            const b = pts[pts.length - 1];
            const dx = b.x - a.x;
            const dy = b.y - a.y;
            const len = Math.hypot(dx, dy);
            if (len <= 0)
                return [a, b];
            const spread = Math.PI / 7;
            const headLen = Math.max(15 / root.viewScale, shape.width * 4);
            const offset = headLen * Math.cos(spread);
            const shaftLen = Math.max(0, len - offset);
            const angle = Math.atan2(dy, dx);
            const endX = a.x + shaftLen * Math.cos(angle);
            const endY = a.y + shaftLen * Math.sin(angle);
            return [a, Qt.point(endX, endY)];
        }
        return pts;
    }



    function arrowHead(shape) {
        const a = shape.points[0];
        const b = shape.points[shape.points.length - 1];
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        if (Math.hypot(dx, dy) <= 0)
            return [];
        const angle = Math.atan2(dy, dx);
        const headLength = Math.max(15 / root.viewScale, shape.width * 4);
        const spreadAngle = Math.PI / 7;
        const strokeWidth = shape.width;

        const tipRadius = Math.max(1.5, Math.min(strokeWidth * 0.5, headLength * 0.15));
        const sinHalf = Math.sin(spreadAngle);
        const tipApexInset = tipRadius * (1 / sinHalf - 1);
        const effectiveTipX = b.x + tipApexInset * Math.cos(angle);
        const effectiveTipY = b.y + tipApexInset * Math.sin(angle);

        const v1 = Qt.point(effectiveTipX, effectiveTipY);
        const v2 = Qt.point(b.x - headLength * Math.cos(angle - spreadAngle), b.y - headLength * Math.sin(angle - spreadAngle));
        const v3 = Qt.point(b.x - headLength * Math.cos(angle + spreadAngle), b.y - headLength * Math.sin(angle + spreadAngle));

        return [v1, v2, v3, v1];
    }

    function snapPointToAngle(point, fixed) {
        const dx = point.x - fixed.x;
        const dy = point.y - fixed.y;
        const length = Math.hypot(dx, dy);
        if (length === 0)
            return point;
        const snapStep = Math.PI / 12; // 15 degrees
        const angle = Math.atan2(dy, dx);
        const snapped = Math.round(angle / snapStep) * snapStep;
        return Qt.point(fixed.x + length * Math.cos(snapped), fixed.y + length * Math.sin(snapped));
    }

    function constrainSquarePoint(start, point) {
        if (!start || !point)
            return point || Qt.point(0, 0);
        const dx = point.x - start.x;
        const dy = point.y - start.y;
        const size = Math.max(Math.abs(dx), Math.abs(dy));
        const sx = dx < 0 ? -1 : 1;
        const sy = dy < 0 ? -1 : 1;
        return Qt.point(start.x + sx * size, start.y + sy * size);
    }

    function normalizedRect(a, b) {
        const x1 = Math.max(0, Math.min(a.x, b.x));
        const y1 = Math.max(0, Math.min(a.y, b.y));
        const x2 = Math.min(width, Math.max(a.x, b.x));
        const y2 = Math.min(height, Math.max(a.y, b.y));
        return Qt.rect(x1, y1, Math.max(0, x2 - x1), Math.max(0, y2 - y1));
    }

    function contains(area, p) {
        return !area || (p.x >= area.x && p.x <= area.x + area.width && p.y >= area.y && p.y <= area.y + area.height);
    }

    component Annotation: Item {
        id: annotation

        required property var shape
        readonly property bool isText: shape.type === "text"
        readonly property bool isRect: shape.type === "rect"
        readonly property var points: isText || isRect || !shape.points?.length ? [] : root.outline(shape)
        readonly property real headRounding: Math.max(2, (shape.width ?? 1) * 0.6)

        Rectangle {
            visible: annotation.isRect && (annotation.shape.points?.length ?? 0) >= 2
            x: Math.min(annotation.shape.points?.[0]?.x ?? 0, annotation.shape.points?.[annotation.shape.points?.length - 1]?.x ?? 0)
            y: Math.min(annotation.shape.points?.[0]?.y ?? 0, annotation.shape.points?.[annotation.shape.points?.length - 1]?.y ?? 0)
            width: Math.abs((annotation.shape.points?.[annotation.shape.points?.length - 1]?.x ?? 0) - (annotation.shape.points?.[0]?.x ?? 0))
            height: Math.abs((annotation.shape.points?.[annotation.shape.points?.length - 1]?.y ?? 0) - (annotation.shape.points?.[0]?.y ?? 0))
            color: "transparent"
            border.color: annotation.shape.color ?? "transparent"
            border.width: annotation.shape.width ?? 1
            radius: Math.min((Theme.cornerRadius + (annotation.shape.width ?? 1) / 2) / root.viewScale, Math.min(width, height) / 2)
        }

        Shape {
            anchors.fill: parent
            visible: !annotation.isText && !annotation.isRect
            preferredRendererType: Shape.CurveRenderer
            opacity: annotation.shape.type === "highlighter" ? 0.4 : 1

            ShapePath {
                strokeColor: annotation.shape.color ?? "transparent"
                strokeWidth: annotation.shape.width ?? 1
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: annotation.points
                }
            }

            ShapePath {
                strokeColor: annotation.shape.type === "arrow" ? (annotation.shape.color ?? "transparent") : "transparent"
                strokeWidth: annotation.headRounding
                fillColor: annotation.shape.type === "arrow" ? (annotation.shape.color ?? "transparent") : "transparent"
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap

                PathPolyline {
                    path: annotation.shape.type === "arrow" ? root.arrowHead(annotation.shape) : []
                }
            }
        }

        Text {
            visible: annotation.isText
            x: annotation.shape.x ?? 0
            y: annotation.shape.y ?? 0
            text: annotation.shape.text ?? ""
            color: annotation.shape.color ?? "transparent"
            font.family: Theme.fontFamily
            font.pixelSize: annotation.shape.size ?? 1
            font.weight: Font.Medium
        }
    }

    Repeater {
        model: root.shapes

        delegate: Annotation {
            required property var modelData
            anchors.fill: parent
            shape: modelData
        }
    }

    Loader {
        anchors.fill: parent
        active: root.draft !== null
        sourceComponent: Annotation {
            shape: root.draft ?? {}
        }
    }

    TextInput {
        id: textInput

        visible: root.editingText
        x: root.textAnchor?.x ?? 0
        y: root.textAnchor?.y ?? 0
        color: root.strokeColor
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        font.weight: Font.Medium
        cursorDelegate: Rectangle {
            width: Math.max(1, 2 / root.viewScale)
            color: root.strokeColor
        }

        Keys.onReturnPressed: root.commitText()
        Keys.onEnterPressed: root.commitText()
        Keys.onEscapePressed: {
            textInput.text = "";
            root.textAnchor = null;
        }
    }

    MouseArea {
        property point start

        anchors.fill: parent
        enabled: root.drawingTool
        cursorShape: root.tool === "text" ? Qt.IBeamCursor : (root.tool === "eraser" ? Qt.PointingHandCursor : Qt.CrossCursor)

        onPressed: mouse => {
            const p = Qt.point(mouse.x, mouse.y);
            if (!root.contains(root.drawArea, p)) {
                mouse.accepted = false;
                return;
            }
            root.commitText();
            start = p;
            switch (root.tool) {
            case "text":
                textInput.text = "";
                root.textAnchor = Qt.point(p.x, p.y - root.fontSize / 2);
                textInput.forceActiveFocus();
                return;
            case "eraser":
                root.eraseAt(p);
                return;
            }
            root.draft = {
                type: root.tool,
                color: root.strokeColor.toString(),
                width: root.tool === "highlighter" ? root.strokeWidth * 4 : root.strokeWidth,
                points: [p]
            };
        }

        onPositionChanged: mouse => {
            let p = Qt.point(mouse.x, mouse.y);
            if (root.tool === "eraser") {
                root.eraseAt(p);
                return;
            }
            if (!root.draft)
                return;
            const pts = root.draft.points;
            const first = pts[0];
            const isShift = mouse.modifiers & Qt.ShiftModifier;

            if (root.draft.type === "pen") {
                if (isShift) {
                    root.draft = Object.assign({}, root.draft, {
                        points: [first, root.snapPointToAngle(p, first)]
                    });
                    return;
                }
                const last = pts[pts.length - 1];
                if (Math.hypot(p.x - last.x, p.y - last.y) < 1.5 / root.viewScale)
                    return;
                root.draft = Object.assign({}, root.draft, {
                    points: pts.concat([p])
                });
                return;
            }

            if (isShift) {
                if (root.draft.type === "arrow" || root.draft.type === "highlighter") {
                    p = root.snapPointToAngle(p, first);
                } else if (root.draft.type === "rect") {
                    p = root.constrainSquarePoint(first, p);
                }
            }

            root.draft = Object.assign({}, root.draft, {
                points: [first, p]
            });
        }

        onReleased: mouse => {
            if (!root.draft)
                return;
            let shape = root.draft;
            root.draft = null;
            root.commit(root.shapes.concat([shape]), root.crop);
        }
    }
}
