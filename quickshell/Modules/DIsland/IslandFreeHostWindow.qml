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
    // Sized from the visual's size alone, so a fractional spring position never resizes the surface.
    readonly property int surfaceX: Math.floor(body.currentVisualX - root.hitPadding - body.shadowPadding)
    readonly property int surfaceY: Math.floor(body.currentVisualY - root.hitPadding - body.shadowPadding)
    readonly property int surfaceWidth: Math.ceil(body.currentVisualWidth + 2 * (root.hitPadding + body.shadowPadding)) + 1
    readonly property int surfaceHeight: Math.ceil(body.currentVisualHeight + 2 * (root.hitPadding + body.shadowPadding)) + 1

    // Gestures and morphs run on a surface lifted to the whole output: per-frame margin commits skew pointer coordinates and relayout Hyprland.
    property bool lifting: false
    property bool liftForced: false
    property point liftOrigin
    // True from the unlift until the tight configure lands: a re-grab in that window still reads the output size.
    property bool sizeStale: false
    readonly property bool outputSized: root.width >= root.screenWidth - 2 && root.height >= root.screenHeight - 2
    // Negative far margins grow the surface in place; the origin flips only once the buffer spans the output.
    readonly property bool lifted: root.lifting && (root.liftForced || (!root.sizeStale && root.outputSized))
    readonly property int frameLeft: root.lifted ? 0 : root.lifting ? root.liftOrigin.x : root.surfaceX
    readonly property int frameTop: root.lifted ? 0 : root.lifting ? root.liftOrigin.y : root.surfaceY
    readonly property int frameRight: root.lifting ? -root.frameLeft : Math.round(root.screenWidth) - root.surfaceX - root.surfaceWidth
    readonly property int frameBottom: root.lifting ? -root.frameTop : Math.round(root.screenHeight) - root.surfaceY - root.surfaceHeight

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
    // sheetOut spans the expand through the collapse spring, so the whole morph draws into one static buffer.
    readonly property bool liftWanted: root.dragging || root.flinging || body.sheetOut
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

    function beginLift() {
        if (root.lifting)
            return;
        root.liftOrigin = Qt.point(root.frameLeft, root.frameTop);
        root.liftForced = false;
        root.lifting = true;
        liftTimeout.restart();
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
        if (!root.liftWanted)
            root.anchor = root.storedPoint;
    }
    // Stored once the fling settles; a save mid-gesture stalls the fling's first frame.
    onLiftWantedChanged: {
        if (root.liftWanted) {
            root.beginLift();
            return;
        }
        root.sizeStale = root.outputSized;
        root.lifting = false;
        liftTimeout.stop();
        root.storeAnchor();
    }
    onOutputSizedChanged: {
        if (!root.outputSized)
            root.sizeStale = false;
    }
    onLiftedChanged: {
        if (root.lifted)
            liftTimeout.stop();
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

    // All four edges are anchored so the margins alone place and size the surface, letting a lift grow it past the output.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    WlrLayershell.margins {
        left: root.frameLeft
        top: root.frameTop
        right: root.frameRight
        bottom: root.frameBottom
    }

    Component.onCompleted: {
        root.wake();
        KeyboardFocus.registerBarWindow(root);
    }
    Component.onDestruction: KeyboardFocus.unregisterBarWindow(root)

    IslandHostChrome {
        id: islandChrome

        window: root
        extraWindows: [dismissWindow]
        host: body
    }

    Timer {
        id: idleTimer

        interval: root.idleDelay
        onTriggered: {
            if (root.expanded || root.pointerInside || hitHover.hovered || root.liftWanted || body.islandController.transientActive)
                return;
            root.idle = true;
        }
    }

    // A compositor that never sizes the lifted surface would leave every drag frozen.
    Timer {
        id: liftTimeout

        interval: 250
        onTriggered: root.liftForced = true
    }

    // A quick stroke outruns the dot's rectangle between frames and the pointer leave ends the drag, so a drag takes input everywhere.
    mask: root.dragging && root.lifted ? null : hitRegion
    Region {
        id: hitRegion

        item: body.inputSuspended ? null : hitTarget
    }
    Item {
        id: hitTarget

        x: body.currentVisualX - root.hitPadding - root.frameLeft
        y: body.currentVisualY - root.hitPadding - root.frameTop
        width: body.currentVisualWidth + 2 * root.hitPadding
        height: body.currentVisualHeight + 2 * root.hitPadding

        // The idle ring around a shrunk nub takes clicks and drags, so hovering it wakes the dot too.
        HoverHandler {
            id: hitHover

            onHoveredChanged: root.wake()
        }
    }

    // Catches outside clicks; the lifted surface's own mask stays the island rectangle.
    PanelWindow {
        id: dismissWindow
        screen: root.screen
        visible: body.islandController.outsideClickCollapses && !body.inputSuspended
        color: "transparent"
        exclusiveZone: -1
        WlrLayershell.namespace: "dms:dankisland-dismiss"
        WlrLayershell.layer: root.WlrLayershell.layer
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // The frozen spring envelope, so this full-output surface is not re-committed every frame of a morph.
        mask: Region {
            width: dismissWindow.width
            height: dismissWindow.height
            Region {
                readonly property Item envelope: body.inputMaskItem

                x: dismissWindow.visible ? envelope.x : 0
                y: dismissWindow.visible ? envelope.y : 0
                width: dismissWindow.visible ? envelope.width : 0
                height: dismissWindow.visible ? envelope.height : 0
                intersection: Intersection.Subtract
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: body.islandController.requestCollapse()
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.expanded && !body.inputSuspended
        onClicked: {
            SettingsData.recordBarInteraction(root.screen, root.barId);
            body.islandController.requestToggle(true);
        }
    }

    IslandBarHost {
        id: body

        x: -root.frameLeft
        y: -root.frameTop
        width: root.screenWidth
        height: root.screenHeight
        originOffsetX: x
        originOffsetY: y
        barConfig: root.barConfig
        screen: root.screen
        hostWindow: root
        hostLifted: root.lifted
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
