import QtQuick
import Quickshell
import qs.Common
import qs.Services
import "../Common/PopoutBounds.js" as PopoutBounds

PanelWindow {
    id: root

    property string kind: ""
    property bool active: false
    property bool renders: true
    property Item maskItem: null
    property rect requestedBounds: Qt.rect(0, 0, 0, 0)
    property rect _envelope: Qt.rect(0, 0, 0, 0)
    readonly property rect renderBounds: {
        if (active && boundsSupported)
            return _envelope;
        if (compactWhenIdle && idleSupported)
            return Qt.rect(0, 0, 1, 1);
        return Qt.rect(0, 0, 0, 0);
    }
    readonly property bool bounded: renderBounds.width > 0 && renderBounds.height > 0
    property string band: ""
    property real bandSize: 0
    readonly property bool _column: band === "left" || band === "right" || band === "column"
    readonly property bool _row: band === "top" || band === "bottom" || band === "row"
    readonly property real screenWidth: screen?.width ?? 0
    readonly property real screenHeight: screen?.height ?? 0
    readonly property int bandExtent: Math.max(1, Math.ceil(bandSize))
    readonly property real bandOriginX: band === "right" ? screenWidth - bandExtent : band === "column" ? Math.round((screenWidth - bandExtent) / 2) : 0
    readonly property real bandX: bounded ? renderBounds.x : bandOriginX
    readonly property real bandY: bounded ? renderBounds.y : band === "bottom" ? screenHeight - bandExtent : band === "row" ? Math.round((screenHeight - bandExtent) / 2) : 0
    property string _registeredName: ""
    property bool keepMapped: true
    property bool compactWhenIdle: false
    // Without render control an inputOnly window still renders, on its own thread and buffers.
    // Hyprland focuses an OnDemand layer only as it maps, and shows its old geometry for a frame.
    readonly property bool boundsSupported: "inputOnly" in root && Quickshell.renderControl === true && !CompositorService.isHyprland
    readonly property bool idleSupported: keepMapped && boundsSupported

    property bool _mapped: true
    // Lags active by a turn when bounded on demand, so the surface maps at its bounds and not the band.
    property bool _shown: false

    visible: _mapped && (idleSupported || _shown)
    color: "transparent"
    exclusiveZone: -1

    anchors {
        top: root.bounded || !_row || band === "top"
        bottom: !root.bounded && (!_row || band === "bottom")
        left: root.bounded || !_column || band === "left"
        right: !root.bounded && (!_column || band === "right")
    }

    margins.left: bounded ? renderBounds.x : 0
    margins.top: bounded ? renderBounds.y : 0

    implicitWidth: bounded ? renderBounds.width : _column ? bandExtent : 0
    implicitHeight: bounded ? renderBounds.height : _row ? bandExtent : 0

    mask: Region {
        item: root.active ? root.maskItem : null
    }

    function _syncIdle() {
        if (!idleSupported)
            return;
        inputOnly = !active || !renders;
    }

    function _boundsFrom(base) {
        if (!active || requestedBounds.width <= 0 || requestedBounds.height <= 0)
            return Qt.rect(0, 0, 0, 0);
        const bounds = PopoutBounds.clip(PopoutBounds.unite(base, requestedBounds), screenWidth, screenHeight);
        return Qt.rect(bounds.x, bounds.y, bounds.width, bounds.height);
    }

    function growBounds() {
        _envelope = _boundsFrom(_envelope);
    }

    function fitBounds() {
        _envelope = _boundsFrom(Qt.rect(0, 0, 0, 0));
    }

    function _syncShown() {
        _shown = active;
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

    onActiveChanged: {
        _syncIdle();
        fitBounds();
        if (active && boundsSupported && !idleSupported) {
            Qt.callLater(_syncShown);
            return;
        }
        _shown = active;
    }
    onRequestedBoundsChanged: growBounds()
    onRendersChanged: _syncIdle()
    Component.onCompleted: {
        _syncIdle();
        fitBounds();
        _shown = active;
        _register();
    }
    Component.onDestruction: {
        if (_registeredName)
            IdleSurfaces.unregister(kind, _registeredName, root);
    }
}
