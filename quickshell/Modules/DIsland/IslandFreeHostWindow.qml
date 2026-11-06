pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
    id: root

    required property string barId

    readonly property bool free: true
    readonly property bool dot: body.dotMode
    readonly property var barConfig: SettingsData.getBarConfig(root.barId)
    readonly property var islandController: body.islandController
    readonly property int launcherResultCount: body.launcherResultCount
    readonly property int hostOriginX: body.hostOriginX
    readonly property int hostOriginY: body.hostOriginY
    readonly property real dotSize: body.dotSize
    readonly property real compactWidth: body.islandController.compactTarget.width
    readonly property real compactHeight: body.islandController.compactTarget.height
    readonly property real idleScale: Math.max(0.2, Math.min(1, body.setting("islandFreeIdleScale")))
    readonly property real idleOpacity: Math.max(0.05, Math.min(1, body.setting("islandFreeIdleOpacity")))
    readonly property int idleDelay: root.dot ? body.setting("islandFreeIdleDelay") : 0
    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080
    readonly property string positionKey: IslandHostRegistry.key(root.screen?.name, root.barId)
    readonly property var storedAnchor: SessionData.islandFreePositions[root.positionKey] ?? null
    readonly property point storedPoint: Qt.point(root.clampAnchorX((typeof root.storedAnchor?.x === "number" ? root.storedAnchor.x : 0.5) * root.screenWidth), root.clampAnchorY((typeof root.storedAnchor?.y === "number" ? root.storedAnchor.y : 0.5) * root.screenHeight))
    readonly property real anchorX: root.anchor.x
    readonly property real anchorY: root.anchor.y

    readonly property bool expanded: body.expanded
    readonly property bool pointerInside: body.islandController.pointerInside
    readonly property string activeActivity: body.islandController.activeActivity
    readonly property bool motionRunning: body.motionRunning
    // A shrunk nub keeps the full dot's hit area and surface, so idling and waking never resize the window.
    readonly property real hitPadding: root.dot ? Math.max(0, (root.dotSize - body.currentVisualWidth) / 2) : 0
    // Blur regions are not antialiased and a small circle shows the jagged rim, so blur waits for the morph.
    readonly property bool blurWanted: !root.dot || Math.min(body.currentVisualWidth, body.currentVisualHeight) > root.dotSize * 1.5

    property point anchor
    property bool dragging: false
    property bool flinging: false
    // sheetOut spans the expand through the collapse spring.
    readonly property bool anchorHeld: root.dragging || root.flinging || body.sheetOut
    readonly property bool dismissActive: body.islandController.outsideClickCollapses && !body.inputSuspended
    property bool idle: false

    function anchorLimit(size, extent) {
        const half = size / 2;
        const low = body.freeMargin + half;
        const high = extent - body.freeMargin - half;
        return high <= low ? [extent / 2, extent / 2] : [low, high];
    }

    function clampAnchorX(value) {
        const range = root.anchorLimit(root.compactWidth, root.screenWidth);
        return Math.max(range[0], Math.min(value, range[1]));
    }

    function clampAnchorY(value) {
        const range = root.anchorLimit(root.compactHeight, root.screenHeight);
        return Math.max(range[0], Math.min(value, range[1]));
    }

    function storeAnchor() {
        SessionData.setIslandFreePosition(root.positionKey, root.anchor.x / root.screenWidth, root.anchor.y / root.screenHeight);
    }

    function moveTo(x, y) {
        root.anchor = Qt.point(root.clampAnchorX(x), root.clampAnchorY(y));
        root.storeAnchor();
        root.wake();
    }

    function wake() {
        root.idle = false;
        if (root.idleDelay > 0)
            idleTimer.restart();
        else
            idleTimer.stop();
    }

    function requestKeyboardFocus() {
        body.requestKeyboardFocus();
    }

    function containsGlobalPoint(gx, gy, padding) {
        return body.containsGlobalPoint(gx, gy, padding);
    }

    onStoredPointChanged: {
        if (!root.anchorHeld)
            root.anchor = root.storedPoint;
    }
    // Stored once the fling settles; a save mid-gesture stalls the fling's first frame.
    onAnchorHeldChanged: {
        if (!root.anchorHeld)
            root.storeAnchor();
    }
    onMotionRunningChanged: {
        if (!root.motionRunning)
            root.flinging = false;
    }
    onPointerInsideChanged: root.wake()
    onExpandedChanged: root.wake()
    onActiveActivityChanged: root.wake()
    onIdleDelayChanged: root.wake()

    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "dms:dankisland"
    WlrLayershell.layer: LayerShell.fromEnv("DMS_DANKISLAND_LAYER", body.usesOverlayLayer ? WlrLayer.Overlay : WlrLayer.Top)
    WlrLayershell.keyboardFocus: islandChrome.keyboardFocusPolicy
    BackgroundEffect.blurRegion: root.blurWanted && BlurService.enabled && BlurService.available && body.surfaceOpacity > 0 && body.surfaceOpacity < 1 ? surfaceBlurRegion : null

    Region {
        id: surfaceBlurRegion

        readonly property real left: body.x + body.currentVisualX
        readonly property real top: body.y + body.currentVisualY

        x: Math.ceil(left)
        y: Math.ceil(top)
        width: Math.max(0, Math.floor(left + body.currentVisualWidth) - x)
        height: Math.max(0, Math.floor(top + body.currentVisualHeight) - y)
        radius: Math.ceil(body.currentSurfaceRadius)
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Component.onCompleted: {
        root.wake();
        KeyboardFocus.registerBarWindow(root);
    }
    Component.onDestruction: KeyboardFocus.unregisterBarWindow(root)

    IslandHostChrome {
        id: islandChrome

        window: root
        host: body
    }

    Timer {
        id: idleTimer

        interval: root.idleDelay
        onTriggered: {
            if (root.expanded || root.pointerInside || hitHover.hovered || root.anchorHeld || body.islandController.transientActive)
                return;
            root.idle = true;
        }
    }

    // A quick stroke outruns the dot's rectangle between frames and the pointer leave ends the drag, so a drag takes input everywhere.
    mask: root.dragging || root.dismissActive ? null : hitRegion
    Region {
        id: hitRegion

        item: body.inputSuspended ? null : hitTarget
    }
    Item {
        id: hitTarget

        x: body.currentVisualX - root.hitPadding
        y: body.currentVisualY - root.hitPadding
        width: body.currentVisualWidth + 2 * root.hitPadding
        height: body.currentVisualHeight + 2 * root.hitPadding

        // The idle ring around a shrunk nub takes clicks and drags, so hovering it wakes the dot too.
        HoverHandler {
            id: hitHover

            onHoveredChanged: root.wake()
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.dismissActive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: body.islandController.requestCollapse()
    }

    // Clicks inside the morph envelope stay with the island instead of collapsing it.
    MouseArea {
        readonly property Item envelope: body.inputMaskItem

        enabled: root.dismissActive
        x: envelope.x
        y: envelope.y
        width: envelope.width
        height: envelope.height
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => mouse.accepted = true
    }

    MouseArea {
        anchors.fill: hitTarget
        enabled: !root.expanded && !body.inputSuspended
        onClicked: {
            SettingsData.recordBarInteraction(root.screen, root.barId);
            body.islandController.requestToggle(true);
        }
    }

    IslandBarHost {
        id: body

        width: root.screenWidth
        height: root.screenHeight
        barConfig: root.barConfig
        screen: root.screen
        hostWindow: root
        barId: root.barId
        anchor: root.anchor
        anchorSnaps: root.dragging
        freeScale: root.idle ? root.idleScale : 1
        freeOpacity: root.idle ? root.idleOpacity : 1
    }

    IslandFreeDragArea {
        hostWindow: root
        surface: body.surface
        enabled: !root.expanded && !body.inputSuspended
    }
}
