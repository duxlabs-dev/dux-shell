import QtQuick
import qs.Common
import "../../../Common/IslandKit.js" as Kit

// Split by weight in whole pixels, so a row's edges stay sharp; hidden buttons give their share to the others.
Item {
    id: row

    property real spacing: Theme.spacingXS
    // Buttons sit in the order they are declared, which is also their Tab order; right to left, both run from the right.
    readonly property bool mirrored: I18n.isRtl

    readonly property var shown: {
        const out = [];
        for (let i = 0; i < row.children.length; i++) {
            if (row.children[i].visible)
                out.push(row.children[i]);
        }
        return out;
    }
    readonly property var cells: Kit.rowLayout(row.width, row.shown.map(item => item.weight ?? 1), row.spacing)

    implicitHeight: Theme.buttonHeightS

    // Placed from here, not by bindings: a binding written onto a card's button is dropped by the first x or width the
    // card sets on it. A button just shown may have no cell yet: it is placed once cells follow.
    function place() {
        row.shown.forEach((item, i) => {
            const cell = row.cells[i];
            if (!cell)
                return;
            item.x = row.mirrored ? row.width - cell.x - cell.width : cell.x;
            item.width = cell.width;
            item.height = row.height;
        });
    }
    onCellsChanged: row.place()
    onHeightChanged: row.place()
    onMirroredChanged: row.place()
}
