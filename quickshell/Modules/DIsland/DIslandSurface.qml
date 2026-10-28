pragma ComponentBehavior: Bound

import qs.Modules.SurfaceWidgets
import QtQuick
import qs.Common
import qs.Modules.DDash
import qs.Modules.DIsland.Activities
import qs.Services
import qs.Widgets

Item {
    id: root

    required property IslandController controller
    required property var mediaModel
    required property var systemModel
    required property var notificationModel
    required property var launcherController
    property var launcherTransientSurfaceTracker: null
    property var effectiveScreen: null
    property bool reducedMotion: false
    property real springStiffness: 560
    property real springDamping: 37
    property real springMass: 1
    property real hostOriginX: 0
    property real hostOriginY: 0
    property string palette: "default"
    property bool highContrast: false
    property real transparency: 1
    property color surfaceBase: Theme.hostSurface
    property string requestedWindow: ""
    property bool freeMode: false
    property bool anchorSnaps: false
    property point anchor
    // Velocity the next applyTarget seeds the spring with; a released drag flings from it.
    property var flingSeed: null
    property real freeMargin: 8
    // Measured from the band centre, not the band start.
    property real anchorAlong: 0
    property real nearInset: 0
    property real bandAlongStart: 0
    property real bandAlongEnd: root.alongExtent
    // Hosted: false while the bar window is still band sized, so the sheet never starts inside a window that clips it.
    property bool hostReady: true
    property bool targetPending: false
    onHostReadyChanged: {
        if (!root.hostReady || !root.targetPending)
            return;
        root.targetPending = false;
        root.applyTarget();
    }
    property Component compactFaceOverride: null
    // "own" paints the palette; "band" wears the host bar's colour with join corners; "none" paints nothing and leaves the silhouette to the frame SDF.
    property string chrome: "own"
    // Flush with the screen edge, with concave flares where it meets it.
    property bool notch: false
    property real notchRadius: Theme.windowRadius
    property color bandColor: Theme.hostSurface
    property bool compactBackground: false
    property color compactBackgroundColor: "transparent"
    readonly property bool embedded: root.chrome !== "own"
    readonly property bool chromeless: root.chrome === "none"

    readonly property color surfaceColor: {
        if (root.highContrast)
            return Theme.surfaceContainerHighest;
        switch (root.palette) {
        case "bright":
            return Theme.surfaceBright;
        case "dim":
            return Theme.surfaceDim;
        }
        return root.surfaceBase;
    }
    readonly property bool popupStyled: root.controller.expanded
    readonly property real islandOpacity: Math.max(0, Math.min(1, root.transparency))
    readonly property color effectiveSurfaceColor: root.embedded ? root.bandColor : root.highContrast ? Theme.surfaceContainerHighest : Theme.withAlpha(root.surfaceColor, root.islandOpacity)
    readonly property real surfaceOpacity: root.effectiveSurfaceColor.a
    readonly property bool shadowEnabled: !root.chromeless && root.surfaceOpacity > 0 && Theme.elevationEnabled && SettingsData.barElevationEnabled
    readonly property string autoBarShadowDirection: root.controller.edge
    readonly property string effectiveShadowDirection: Theme.elevationLightDirection === "autoBar" ? autoBarShadowDirection : Theme.elevationLightDirection
    readonly property real currentSurfaceRadius: Math.max(0, motion.currentTopLeftRadius, motion.currentBottomLeftRadius)
    readonly property color notificationAccentColor: {
        if (!root.controller.notificationActive)
            return "transparent";
        if (root.notificationModel.critical)
            return Theme.error;
        if (root.notificationModel.important)
            return Theme.warning;
        return "transparent";
    }

    signal scrollWheel(var wheel)

    readonly property alias inputMaskItem: inputEnvelope
    readonly property alias fittsStripItem: fittsStrip
    readonly property alias surfaceMotion: motion
    readonly property bool motionRunning: motion.running
    onMotionRunningChanged: {
        if (!motionRunning && requestedWindow)
            openWindow.restart();
        if (motionRunning) {
            motionStartBounds = Qt.rect(currentVisualX, currentVisualY, currentVisualWidth, currentVisualHeight);
            return;
        }
        controller.releaseIdleVisuals();
    }
    readonly property real springTimeConstantMs: motion.timeConstantMs
    property real trackedCrossExtent: 0
    property real fadeCompactCross: 48
    property real fadeExpandedCross: 352
    property rect motionStartBounds: Qt.rect(0, 0, 0, 0)
    readonly property bool isVertical: root.controller.isVertical
    readonly property bool farEdge: root.controller.edge === "bottom" || root.controller.edge === "right"
    readonly property real alongExtent: root.isVertical ? root.height : root.width
    readonly property real crossExtent: root.isVertical ? root.width : root.height
    readonly property bool snapsAlongEdges: root.notch || (root.embedded && !root.chromeless)
    readonly property real dpr: CompositorService.getScreenScale(root.effectiveScreen)
    readonly property real motionAlong: isVertical ? motion.currentHeight : motion.currentWidth
    readonly property real motionAlongPos: (alongExtent - motionAlong) / 2 + motion.currentOffsetAlong
    readonly property real currentAlongPos: snapsAlongEdges ? Theme.snap(motionAlongPos, dpr) : motionAlongPos
    readonly property real currentVisualAlong: snapsAlongEdges ? Theme.snap(motionAlongPos + motionAlong, dpr) - currentAlongPos : motionAlong
    readonly property real currentVisualWidth: isVertical ? motion.currentWidth : currentVisualAlong
    readonly property real currentVisualHeight: isVertical ? currentVisualAlong : motion.currentHeight
    readonly property real currentVisualCross: isVertical ? motion.currentWidth : motion.currentHeight
    readonly property real currentCrossPos: farEdge ? crossExtent - motion.currentOffsetCross - currentVisualCross : motion.currentOffsetCross
    readonly property real currentVisualX: isVertical ? currentCrossPos : currentAlongPos
    readonly property real currentVisualY: isVertical ? currentAlongPos : currentCrossPos
    readonly property real targetAlongPos: Math.round((alongExtent - (isVertical ? motion.targetHeight : motion.targetWidth)) / 2 + motion.targetOffsetAlong)
    readonly property real targetCrossPos: farEdge ? crossExtent - Math.round(motion.targetOffsetCross) - (isVertical ? motion.targetWidth : motion.targetHeight) : Math.round(motion.targetOffsetCross)
    readonly property real targetVisualX: isVertical ? targetCrossPos : targetAlongPos
    readonly property real targetVisualY: isVertical ? targetAlongPos : targetCrossPos
    readonly property real targetScreenX: targetVisualX + root.hostOriginX
    readonly property real targetScreenY: targetVisualY + root.hostOriginY
    readonly property real targetVisualWidth: motion.targetWidth
    readonly property real currentScreenX: currentVisualX + root.hostOriginX
    readonly property real currentScreenY: currentVisualY + root.hostOriginY
    readonly property real targetVisualHeight: motion.targetHeight
    readonly property real targetVisualAlong: isVertical ? motion.targetHeight : motion.targetWidth
    readonly property real morphProgress: {
        const span = fadeExpandedCross - fadeCompactCross;
        if (Math.abs(span) < 1)
            return controller.expanded ? 1 : 0;
        return Math.max(0, Math.min(1, (currentVisualCross - fadeCompactCross) / span));
    }

    readonly property QtObject resizeGeometry: QtObject {
        readonly property real renderedX: root.currentScreenX
        readonly property real renderedY: root.currentScreenY

        function screenXFor(width) {
            if (!root.isVertical)
                return Math.round((root.alongExtent - width) / 2 + (root.embedded ? root.clampAnchored(root.controller.alongOffset + root.anchorAlong, width) : motion.targetOffsetAlong)) + root.hostOriginX;
            const cross = Math.round(motion.targetOffsetCross);
            return (root.farEdge ? root.crossExtent - cross - width : cross) + root.hostOriginX;
        }
    }

    function openAfterCollapse(windowName) {
        requestedWindow = windowName;
        controller.requestCollapse();
        openWindow.restart();
    }

    DeferredAction {
        id: openWindow

        onTriggered: {
            if (root.motionRunning || root.controller.expanded)
                return;
            const requested = root.requestedWindow;
            root.requestedWindow = "";
            switch (requested) {
            case "settings":
                PopoutService.focusOrToggleSettings();
                break;
            case "accounts":
                PopoutService.openSettingsWithTab("user_accounts");
                break;
            case "colorPicker":
                PopoutService.showColorPicker();
                break;
            }
        }
    }

    function descriptorCross(target) {
        return root.isVertical ? target.width : target.height;
    }

    function descriptorAlong(target) {
        return root.isVertical ? target.height : target.width;
    }

    // Free mode re-centres the target on the anchor and clamps it on screen, so the centre glides
    // between the compact and expanded positions instead of pinning the top-left corner.
    function clampFree(value, size, extent) {
        const limit = extent - size - root.freeMargin;
        if (limit <= root.freeMargin)
            return Math.round((extent - size) / 2);
        return Math.round(Math.max(root.freeMargin, Math.min(value, limit)));
    }

    // A compact face keeps its slot right up to the band edge; only a sheet that outgrows the slot keeps a margin.
    function clampAnchored(offset, size) {
        const margin = size > root.descriptorAlong(root.controller.compactTarget) ? Theme.spacingS : 0;
        const centre = root.alongExtent / 2;
        const low = root.bandAlongStart + margin + size / 2 - centre;
        const high = root.bandAlongEnd - margin - size / 2 - centre;
        return low > high ? (root.bandAlongStart + root.bandAlongEnd) / 2 - centre : Math.max(low, Math.min(offset, high));
    }

    function resolveTarget(target) {
        if (root.embedded && !root.freeMode) {
            const inset = target.sheet ? root.nearInset : 0;
            return Object.assign({}, target, {
                "offsetAlong": root.clampAnchored(target.offsetAlong + root.anchorAlong, root.descriptorAlong(target)),
                "width": target.width + (root.isVertical ? inset : 0),
                "height": target.height + (root.isVertical ? 0 : inset)
            });
        }
        if (!root.freeMode)
            return target;
        const x = root.clampFree(root.anchor.x - target.width / 2, target.width, root.width);
        const y = root.clampFree(root.anchor.y - target.height / 2, target.height, root.height);
        return Object.assign({}, target, {
            "offsetAlong": root.isVertical ? y + target.height / 2 - root.height / 2 : x + target.width / 2 - root.width / 2,
            "offsetCross": root.isVertical ? x : y
        });
    }

    function applyTarget(seedVelocity) {
        root.targetPending = controller.expanded && !root.hostReady;
        if (root.targetPending)
            return;
        if (controller.expanded)
            fadeExpandedCross = root.descriptorCross(root.resolveTarget(controller.expandedTarget));
        else
            fadeCompactCross = root.descriptorCross(controller.compactTarget);
        if (motion.running)
            root.unionMotionStartBounds();
        const seed = seedVelocity ?? root.flingSeed;
        root.flingSeed = null;
        motion.setTarget(root.resolveTarget(controller.targetDescriptor), seed);
        if (!motion.running)
            root.controller.releaseIdleVisuals();
    }

    // Neighbours re-layout without animation, so a settled collapsed pill snaps with them; a size change or an open sheet springs.
    function syncAnchor() {
        if (!root.freeMode && !root.embedded)
            return;
        if (root.anchorSnaps) {
            motion.snapTo(root.resolveTarget(controller.targetDescriptor));
            return;
        }
        // targetDescriptor may not have updated yet when the slot resizes, compactTarget has.
        const compact = root.resolveTarget(controller.compactTarget);
        const settledCompact = root.embedded && !motion.running && !controller.expanded && compact.width === motion.targetWidth && compact.height === motion.targetHeight;
        if (settledCompact) {
            motion.snapTo(compact);
            return;
        }
        root.applyTarget();
    }

    onAnchorChanged: root.syncAnchor()
    onAnchorAlongChanged: root.syncAnchor()
    onAlongExtentChanged: root.syncAnchor()
    onBandAlongStartChanged: root.syncAnchor()
    onBandAlongEndChanged: root.syncAnchor()

    function unionMotionStartBounds() {
        const b = root.motionStartBounds;
        const left = Math.min(b.x, root.currentVisualX);
        const top = Math.min(b.y, root.currentVisualY);
        const right = Math.max(b.x + b.width, root.currentVisualX + root.currentVisualWidth);
        const bottom = Math.max(b.y + b.height, root.currentVisualY + root.currentVisualHeight);
        root.motionStartBounds = Qt.rect(left, top, right - left, bottom - top);
    }

    // Without a face to swap to, a right-click falls through to the bar's own right-click action.
    function acceptsClick(button) {
        return button !== Qt.RightButton || root.controller.mediaFaceToggleAvailable;
    }

    function handleClick(button) {
        SettingsData.recordBarInteraction(root.effectiveScreen, root.controller.barConfig?.id);
        if (button === Qt.RightButton)
            root.controller.toggleMediaFace();
        else
            root.controller.requestToggle(true);
    }

    function requestActivityFocus() {
        return contentHost.requestActivityFocus();
    }

    Component.onCompleted: {
        trackedCrossExtent = crossExtent;
        fadeCompactCross = root.descriptorCross(controller.compactTarget);
        fadeExpandedCross = root.descriptorCross(root.resolveTarget(controller.expandedTarget));
        motion.snapTo(root.resolveTarget(controller.targetDescriptor));
    }

    // On a far edge the cross coordinate is measured from the far side, so a host resize
    // shifts everything already in flight by the same delta.
    onCrossExtentChanged: {
        const delta = crossExtent - trackedCrossExtent;
        trackedCrossExtent = crossExtent;
        if (root.freeMode) {
            root.syncAnchor();
            return;
        }
        if (!farEdge || !motion.running || delta === 0)
            return;
        const b = motionStartBounds;
        motionStartBounds = isVertical ? Qt.rect(b.x + delta, b.y, b.width, b.height) : Qt.rect(b.x, b.y + delta, b.width, b.height);
    }

    Connections {
        target: root.controller

        function onTargetDescriptorChanged() {
            root.applyTarget();
        }

        function onExpandedChanged() {
            if (!root.controller.expanded)
                return;
            openWindow.cancel();
            root.requestedWindow = "";
        }
    }

    VectorSpringMotion {
        id: motion

        reducedMotion: root.reducedMotion
        stiffness: root.springStiffness
        damping: root.springDamping
        mass: root.springMass
    }

    // Host and surface are band-sized when embedded; the sheet grows past them after the pill was hovered at rest.
    PointerOverflowMarker {}

    // Frozen start/target union so the Wayland mask is not rewritten every spring frame.
    Item {
        id: inputEnvelope

        readonly property real overshootBudget: {
            if (!motion.running)
                return 0;
            const zeta = motion.damping / (2 * Math.sqrt(Math.max(1, motion.stiffness * motion.mass)));
            if (zeta >= 1)
                return 0;
            const spanX = Math.abs(root.targetVisualX - root.motionStartBounds.x);
            const spanY = Math.abs(root.targetVisualY - root.motionStartBounds.y);
            const spanW = Math.abs(motion.targetWidth - root.motionStartBounds.width);
            const spanH = Math.abs(motion.targetHeight - root.motionStartBounds.height);
            const span = Math.max(spanX, spanY, spanW, spanH);
            return Math.ceil(span * Math.exp(-Math.PI * zeta / Math.sqrt(1 - zeta * zeta)));
        }

        x: (motion.running ? Math.min(root.motionStartBounds.x, root.targetVisualX) : root.targetVisualX) - overshootBudget
        y: (motion.running ? Math.min(root.motionStartBounds.y, root.targetVisualY) : root.targetVisualY) - overshootBudget
        width: (motion.running ? Math.max(root.motionStartBounds.x + root.motionStartBounds.width, root.targetVisualX + motion.targetWidth) : root.targetVisualX + motion.targetWidth) + overshootBudget - x
        height: (motion.running ? Math.max(root.motionStartBounds.y + root.motionStartBounds.height, root.targetVisualY + motion.targetHeight) : root.targetVisualY + motion.targetHeight) + overshootBudget - y
    }

    Loader {
        anchors.fill: island
        z: island.z - 1
        active: root.shadowEnabled && !root.embedded
        sourceComponent: shadowComponent
    }

    MorphSurface {
        id: island
        motion: root.surfaceMotion

        x: root.currentVisualX
        y: root.currentVisualY
        width: root.currentVisualWidth
        height: root.currentVisualHeight
        // Embedded, the band already paints the in-band strip; overhangFill draws the rest, so a translucent band never double-alphas.
        color: root.embedded ? "transparent" : root.effectiveSurfaceColor
        border.width: root.notificationAccentColor !== "transparent" ? 1.5 : root.embedded ? 0 : (root.highContrast ? 2 : (root.popupStyled && !root.notch ? BlurService.borderWidth : 0))
        border.color: root.notificationAccentColor !== "transparent" ? root.notificationAccentColor : (root.highContrast ? Theme.outlineStrong : (root.popupStyled && !root.notch ? BlurService.borderColor : "transparent"))

        Behavior on color {
            ColorAnimation {
                duration: root.reducedMotion ? 0 : Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: root.reducedMotion ? 0 : Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: root.compactBackground && opacity > 0
            opacity: 1 - root.morphProgress
            color: root.compactBackgroundColor
            topLeftRadius: parent.topLeftRadius
            topRightRadius: parent.topRightRadius
            bottomLeftRadius: parent.bottomLeftRadius
            bottomRightRadius: parent.bottomRightRadius
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => mouse.accepted = root.acceptsClick(mouse.button)
            enabled: !root.controller.expanded || !root.controller.activityOwnsBlankClicks
            onClicked: mouse => root.handleClick(mouse.button)
            onWheel: wheel => {
                if (root.controller.expanded) {
                    wheel.accepted = false;
                    return;
                }
                root.scrollWheel(wheel);
                wheel.accepted = true;
            }
        }

        IslandContentHost {
            id: contentHost

            controller: root.controller
            surfaceColor: root.effectiveSurfaceColor
            freeMode: root.freeMode
            compactFaceOverride: root.compactFaceOverride
            resolveTarget: target => root.resolveTarget(target)
            expandedInset: root.embedded && !root.freeMode ? root.nearInset : 0
            islandX: root.currentVisualX
            islandY: root.currentVisualY
            hostWidth: root.width
            hostHeight: root.height
            springTimeConstantMs: root.springTimeConstantMs
            morphProgress: root.morphProgress
            expanded: root.controller.expanded
            pointerInside: root.controller.pointerInside
            activityId: root.controller.activeActivity
            homeCompactComponent: compactHomeComponent
            homeExpandedComponent: expandedHomeComponent
            mediaCompactComponent: compactMediaComponent
            mediaExpandedComponent: expandedMediaComponent
            launcherCompactComponent: compactLauncherComponent
            launcherExpandedComponent: expandedLauncherComponent
            controlCenterCompactComponent: compactControlCenterComponent
            controlCenterExpandedComponent: expandedControlCenterComponent
            wallpaperCompactComponent: compactWallpaperComponent
            wallpaperExpandedComponent: expandedWallpaperComponent
            weatherCompactComponent: compactWeatherComponent
            weatherExpandedComponent: expandedWeatherComponent
            wellbeingCompactComponent: compactWellbeingComponent
            wellbeingExpandedComponent: expandedWellbeingComponent
            systemCompactComponent: compactSystemComponent
            systemExpandedComponent: expandedSystemComponent
            notificationCompactComponent: compactNotificationComponent
            notificationExpandedComponent: expandedNotificationComponent
            notificationCenterCompactComponent: compactNotificationCenterComponent
            notificationCenterExpandedComponent: expandedNotificationCenterComponent
            clipboardCompactComponent: compactClipboardComponent
            clipboardExpandedComponent: expandedClipboardComponent
            powerMenuCompactComponent: compactPowerMenuComponent
            powerMenuExpandedComponent: expandedPowerMenuComponent
        }

        HoverHandler {
            id: islandHover

            onHoveredChanged: root.updateFittsPointerInside()
        }
    }

    function updateFittsPointerInside() {
        root.controller.updatePointerInside(islandHover.hovered || stripHover.hovered);
    }

    // Fitts zone from the island edge to the screen edge — hover/click count as island.
    // Bounds follow the spring target, never the per-frame value, so the Wayland mask is not
    // rewritten every frame and the strip never shrinks out from under the cursor mid-open.
    Item {
        id: fittsStrip

        readonly property real targetCross: root.isVertical ? motion.targetWidth : motion.targetHeight
        readonly property real span: Math.max(root.descriptorAlong(root.controller.compactTarget), root.isVertical ? motion.targetHeight : motion.targetWidth)
        readonly property real edgeGap: root.farEdge ? Math.max(0, root.crossExtent - (root.targetCrossPos + targetCross)) : Math.max(0, root.targetCrossPos)
        readonly property real alongPos: Math.round((root.alongExtent - span) / 2 + motion.targetOffsetAlong)
        readonly property real crossPos: root.farEdge ? root.targetCrossPos + targetCross : 0

        x: root.isVertical ? crossPos : alongPos
        y: root.isVertical ? alongPos : crossPos
        width: root.isVertical ? edgeGap : span
        height: root.isVertical ? span : edgeGap
        visible: !root.freeMode && !root.embedded && edgeGap > 0 && span > 0

        HoverHandler {
            id: stripHover

            onHoveredChanged: root.updateFittsPointerInside()
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: mouse => mouse.accepted = root.acceptsClick(mouse.button)
            onClicked: mouse => root.handleClick(mouse.button)
            onWheel: wheel => {
                root.scrollWheel(wheel);
                wheel.accepted = true;
            }
        }
    }

    // crossExtent is the band here, so the overhang is how far the sheet has left the bar.
    readonly property real embeddedOverhang: !root.embedded || root.chromeless ? 0 : Math.max(0, root.farEdge ? -(root.isVertical ? root.currentVisualX : root.currentVisualY) : (root.isVertical ? root.currentVisualX + root.currentVisualWidth : root.currentVisualY + root.currentVisualHeight) - root.crossExtent)
    readonly property real joinRadius: root.notch ? root.notchRadius : Math.min(Theme.connectedCornerRadius, root.embeddedOverhang)
    // Depth is capped so the flare never passes the pill's far corner; the slider still drives the along radius.
    readonly property real joinCrossRadius: root.notch ? Math.max(0, Math.min(root.joinRadius, root.controller.compactFaceThickness - Math.min(root.controller.compactFaceThickness / 2, root.controller.pillRadius))) : root.joinRadius
    // Where the join corners sit: the band's inner edge when embedded, the screen edge for a notch.
    readonly property real joinCross: root.notch === root.farEdge ? root.crossExtent : 0
    readonly property var joinCorners: joinChrome.item ? [joinChrome.item.leadingCorner, joinChrome.item.trailingCorner] : []

    // A Loader, not visible:, so islands and dots skip these per-frame motion bindings.
    Loader {
        id: joinChrome

        active: (root.embedded && !root.chromeless) || root.notch
        z: island.z - 1
        sourceComponent: Item {
            readonly property alias leadingCorner: leadingCorner
            readonly property alias trailingCorner: trailingCorner

            Loader {
                active: root.embedded
                sourceComponent: Item {
                    id: overhangClip
                    readonly property real shadowPad: root.shadowEnabled ? Theme.elevationRenderPadding(Theme.elevationLevel2, root.effectiveShadowDirection, Theme.spacingXS, Theme.spacingS, Theme.spacingL) : 0

                    visible: root.embeddedOverhang > 0
                    clip: true
                    x: root.isVertical ? (root.farEdge ? -root.embeddedOverhang - shadowPad : root.crossExtent) : -shadowPad
                    y: root.isVertical ? -shadowPad : (root.farEdge ? -root.embeddedOverhang - shadowPad : root.crossExtent)
                    width: root.isVertical ? root.embeddedOverhang + shadowPad : root.width + 2 * shadowPad
                    height: root.isVertical ? root.height + 2 * shadowPad : root.embeddedOverhang + shadowPad

                    Loader {
                        anchors.fill: overhang
                        active: root.shadowEnabled
                        sourceComponent: shadowComponent
                    }

                    MorphSurface {
                        id: overhang

                        motion: root.surfaceMotion
                        x: root.currentVisualX - overhangClip.x
                        y: root.currentVisualY - overhangClip.y
                        width: root.currentVisualWidth
                        height: root.currentVisualHeight
                        color: root.effectiveSurfaceColor
                    }
                }
            }

            GothCorner {
                id: leadingCorner

                visible: root.joinRadius > 0 && root.joinCrossRadius > 0
                radiusX: root.isVertical ? root.joinCrossRadius : root.joinRadius
                radiusY: root.isVertical ? root.joinRadius : root.joinCrossRadius
                color: root.effectiveSurfaceColor
                corner: root.isVertical ? (root.farEdge ? "topLeft" : "topRight") : (root.farEdge ? "topLeft" : "bottomLeft")
                x: root.isVertical ? (root.farEdge ? root.joinCross - radiusX : root.joinCross) : root.currentVisualX - radiusX
                y: root.isVertical ? root.currentVisualY - radiusY : (root.farEdge ? root.joinCross - radiusY : root.joinCross)
            }

            GothCorner {
                id: trailingCorner

                visible: root.joinRadius > 0 && root.joinCrossRadius > 0
                radiusX: root.isVertical ? root.joinCrossRadius : root.joinRadius
                radiusY: root.isVertical ? root.joinRadius : root.joinCrossRadius
                color: root.effectiveSurfaceColor
                corner: root.isVertical ? (root.farEdge ? "bottomLeft" : "bottomRight") : (root.farEdge ? "topRight" : "bottomRight")
                x: root.isVertical ? (root.farEdge ? root.joinCross - radiusX : root.joinCross) : root.currentVisualX + root.currentVisualWidth
                y: root.isVertical ? root.currentVisualY + root.currentVisualHeight : (root.farEdge ? root.joinCross - radiusY : root.joinCross)
            }
        }
    }

    Component {
        id: shadowComponent

        ElevationShadow {
            level: Theme.elevationLevel2
            direction: root.effectiveShadowDirection
            fallbackOffset: Theme.spacingXS
            targetColor: "transparent"
            topLeftRadius: island.topLeftRadius
            topRightRadius: island.topRightRadius
            bottomLeftRadius: island.bottomLeftRadius
            bottomRightRadius: island.bottomRightRadius
        }
    }

    Component {
        id: compactHomeComponent

        HomeCompact {
            controller: root.controller
            systemModel: root.systemModel
        }
    }

    Component {
        id: expandedHomeComponent

        HomeExpanded {
            controller: root.controller
            resizeGeometry: root.resizeGeometry
        }
    }

    Component {
        id: compactMediaComponent

        MediaCompact {
            mediaModel: root.mediaModel
            controller: root.controller
        }
    }

    Component {
        id: expandedMediaComponent

        MediaExpanded {
            controller: root.controller
            resizeGeometry: root.resizeGeometry
        }
    }

    Component {
        id: compactLauncherComponent

        DestinationCompact {
            id: launcherFace

            readonly property var launcherEntry: SettingsData.barWidgetEntry(root.controller.barConfig, "launcherButton")

            function opt(key) {
                return SettingsData.widgetOption("launcherButton", launcherFace.launcherEntry, key);
            }

            controller: root.controller
            activityId: "launcher"
            label: I18n.tr("Launcher", "island compact face: launcher label")
            leading: LauncherLogo {
                id: faceLogo

                mode: launcherFace.opt("launcherLogoMode")
                size: Math.max(12, Theme.iconSizeSmall + launcherFace.opt("launcherLogoSizeOffset"))
                appsIconColor: faceLogo.resolvedColor
                colorOverride: launcherFace.opt("launcherLogoColorOverride") || "surface"
                brightness: launcherFace.opt("launcherLogoBrightness")
                contrast: launcherFace.opt("launcherLogoContrast")
                customPath: launcherFace.opt("launcherLogoCustomPath")
                fallbackToApps: true
            }
        }
    }

    Component {
        id: expandedLauncherComponent

        LauncherExpanded {
            controller: root.controller
            launcherController: root.launcherController
            transientSurfaceTracker: root.launcherTransientSurfaceTracker
            effectiveScreen: root.effectiveScreen
            alignedX: root.targetScreenX
            alignedY: root.targetScreenY
        }
    }

    Component {
        id: compactControlCenterComponent

        DestinationCompact {
            controller: root.controller
            activityId: "controlcenter"
            iconName: "tune"
            label: I18n.tr("Control Center", "island compact face: control center label")
        }
    }

    Component {
        id: expandedControlCenterComponent

        ControlCenterExpanded {
            controller: root.controller
            onWindowRequested: windowName => root.openAfterCollapse(windowName)
            effectiveScreen: root.effectiveScreen
            alignedX: root.targetScreenX
            alignedY: root.targetScreenY
            alignedWidth: root.targetVisualWidth
            alignedHeight: root.targetVisualHeight
            resizeGeometry: root.resizeGeometry
        }
    }

    Component {
        id: compactWallpaperComponent

        DestinationCompact {
            controller: root.controller
            activityId: "wallpaper"
            iconName: "wallpaper"
            label: I18n.tr("Wallpaper", "island compact face: wallpaper picker label")
        }
    }

    Component {
        id: expandedWallpaperComponent

        WallpaperExpanded {
            controller: root.controller
            resizeGeometry: root.resizeGeometry
            effectiveScreen: root.effectiveScreen
        }
    }

    Component {
        id: compactWeatherComponent

        DestinationCompact {
            controller: root.controller
            activityId: "weather"
            iconName: "partly_cloudy_day"
            label: I18n.tr("Weather", "island compact face: weather label")
        }
    }

    Component {
        id: expandedWeatherComponent

        WeatherExpanded {
            controller: root.controller
            resizeGeometry: root.resizeGeometry
        }
    }

    Component {
        id: compactWellbeingComponent

        DestinationCompact {
            controller: root.controller
            activityId: "wellbeing"
            iconName: "digital_wellbeing"
            label: I18n.tr("Screen time", "dashboard card and settings card title, time spent in apps")
        }
    }

    Component {
        id: expandedWellbeingComponent

        WellbeingExpanded {
            controller: root.controller
            resizeGeometry: root.resizeGeometry
        }
    }

    Component {
        id: compactSystemComponent

        Loader {
            sourceComponent: root.systemModel.levelActivity ? compactSystemLevelComponent : compactSystemStateComponent
        }
    }

    Component {
        id: compactSystemLevelComponent

        SystemLevelCompact {
            systemModel: root.systemModel
            isVertical: root.isVertical
            iconSize: root.controller.compactIconSize
        }
    }

    Component {
        id: compactSystemStateComponent

        SystemStateCompact {
            systemModel: root.systemModel
            controller: root.controller
        }
    }

    Component {
        id: expandedSystemComponent

        SystemLevelExpanded {
            systemModel: root.systemModel
        }
    }

    Component {
        id: compactNotificationComponent

        NotificationCompact {
            notificationModel: root.notificationModel
            controller: root.controller
            dense: root.controller.compactDense
            iconSize: root.controller.compactIconSize
        }
    }

    Component {
        id: compactNotificationCenterComponent

        DestinationCompact {
            id: notificationCenterFace

            readonly property int unreadCount: NotificationService.notifications.length

            controller: root.controller
            activityId: "notificationcenter"
            iconName: notificationCenterFace.unreadCount > 0 ? "notifications_active" : "notifications"
            label: notificationCenterFace.unreadCount > 0 ? I18n.tr("%1 notifications", "island compact face: unread notification count").arg(notificationCenterFace.unreadCount) : I18n.tr("Notifications", "island compact face: notification center label")
        }
    }

    Component {
        id: expandedNotificationCenterComponent

        NotificationCenterExpanded {
            controller: root.controller
            resizeGeometry: root.resizeGeometry
        }
    }

    Component {
        id: compactClipboardComponent

        DestinationCompact {
            controller: root.controller
            activityId: "clipboard"
            iconName: "content_paste"
            label: I18n.tr("Clipboard")
        }
    }

    Component {
        id: expandedClipboardComponent

        ClipboardExpanded {
            controller: root.controller
            transientSurfaceTracker: root.launcherTransientSurfaceTracker
            effectiveScreen: root.effectiveScreen
            alignedX: root.targetScreenX
            alignedY: root.targetScreenY
        }
    }

    Component {
        id: compactPowerMenuComponent

        DestinationCompact {
            controller: root.controller
            activityId: "powermenu"
            iconName: "power_settings_new"
            label: I18n.tr("Power menu", "island compact face: power menu label")
        }
    }

    Component {
        id: expandedPowerMenuComponent

        PowerMenuExpanded {
            controller: root.controller
        }
    }

    Component {
        id: expandedNotificationComponent

        NotificationExpanded {
            notificationModel: root.notificationModel
        }
    }
}
