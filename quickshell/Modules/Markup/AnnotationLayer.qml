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
                color: strokeColor,
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
        if (shape.type !== "rect")
            return shape.type === "arrow" ? [pts[0], pts[pts.length - 1]] : pts;
        const a = pts[0];
        const b = pts[pts.length - 1];
        return [a, Qt.point(b.x, a.y), b, Qt.point(a.x, b.y), a];
    }

    function arrowHead(shape) {
        const a = shape.points[0];
        const b = shape.points[shape.points.length - 1];
        const angle = Math.atan2(b.y - a.y, b.x - a.x);
        const len = shape.width * 4;
        const spread = Math.PI / 7;
        return [Qt.point(b.x - len * Math.cos(angle - spread), b.y - len * Math.sin(angle - spread)), b, Qt.point(b.x - len * Math.cos(angle + spread), b.y - len * Math.sin(angle + spread))];
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
        readonly property var points: isText || !shape.points?.length ? [] : root.outline(shape)

        Shape {
            anchors.fill: parent
            visible: !annotation.isText
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
                strokeColor: annotation.shape.type === "arrow" ? annotation.shape.color : "transparent"
                strokeWidth: annotation.shape.width ?? 1
                fillColor: strokeColor
                joinStyle: ShapePath.RoundJoin

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
                color: root.strokeColor,
                width: root.tool === "highlighter" ? root.strokeWidth * 4 : root.strokeWidth,
                points: [p]
            };
        }

        onPositionChanged: mouse => {
            const p = Qt.point(mouse.x, mouse.y);
            if (root.tool === "eraser") {
                root.eraseAt(p);
                return;
            }
            if (!root.draft)
                return;
            const pts = root.draft.points;
            const last = pts[pts.length - 1];
            const freehand = root.draft.type === "pen" || root.draft.type === "highlighter";
            if (freehand && Math.hypot(p.x - last.x, p.y - last.y) < 1.5 / root.viewScale)
                return;
            root.draft = Object.assign({}, root.draft, {
                points: freehand ? pts.concat([p]) : [pts[0], p]
            });
        }

        onReleased: {
            if (!root.draft)
                return;
            const shape = root.draft;
            root.draft = null;
            root.commit(root.shapes.concat([shape]), root.crop);
        }
    }
}
