import QtQuick
import qs.Common
import "../Common/GridLayout.js" as GridUtils

QtObject {
    id: root

    required property var popout
    property real gutter: 0
    property real stepWidth: 0
    property var widthFor: step => 0
    property var currentStep: () => 0
    property var currentRows: () => 0
    property int minStep: 0
    property int maxStep: 0
    property real rowUnit: 0
    property int minRows: 0
    property int maxRows: 0
    readonly property bool resizing: _drag !== null
    property var _drag: null

    signal preview(int step, int rows)
    signal committed(int step, int rows, bool stepChanged, bool rowsChanged)
    signal canceled

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
        _drag = {
            "step": step,
            "rows": rows,
            "previewStep": step,
            "previewRows": rows,
            "side": (signX < 0 ? -1 : 1) * (I18n.isRtl ? -1 : 1),
            "x": px + popout.renderedAlignedX,
            "y": py + popout.renderedAlignedY
        };
    }

    function move(px, py) {
        const drag = _drag;
        if (!drag)
            return;
        const wanted = edgeFor(drag.step, drag.side) + px + popout.renderedAlignedX - drag.x;
        const step = GridUtils.nearestStep(step => edgeFor(step, drag.side), drag.step, minStep, maxStep, wanted);
        const rows = rowUnit > 0 ? Math.max(minRows, Math.min(maxRows, drag.rows + Math.round((py + popout.renderedAlignedY - drag.y) / rowUnit))) : drag.rows;
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
