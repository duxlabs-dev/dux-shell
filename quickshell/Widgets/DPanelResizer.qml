import QtQuick
import qs.Common
import "../Common/GridLayout.js" as GridUtils

QtObject {
    id: root

    required property var popout
    property Item pointerItem: null
    property real pointerInset: 0
    property real gutter: 0
    property real stepWidth: 0
    property var widthFor: step => 0
    property var currentStep: () => 0
    property var currentRows: () => 0
    property int minStep: 0
    property int maxStep: 0
    property real rowUnit: 0
    property var rowEdgeFor: null
    property int minRows: 0
    property int maxRows: 0
    readonly property bool resizing: _drag !== null
    property var _drag: null

    signal preview(int step, int rows)
    signal committed(int step, int rows, bool stepChanged, bool rowsChanged)
    signal canceled

    function pointerAt(px, py) {
        if (pointerItem)
            return pointerItem.mapToGlobal(px + pointerInset, py + pointerInset);
        return Qt.point(px + popout.renderedAlignedX, py + popout.renderedAlignedY);
    }

    function edgeFor(step, side) {
        const width = widthFor(step) + gutter * 2;
        return popout.alignedXFor(width) + (side > 0 ? width : 0);
    }

    function sideMovable(signX, step) {
        const side = (signX < 0 ? -1 : 1) * (I18n.isRtl ? -1 : 1);
        const width = widthFor(step) + gutter * 2;
        const x = popout.alignedXFor(width);
        const grown = popout.alignedXFor(width + stepWidth);
        return side > 0 ? grown + stepWidth !== x : grown !== x;
    }

    function begin(px, py, signX) {
        if (_drag)
            return;
        const step = currentStep();
        const rows = currentRows();
        const side = (signX < 0 ? -1 : 1) * (I18n.isRtl ? -1 : 1);
        const point = pointerAt(px, py);
        // Freeze screen-space snap points because previews can move the host.
        const edges = {};
        for (let candidate = minStep; candidate <= maxStep; candidate++)
            edges[candidate] = edgeFor(candidate, side);
        const rowEdges = {};
        if (signX === 0 && rowEdgeFor) {
            for (let candidate = minRows; candidate <= maxRows; candidate++)
                rowEdges[candidate] = rowEdgeFor(candidate);
        }
        _drag = {
            "step": step,
            "rows": rows,
            "previewStep": step,
            "previewRows": rows,
            "edges": edges,
            "rowEdges": rowEdges,
            "minStep": minStep,
            "maxStep": maxStep,
            "minRows": minRows,
            "maxRows": maxRows,
            "vertical": signX === 0,
            "x": point.x,
            "y": point.y
        };
    }

    function move(px, py) {
        const drag = _drag;
        if (!drag)
            return;
        const point = pointerAt(px, py);
        const wanted = drag.edges[drag.step] + point.x - drag.x;
        const step = drag.vertical ? drag.step :GridUtils.nearestStep(step => drag.edges[step], drag.step, Math.max(minStep, drag.minStep), Math.min(maxStep, drag.maxStep), wanted);
        let rows = drag.rows;
        if (drag.vertical && rowEdgeFor) {
            const wantedRow = drag.rowEdges[drag.rows] + point.y - drag.y;
            rows = GridUtils.nearestStep(rows => drag.rowEdges[rows], drag.rows, drag.minRows, drag.maxRows, wantedRow);
        } else if (rowUnit > 0) {
            rows = Math.max(minRows, Math.min(maxRows, drag.rows + Math.round((point.y - drag.y) / rowUnit)));
        }
        if (step === drag.previewStep && rows === drag.previewRows)
            return;
        drag.previewStep = step;
        drag.previewRows = rows;
        preview(step, rows);
    }

    function end() {
        const drag = _drag;
        if (!drag)
            return;
        _drag = null;
        if (drag.previewStep === drag.step && drag.previewRows === drag.rows) {
            canceled();
            return;
        }
        committed(drag.previewStep, drag.previewRows, drag.previewStep !== drag.step, drag.previewRows !== drag.rows);
    }

    function cancel() {
        if (!_drag)
            return;
        _drag = null;
        canceled();
    }
}
