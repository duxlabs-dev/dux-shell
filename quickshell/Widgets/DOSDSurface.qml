import QtQuick
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../Common/PopoutBounds.js" as PopoutBounds

DIdleSurface {
    id: root

    readonly property int hostCount: hostItem.children.length
    readonly property var activeHost: hostCount > 0 ? (hostItem.children[hostCount - 1].host ?? null) : null
    readonly property alias hostItem: hostItem

    requestedBounds: {
        if (!boundsSupported || !active)
            return Qt.rect(0, 0, 0, 0);
        let bounds = {
            x: 0,
            y: 0,
            width: 0,
            height: 0
        };
        for (const child of hostItem.children) {
            const host = child.host;
            if (!host || host.expanded)
                return Qt.rect(0, 0, screenWidth, screenHeight);
            bounds = PopoutBounds.unite(bounds, host.renderBounds);
        }
        return Qt.rect(bounds.x, bounds.y, bounds.width, bounds.height);
    }

    kind: "osd"
    // Maps per show, so it stacks above overlay surfaces mapped since the last one.
    keepMapped: false
    active: hostCount > 0 && IdleService.chromeOpacity > 0
    contentItem.opacity: IdleService.chromeOpacity
    maskItem: activeHost?.maskItem ?? null

    WlrLayershell.namespace: "dms:osd"
    WlrLayershell.layer: LayerShell.fromEnv("DMS_OSD_LAYER", WlrLayer.Overlay, {
        "allow": ["top", "overlay"],
        "invalidLayer": WlrLayer.Overlay,
        "label": "OSDs"
    })
    WlrLayershell.keyboardFocus: activeHost?.surfaceKeyboardFocus ?? WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: activeHost?.blurRegion ?? null

    Item {
        id: hostItem
        x: -root.bandX
        y: -root.bandY
        width: root.screenWidth
        height: root.screenHeight
    }
}
