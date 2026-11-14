pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import "../Common/PopoutBounds.js" as PopoutBounds

DIdleSurface {
    id: root

    readonly property int hostCount: hostItem.children.length
    readonly property var activeHost: hostCount > 0 ? (hostItem.children[hostCount - 1].host ?? null) : null
    readonly property alias hostItem: hostItem
    readonly property var focusWindows: dismissalLoader.item ? [root, dismissalLoader.item] : [root]

    requestedBounds: {
        if (!idleSupported || !active)
            return Qt.rect(0, 0, 0, 0);
        let bounds = {
            x: 0,
            y: 0,
            width: 0,
            height: 0
        };
        for (const child of hostItem.children) {
            const host = child.host;
            if (!host || host.overlayContent)
                return Qt.rect(0, 0, screenWidth, screenHeight);
            bounds = PopoutBounds.unite(bounds, host.renderBounds);
        }
        return Qt.rect(bounds.x, bounds.y, bounds.width, bounds.height);
    }

    kind: "popout"
    // A full-screen idle surface is blacked out whole by compositor capture rules matching this namespace.
    compactWhenIdle: true
    active: hostCount > 0
    maskItem: activeHost?.maskItem ?? null

    WlrLayershell.namespace: "dms:popout"
    WlrLayershell.layer: activeHost?.effectivePopoutLayer ?? WlrLayer.Top
    WlrLayershell.keyboardFocus: activeHost?.surfaceKeyboardFocus ?? WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: activeHost?.blurRegion ?? null

    Loader {
        id: dismissalLoader
        active: root.idleSupported
        sourceComponent: DIdleSurface {
            id: dismissal
            screen: root.screen
            renders: false
            active: root.active && root.bounded && (root.activeHost?.shouldBeVisible ?? false) && (root.activeHost?.backgroundInteractive ?? false)
            WlrLayershell.namespace: "dms:popout-dismiss"
            WlrLayershell.layer: root.WlrLayershell.layer
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {
                x: root.activeHost?.maskX ?? 0
                y: root.activeHost?.maskY ?? 0
                width: dismissal.active ? (root.activeHost?.maskWidth ?? 0) : 0
                height: dismissal.active ? (root.activeHost?.maskHeight ?? 0) : 0
                Region {
                    x: root.renderBounds.x
                    y: root.renderBounds.y
                    width: root.renderBounds.width
                    height: root.renderBounds.height
                    intersection: Intersection.Subtract
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: root.activeHost?.backgroundClicked()
            }
        }
    }

    Item {
        id: hostItem
        x: -root.bandX
        y: -root.bandY
        width: root.screenWidth
        height: root.screenHeight
    }
}
