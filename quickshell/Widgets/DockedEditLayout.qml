import QtQuick
import qs.Common

// Where a DPopout's edit panel docks: a side picked on entering edit mode, or the strip when there is no room.
QtObject {
    id: root

    required property var popout
    property bool editMode: false
    property bool wanted: false
    required property real panelWidth
    property real panelGap: 0
    property real connectedPanelGap: 0
    required property real minHeight
    property real minBodyHeight: 0
    required property real availableHeight
    property int baseCap: 1
    property int pickColumns: 1
    property int keepColumns: 1
    required property var widthFor

    // Latched on entering edit mode ("" until decided, then "strip", "left" or "right") so a width change cannot move the body mid-edit.
    property string _layout: ""
    // Drops to the strip if the screen loses the room mid-edit (output change, bar resize) instead of squeezing the panel.
    readonly property string side: (_layout === "left" || _layout === "right") && _roomFor(_layout) ? _layout : ""
    readonly property bool decided: _layout !== ""
    readonly property bool fits: editMode && side !== ""
    readonly property bool stripEdit: editMode && decided && side === ""
    // Docked was wanted but did not fit: the panel opens as a popover over the body instead.
    readonly property bool popover: stripEdit && wanted
    // While docked the cap keeps the panel's room free, so widening the body can never squeeze it out.
    readonly property int cap: side !== "" ? Math.min(baseCap, _dockedCap(side)) : baseCap
    // Connected, the body's flares run along the bar, so the panel keeps clear of them and of the bar itself.
    readonly property real gap: popout.usesConnectedSurfaceChrome ? connectedPanelGap : panelGap
    readonly property real inset: popout.usesConnectedSurfaceChrome && (popout.effectiveBarPosition === SettingsData.Position.Top || popout.effectiveBarPosition === SettingsData.Position.Bottom) ? gap : 0
    readonly property real reserve: panelWidth + gap
    readonly property real leftOverflow: fits && side === "left" ? reserve : 0
    readonly property real rightOverflow: fits && side === "right" ? reserve : 0
    readonly property real _minHeight: minHeight + inset
    // The panel keeps its own floor and hangs past a shorter body, toward the side with room.
    readonly property real overhang: overhangFor(popout.popupHeight)
    // Judged at the shortest body, so a height drag never flips the panel across and moves the body under the pointer.
    readonly property bool dockAbove: fits && popout.alignedYFor(0, Math.max(0, _minHeight - minBodyHeight), minBodyHeight) !== popout.alignedYFor(0, 0, minBodyHeight)
    readonly property real sideTopOverflow: dockAbove ? overhang : 0
    readonly property real sideBottomOverflow: dockAbove ? 0 : overhang

    function overhangFor(height) {
        return fits ? Math.max(0, _minHeight - height) : 0;
    }

    function _dockedCap(side) {
        for (let columns = baseCap; columns >= 1; columns--) {
            const width = widthFor(columns);
            if ((side === "left" ? popout.roomLeftFor(width) : popout.roomRightFor(width)) >= reserve)
                return columns;
        }
        return 0;
    }

    function _roomFor(side) {
        return availableHeight >= _minHeight && _dockedCap(side) >= keepColumns;
    }

    // Short screens keep the strip, with the list in a popover; a short body still docks, with the panel hanging past it.
    function _pick() {
        if (!wanted || availableHeight < _minHeight)
            return "strip";
        let preferLeft;
        switch (popout.effectiveBarPosition) {
        case SettingsData.Position.Right:
            preferLeft = true;
            break;
        case SettingsData.Position.Left:
            preferLeft = false;
            break;
        default:
            preferLeft = popout.alignedX + popout.alignedWidth / 2 >= popout.screenWidth / 2;
        }
        const first = preferLeft ? "left" : "right";
        const second = preferLeft ? "right" : "left";
        if (_dockedCap(first) >= pickColumns)
            return first;
        if (_dockedCap(second) >= pickColumns)
            return second;
        return "strip";
    }

    onEditModeChanged: _layout = editMode ? _pick() : ""
}
