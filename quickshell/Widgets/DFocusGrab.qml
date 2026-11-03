import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Common
import "../Common/WorkspaceModel.js" as WorkspaceModel

// Delays grab release so keyboardFocus=None commits before the grab dies,
// keeping Hyprland from handing focus back to the closing surface (#2577)
HyprlandFocusGrab {
    id: root

    property bool wanted: false
    property bool _held: false
    property bool _compositorCleared: false
    property var _restoreToplevel: null
    property string _restoreWorkspace: ""
    readonly property Toplevel liveToplevel: ToplevelManager.activeToplevel

    property Timer _releaseTimer: Timer {
        interval: 50
        onTriggered: {
            root._held = false;
            root.active = false;
            // Restoring a toplevel from another workspace would drag the user back
            // to the workspace they just navigated away from (#2963)
            const workspaceChanged = String(WorkspaceModel.hyprlandKey(Hyprland.focusedWorkspace)) !== root._restoreWorkspace;
            root._restoreToplevel = (root._compositorCleared || workspaceChanged) ? null : KeyboardFocus.restoreToplevel(root._restoreToplevel);
        }
    }

    onWantedChanged: _sync()
    // Don't restore a window the user already left while the grab was held
    onLiveToplevelChanged: {
        if (!_held || !wanted || !liveToplevel || liveToplevel === _restoreToplevel)
            return;
        _restoreToplevel = null;
    }
    Component.onCompleted: _sync()

    function _sync() {
        if (!wanted) {
            if (_held)
                _releaseTimer.restart();
            return;
        }
        _releaseTimer.stop();
        _held = true;
        _compositorCleared = false;
        _restoreToplevel = KeyboardFocus.captureActiveToplevel();
        _restoreWorkspace = String(WorkspaceModel.hyprlandKey(Hyprland.focusedWorkspace));
        active = true;
    }

    onCleared: _compositorCleared = true
}
