import qs.DCommon.Widgets as DCommon

DCommon.FocusRing {
    // Plain Items have no visualFocus; a tile sets this on its own press so a mouse click draws no ring
    property bool pointerFocused: false
    readonly property bool parentFocused: parent?.activeFocus ?? false

    visible: parentFocused && !pointerFocused

    onParentFocusedChanged: {
        if (!parentFocused)
            pointerFocused = false;
    }
}
