pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Common
import "MarkupHelpers.js" as Helpers

// Drawing surface sized to the content in content units. Hosts supply the content and handle export.
Item {
    id: root

    property string tool: "pen"
    property color strokeColor: Theme.error
    property real strokeSize: 4
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
    property int selectedIndex: -1

    readonly property bool dirty: revision !== savedRevision
    readonly property bool editingText: textAnchor !== null
    readonly property bool canUndo: undoStack.length > 0
    readonly property bool canRedo: redoStack.length > 0
    readonly property bool drawingTool: ["select", "pen", "highlighter", "arrow", "rect", "text", "eraser"].includes(tool)
    readonly property real strokeWidth: strokeSize / viewScale
    readonly property real fontSize: Math.max(12, strokeSize * 4) / viewScale
    readonly property var selectedShape: selectedIndex >= 0 && selectedIndex < shapes.length ? shapes[selectedIndex] : null
    readonly property var selectionBox: shapeBounds(selectedShape)

    function changeStrokeSize(delta) {
        strokeSize = Math.max(1, Math.min(32, strokeSize + delta));
    }

    property bool syncingSelection: false

    onStrokeSizeChanged: {
        if (syncingSelection)
            return;
        if (draft) {
            draft = Object.assign({}, draft, {
                width: draft.type === "highlighter" ? strokeWidth * 4 : strokeWidth
            });
        }
        if (tool === "select" && selectedIndex >= 0 && selectedIndex < shapes.length) {
            const shape = shapes[selectedIndex];
            const targetWidth = shape.type === "highlighter" ? strokeWidth * 4 : strokeWidth;
            if (shape.width !== targetWidth) {
                const updated = Object.assign({}, shape, {
                    width: targetWidth
                });
                const newShapes = shapes.slice();
                newShapes[selectedIndex] = updated;
                shapes = newShapes;
            }
        }
    }

    onStrokeColorChanged: {
        if (syncingSelection)
            return;
        if (tool === "select" && selectedIndex >= 0 && selectedIndex < shapes.length) {
            const shape = shapes[selectedIndex];
            const updated = Object.assign({}, shape, {
                color: strokeColor.toString()
            });
            const newShapes = shapes.slice();
            newShapes[selectedIndex] = updated;
            commit(newShapes, crop);
        }
    }

    onToolChanged: {
        if (tool === "select") {
            selectedIndex = shapes.length > 0 ? shapes.length - 1 : -1;
        } else {
            selectedIndex = -1;
        }
    }

    onSelectedIndexChanged: {
        if (tool === "select" && selectedIndex >= 0 && selectedIndex < shapes.length) {
            const shape = shapes[selectedIndex];
            syncingSelection = true;
            if (shape.width !== undefined) {
                const baseWidth = shape.type === "highlighter" ? shape.width / 4 : shape.width;
                strokeSize = Math.max(1, Math.min(32, baseWidth * viewScale));
            }
            if (shape.color) {
                strokeColor = shape.color;
            }
            syncingSelection = false;
        }
    }

    function reset() {
        tool = "pen";
        textAnchor = null;
        draft = null;
        selectedIndex = -1;
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
        return Helpers.distanceToSegment(p, a, b);
    }

    function hits(shape, p, tolerance) {
        return Helpers.hits(shape, p, tolerance, viewScale);
    }

    function shapeBounds(shape) {
        const b = Helpers.shapeBounds(shape, viewScale, fontSize);
        return b ? Qt.rect(b.x, b.y, b.width, b.height) : null;
    }

    function translateShape(shape, dx, dy) {
        return Helpers.translateShape(shape, dx, dy);
    }

    function resizeShape(shape, origBox, newBox) {
        return Helpers.resizeShape(shape, origBox, newBox, fontSize);
    }

    function hitIndexAt(p) {
        const tolerance = 6 / viewScale;
        for (let i = shapes.length - 1; i >= 0; i--) {
            if (hits(shapes[i], p, tolerance))
                return i;
        }
        return -1;
    }

    function eraseAt(p) {
        const i = hitIndexAt(p);
        if (i !== -1)
            commit(shapes.slice(0, i).concat(shapes.slice(i + 1)), crop);
    }

    function outline(shape) {
        const pts = Helpers.outline(shape, viewScale);
        return pts.map(p => Qt.point(p.x, p.y));
    }

    function arrowHead(shape) {
        const pts = Helpers.arrowHead(shape, viewScale);
        return pts.map(p => Qt.point(p.x, p.y));
    }

    function snapPointToAngle(point, fixed) {
        const pt = Helpers.snapPointToAngle(point, fixed);
        return Qt.point(pt.x, pt.y);
    }

    function constrainSquarePoint(start, point) {
        const pt = Helpers.constrainSquarePoint(start, point);
        return Qt.point(pt.x, pt.y);
    }

    function normalizedRect(a, b) {
        const r = Helpers.normalizedRect(a, b, width, height);
        return Qt.rect(r.x, r.y, r.width, r.height);
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

    Rectangle {
        id: selectionIndicator

        readonly property var box: root.selectionBox

        visible: box !== null && root.tool === "select"
        x: box?.x ?? 0
        y: box?.y ?? 0
        width: box?.width ?? 0
        height: box?.height ?? 0
        color: "transparent"
        border.color: Theme.primary
        border.width: 1.5 / root.viewScale
        radius: 3 / root.viewScale
        z: 20

        // 4 corner resize handles
        Repeater {
            model: [Qt.point(0, 0), Qt.point(1, 0), Qt.point(0, 1), Qt.point(1, 1)]
            delegate: Rectangle {
                id: cornerHandle
                required property point modelData

                x: modelData.x * parent.width - width / 2
                y: modelData.y * parent.height - height / 2
                width: 10 / root.viewScale
                height: 10 / root.viewScale
                radius: width / 2
                color: Theme.primary
                border.color: Theme.onPrimary
                border.width: 1.5 / root.viewScale

                MouseArea {
                    property var startShape: null
                    property var startBox: null

                    anchors.fill: parent
                    anchors.margins: -4 / root.viewScale
                    cursorShape: (cornerHandle.modelData.x === cornerHandle.modelData.y) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                    onPressed: mouse => {
                        mouse.accepted = true;
                        if (root.selectedIndex >= 0 && root.selectedIndex < root.shapes.length) {
                            startShape = JSON.parse(JSON.stringify(root.shapes[root.selectedIndex]));
                            startBox = root.shapeBounds(startShape);
                        }
                    }

                    onPositionChanged: mouse => {
                        if (!startShape || !startBox)
                            return;
                        const p = mapToItem(root, mouse.x, mouse.y);
                        const f = cornerHandle.modelData;
                        const left = f.x === 0 ? p.x : startBox.x;
                        const right = f.x === 1 ? p.x : startBox.x + startBox.width;
                        const top = f.y === 0 ? p.y : startBox.y;
                        const bottom = f.y === 1 ? p.y : startBox.y + startBox.height;
                        const newBox = root.normalizedRect(Qt.point(left, top), Qt.point(right, bottom));

                        if (newBox.width >= 4 && newBox.height >= 4) {
                            const resized = root.resizeShape(startShape, startBox, newBox);
                            const newShapes = root.shapes.slice();
                            newShapes[root.selectedIndex] = resized;
                            root.shapes = newShapes;
                        }
                    }

                    onReleased: {
                        if (startShape && startBox) {
                            const curShapes = root.shapes.slice();
                            const beforeShapes = curShapes.slice();
                            beforeShapes[root.selectedIndex] = startShape;
                            root.undoStack = root.undoStack.concat([{
                                shapes: beforeShapes,
                                crop: root.crop
                            }]);
                            root.redoStack = [];
                            root.revision++;
                        }
                        startShape = null;
                        startBox = null;
                    }
                }
            }
        }
    }

    MouseArea {
        property point start
        property var dragStartShape: null
        property bool draggingShape: false

        anchors.fill: parent
        enabled: root.drawingTool
        hoverEnabled: true

        onWheel: wheel => {
            const p = Qt.point(wheel.x, wheel.y);
            if (!root.contains(root.drawArea, p)) {
                wheel.accepted = false;
                return;
            }
            if (wheel.angleDelta.y === 0)
                return;
            const step = wheel.angleDelta.y > 0 ? 1 : -1;
            root.changeStrokeSize(step);
            wheel.accepted = true;
        }

        cursorShape: {
            if (root.tool === "text")
                return Qt.IBeamCursor;
            if (root.tool === "eraser")
                return Qt.PointingHandCursor;
            if (root.tool === "select")
                return draggingShape ? Qt.ClosedHandCursor : (root.selectedIndex !== -1 ? Qt.OpenHandCursor : Qt.ArrowCursor);
            return Qt.CrossCursor;
        }

        onPressed: mouse => {
            const p = Qt.point(mouse.x, mouse.y);
            if (!root.contains(root.drawArea, p)) {
                mouse.accepted = false;
                return;
            }
            root.commitText();
            start = p;
            if (root.tool === "select") {
                // If clicked on currently selected shape or its bounding box
                if (root.selectedIndex !== -1) {
                    const selBox = root.selectionBox;
                    const onBox = selBox && p.x >= selBox.x && p.x <= selBox.x + selBox.width && p.y >= selBox.y && p.y <= selBox.y + selBox.height;
                    const hitIdx = root.hitIndexAt(p);
                    if (hitIdx === root.selectedIndex || (hitIdx === -1 && onBox)) {
                        draggingShape = true;
                        dragStartShape = JSON.parse(JSON.stringify(root.shapes[root.selectedIndex]));
                        return;
                    }
                }
                const hit = root.hitIndexAt(p);
                root.selectedIndex = hit;
                if (hit !== -1) {
                    draggingShape = true;
                    dragStartShape = JSON.parse(JSON.stringify(root.shapes[hit]));
                }
                return;
            }
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
            if (root.tool === "select") {
                if (draggingShape && dragStartShape && root.selectedIndex !== -1) {
                    const dx = p.x - start.x;
                    const dy = p.y - start.y;
                    const moved = root.translateShape(dragStartShape, dx, dy);
                    const newShapes = root.shapes.slice();
                    newShapes[root.selectedIndex] = moved;
                    root.shapes = newShapes;
                }
                return;
            }
            if (root.tool === "eraser") {
                root.eraseAt(p);
                return;
            }
            if (!root.draft)
                return;
            const pts = root.draft.points;
            const first = pts[0];
            const isShift = mouse.modifiers & Qt.ShiftModifier;

            const currentWidth = root.draft.type === "highlighter" ? root.strokeWidth * 4 : root.strokeWidth;
            if (root.draft.type === "pen") {
                if (isShift) {
                    root.draft = Object.assign({}, root.draft, {
                        width: currentWidth,
                        points: [first, root.snapPointToAngle(p, first)]
                    });
                    return;
                }
                const last = pts[pts.length - 1];
                if (Math.hypot(p.x - last.x, p.y - last.y) < 1.5 / root.viewScale) {
                    if (root.draft.width !== currentWidth) {
                        root.draft = Object.assign({}, root.draft, {
                            width: currentWidth
                        });
                    }
                    return;
                }
                root.draft = Object.assign({}, root.draft, {
                    width: currentWidth,
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
                width: currentWidth,
                points: [first, p]
            });
        }

        onReleased: mouse => {
            if (root.tool === "select") {
                if (draggingShape) {
                    draggingShape = false;
                    const p = Qt.point(mouse.x, mouse.y);
                    if (Math.hypot(p.x - start.x, p.y - start.y) > 1) {
                        const curShapes = root.shapes.slice();
                        // Rollback state in undoStack by committing the change
                        const beforeShapes = curShapes.slice();
                        beforeShapes[root.selectedIndex] = dragStartShape;
                        root.undoStack = root.undoStack.concat([{
                            shapes: beforeShapes,
                            crop: root.crop
                        }]);
                        root.redoStack = [];
                        root.revision++;
                    }
                    dragStartShape = null;
                }
                return;
            }
            if (!root.draft)
                return;
            let shape = root.draft;
            root.draft = null;
            root.commit(root.shapes.concat([shape]), root.crop);
        }
    }
}
