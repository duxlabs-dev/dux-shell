import QtQuick
import Quickshell
import qs.Common

PanelWindow {
    id: root

    property string kind: ""
    property bool active: false
    property bool renders: true
    property Item maskItem: null
    property string _registeredName: ""
    readonly property bool idleSupported: "inputOnly" in root

    property bool _mapped: true

    visible: _mapped && (idleSupported || active)
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        item: root.active ? root.maskItem : null
    }

    function _syncIdle() {
        if (!idleSupported)
            return;
        inputOnly = !active || !renders;
    }

    function remap() {
        if (!visible)
            return;
        _mapped = false;
        Qt.callLater(() => _mapped = true);
    }

    function _register() {
        const name = screen?.name ?? "";
        if (!kind || !name)
            return;
        _registeredName = name;
        IdleSurfaces.register(kind, name, root);
    }

    onActiveChanged: _syncIdle()
    onRendersChanged: _syncIdle()
    Component.onCompleted: {
        _syncIdle();
        _register();
    }
    Component.onDestruction: {
        if (_registeredName)
            IdleSurfaces.unregister(kind, _registeredName, root);
    }
}
