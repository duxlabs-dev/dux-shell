import QtQuick
import Quickshell.Wayland
import qs.Widgets

DFocusGrab {
    id: root

    required property var window
    property Item host: null

    readonly property bool sheetOut: root.host?.sheetOut ?? false
    readonly property int keyboardFocusPolicy: root.host?.keyboardFocusPolicy ?? WlrKeyboardFocus.None
    readonly property var maskItem: root.host && !root.host.inputSuspended ? root.host.inputMaskItem : null
    readonly property var fittsStripItem: root.host && !root.host.inputSuspended ? root.host.fittsStripItem : null

    windows: [root.window].concat(root.host?.dismissWindow ?? [], root.host?.transientFocusWindows ?? [])
    wanted: root.host?.wantsFocusGrab ?? false
}
