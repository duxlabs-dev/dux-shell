import QtQuick
import Quickshell
import qs.Common

PanelWindow {
    id: root

    property string kind: ""
    property bool active: false
    property bool renders: true
    property Item maskItem: null
    // Content that lives along one edge takes a strip there instead of the whole output; "column" and "row" are centered.
    property string band: ""
    property real bandSize: 0
    readonly property bool _column: band === "left" || band === "right" || band === "column"
    readonly property bool _row: band === "top" || band === "bottom" || band === "row"
    readonly property real screenWidth: screen?.width ?? 0
    readonly property real screenHeight: screen?.height ?? 0
    // Screen position of this window's origin, so hosts can keep laying out in screen coordinates.
    readonly property int bandExtent: Math.max(1, Math.ceil(bandSize))
    readonly property real bandX: band === "right" ? screenWidth - bandExtent : band === "column" ? Math.round((screenWidth - bandExtent) / 2) : 0
    readonly property real bandY: band === "bottom" ? screenHeight - bandExtent : band === "row" ? Math.round((screenHeight - bandExtent) / 2) : 0
    property string _registeredName: ""
    readonly property bool idleSupported: "inputOnly" in root

    property bool _mapped: true

    visible: _mapped && (idleSupported || active)
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: !_row || band === "top"
        bottom: !_row || band === "bottom"
        left: !_column || band === "left"
        right: !_column || band === "right"
    }

    implicitWidth: _column ? bandExtent : 0
    implicitHeight: _row ? bandExtent : 0

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
