pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import Quickshell.Wayland
import qs.Modals.DLauncherV2 as DLauncher
import qs.Modules.DBar
import qs.Modules.DIsland.Activities
import qs.Services
import qs.Widgets
import "../../Common/LayoutResolver.js" as Resolver

Item {
    id: root

    required property var barConfig
    required property var screen
    required property var hostWindow
    required property string barId
    property real originOffsetX: 0
    property real originOffsetY: 0
    // Set by FrameBarHost; a frame-hosted body cannot see its own slot offset.
    property real hostOffsetX: 0
    property real hostOffsetY: 0
    property string chrome: "own"
    readonly property bool embedded: root.chrome !== "own"
    readonly property bool connectedChrome: root.chrome === "none"
    property real bandThickness: 0
    // The visible band along the bar, in host coordinates; a percent-length or padded bar is shorter than its window.
    property real bandAlongStart: 0
    property real bandAlongEnd: root.isVertical ? root.height : root.width
    // The frame window never resizes for the sheet, whatever chrome the body wears.
    property bool frameHosted: false
    property color bandColor: Theme.hostSurface
    property Item anchorItem: null
    property Item slotItem: null
    property Item barBody: null
    property var leadingSectionRect: null
    property var centerSectionRect: null
    property var trailingSectionRect: null
    readonly property int hostLayer: root.hostWindow?.dBarLayer ?? WlrLayer.Top
    property point anchor
    property bool anchorSnaps: false
    property real freeScale: 1
    property real freeOpacity: 1

    readonly property alias islandController: controller
    readonly property alias surface: surface
    readonly property int launcherResultCount: launcherController.flatModel?.length ?? 0
    readonly property var inputMaskItem: surface.inputMaskItem
    readonly property var fittsStripItem: root.embedded ? null : surface.fittsStripItem
    readonly property bool motionRunning: surface.motionRunning
    readonly property rect motionStartBounds: surface.motionStartBounds
    readonly property real targetAlongPos: surface.targetAlongPos
    readonly property real currentAlongPos: surface.currentAlongPos
    readonly property real currentVisualAlong: surface.currentVisualAlong
    readonly property real targetVisualAlong: surface.targetVisualAlong
    readonly property real currentVisualX: surface.currentVisualX
    readonly property real currentVisualY: surface.currentVisualY
    readonly property real currentVisualWidth: surface.currentVisualWidth
    readonly property real currentVisualHeight: surface.currentVisualHeight
    readonly property real currentSurfaceRadius: surface.currentSurfaceRadius
    readonly property color surfaceColor: surface.surfaceColor
    readonly property real surfaceOpacity: surface.surfaceOpacity
    readonly property bool inputSuspended: controller.inputSuspended
    readonly property bool expanded: controller.expanded
    readonly property bool transientActive: controller.transientActive
    // Held from expand until the collapse spring settles, so compact-to-compact morphs never resize the bar window.
    property bool sheetOut: false
    readonly property bool surfaceFits: (root.isVertical ? root.windowWidth : root.windowHeight) >= root.hostThickness - 1
    // A free host lifts to the whole output for the sheet; the expand waits for that size so no frame of the morph is clipped.
    property bool hostLifted: true
    readonly property bool hostReady: root.freeMode ? root.hostLifted : (!root.embedded || root.frameHosted || root.surfaceFits)
    // Layer surfaces glitch when they resize under a moving sheet: edit room waits for a frame at the grown size, and the grown size outlives the shrink spring.
    readonly property bool surfaceResizes: !root.freeMode && !root.frameHosted
    readonly property int editSurfaceHeight: controller.editSurfaceHeight
    property int heldEditSurfaceHeight: 0
    readonly property bool editRoomWaiting: controller.editRoom > 0 && !controller.editRoomGranted
    onEditSurfaceHeightChanged: {
        if (root.editSurfaceHeight >= root.heldEditSurfaceHeight) {
            root.heldEditSurfaceHeight = root.editSurfaceHeight;
            return;
        }
        Qt.callLater(root.releaseEditSurface);
    }
    onEditRoomWaitingChanged: {
        if (root.editRoomWaiting && !root.surfaceResizes)
            controller.editRoomGranted = true;
    }

    function releaseEditSurface() {
        if (!surface.motionRunning)
            root.heldEditSurfaceHeight = root.editSurfaceHeight;
    }
    readonly property real compactTargetSize: surface.descriptorAlong(controller.compactTarget)
    // Summed by hand so every ancestor offset is a binding dependency; mapToItem goes stale when a section re-centres.
    readonly property real slotCentre: {
        let item = root.slotItem;
        if (!root.embedded || !item || !root.anchorItem)
            return NaN;
        let pos = root.isVertical ? item.height / 2 : item.width / 2;
        for (; item && item !== root.anchorItem; item = item.parent)
            pos += root.isVertical ? item.y : item.x;
        return item ? pos : NaN;
    }
    readonly property real anchorAlong: isNaN(root.slotCentre) ? 0 : root.slotCentre - (root.isVertical ? root.height : root.width) / 2
    onExpandedChanged: {
        if (root.dotMode && root.expanded && !controller.transientActive && root.setting("islandNotificationBadgeClearOnOpen"))
            NotificationService.markNotificationsSeen();
        if (root.expanded) {
            root.sheetOut = true;
            root.closeSameEdgeSurfaces();
        } else if (!root.motionRunning && surface.surfaceMotion.matchesTarget(surface.resolveTarget(controller.compactTarget))) {
            // Already compact, so no step will come to clear the latch.
            root.sheetOut = false;
        }
        root.publishSurface();
    }
    onMotionRunningChanged: root.publishSurface()
    onConnectedChromeChanged: root.publishSurface()
    onEdgeChanged: root.publishSurface()

    signal scrollWheel(var wheel)

    function setting(key) {
        return SettingsData.islandSetting(root.barConfig, key);
    }

    readonly property var islandMetrics: Resolver.islandMetrics(SettingsData.islandSettings(root.barConfig), SettingsData.islandDefaultsFor(root.barConfig))
    readonly property bool freeMode: SettingsData.islandFreePlacement(root.barConfig)
    readonly property bool dotMode: SettingsData.isDotBarConfig(root.barConfig)
    readonly property real dotSize: Math.max(24, Math.min(160, root.setting("islandFreeSize")))
    readonly property real freeMargin: Math.max(0, Math.min(64, root.setting("islandFreeEdgeMargin")))
    readonly property var bandFit: BarMetrics.islandBandFit(root.bandThickness, root.islandMetrics.gap)
    readonly property int compactThickness: root.embedded ? root.bandFit.compact : root.dotMode ? Math.max(24, Math.min(72, root.dotSize)) : root.islandMetrics.compact
    readonly property string screenName: root.screen?.name ?? ""
    readonly property bool floating: root.setting("islandFloating")
    readonly property bool notch: !root.embedded && !root.freeMode && !root.dotMode && root.setting("islandNotch")
    readonly property bool usesOverlayLayer: root.dotMode || CompositorService.framePeerSurfacesUseOverlayForScreen(root.screen) || LayerShell.envUsesOverlay("DMS_DANKISLAND_LAYER", root.setting("islandUseOverlayLayer"))
    // A free island's position only picks the orientation; a dot is always a circle.
    readonly property bool isVertical: !root.dotMode && SettingsData.islandVertical(root.barConfig)
    readonly property string edge: root.freeMode ? (root.isVertical ? "left" : "top") : SettingsData.islandEdge(root.barConfig)
    readonly property bool farEdge: root.edge === "bottom" || root.edge === "right"
    readonly property real windowWidth: root.hostWindow?.width ?? 0
    readonly property real windowHeight: root.hostWindow?.height ?? 0
    readonly property real windowMarginLeft: root.hostWindow?.margins?.left ?? 0
    readonly property real windowMarginRight: root.hostWindow?.margins?.right ?? 0
    readonly property real windowMarginTop: root.hostWindow?.margins?.top ?? 0
    readonly property real windowMarginBottom: root.hostWindow?.margins?.bottom ?? 0
    readonly property int hostOriginX: root.freeMode ? 0 : (root.isVertical && root.farEdge ? Math.max(0, (root.screen?.width ?? 0) - root.windowWidth - root.windowMarginRight) : root.windowMarginLeft) + root.hostOffsetX + root.originOffsetX
    readonly property int hostOriginY: root.freeMode ? 0 : (!root.isVertical && root.farEdge ? Math.max(0, (root.screen?.height ?? 0) - root.windowHeight - root.windowMarginBottom) : root.windowMarginTop) + root.hostOffsetY + root.originOffsetY
    // Screen position of the host window's origin; section rects and mapToItem(null) are window-relative.
    readonly property real sectionOriginX: root.hostOriginX - root.originOffsetX - root.hostOffsetX
    readonly property real sectionOriginY: root.hostOriginY - root.originOffsetY - root.hostOffsetY
    readonly property int outerGap: root.freeMode ? 0 : root.embedded ? root.bandFit.gap : root.islandMetrics.gap
    // An embedded sheet starts inside the band; its content begins past the fold so nothing sits on the bar.
    readonly property int nearInset: root.embedded ? Math.max(0, Math.round(root.bandThickness) - root.outerGap) : 0
    readonly property real crossInsetStart: root.freeMode ? 0 : root.frameHosted ? ShellLayout.frameReservation(root.screen, root.isVertical ? "left" : "top") : root.isVertical ? root.windowMarginLeft : root.windowMarginTop
    readonly property real crossInsetEnd: root.freeMode ? 0 : root.frameHosted ? ShellLayout.frameReservation(root.screen, root.isVertical ? "right" : "bottom") : root.isVertical ? root.windowMarginRight : root.windowMarginBottom
    readonly property real alongInset: root.freeMode ? 0 : root.isVertical ? root.windowMarginTop + root.windowMarginBottom : root.windowMarginLeft + root.windowMarginRight
    readonly property int destinationMinHeight: 560
    readonly property int destinationMaxHeightLimit: 680
    readonly property int activityMinWidth: 320
    readonly property int activityMaxWidth: 736
    readonly property int screenMargin: 200
    readonly property int referenceScreenWidth: 1920
    readonly property int referenceScreenHeight: 1080
    readonly property int maxHoverDelay: 1000
    readonly property var springStiffnessRange: [100, 1200]
    readonly property var springDampingRange: [10, 100]
    readonly property var springMassRange: [0.25, 3]
    readonly property int destinationMaxHeight: Math.max(destinationMinHeight, Math.min(destinationMaxHeightLimit, (root.screen?.height ?? referenceScreenHeight) - screenMargin))
    readonly property int maxActivityHeight: Math.max(root.heldEditSurfaceHeight, controller.dashboardHeight, controller.controlCenterHeight, controller.launcherExpandedTarget.height, controller.clipboardExpandedTarget.height, controller.powerMenuExpandedTarget.height, destinationMaxHeight)
    readonly property int maxActivityWidth: Math.max(controller.dashboardMaxWidth, controller.controlCenterMaxWidth, controller.launcherExpandedTarget.width, controller.clipboardExpandedTarget.width, controller.powerMenuExpandedTarget.width, Math.min(activityMaxWidth, Math.max(activityMinWidth, (root.screen?.width ?? referenceScreenWidth) - screenMargin)))
    readonly property real shadowPadding: surface.shadowEnabled ? Theme.elevationRenderPadding(Theme.elevationLevel2, surface.effectiveShadowDirection, Theme.spacingXS, Theme.spacingS, Theme.spacingL) : 0
    readonly property int hostThickness: outerGap + nearInset + (root.isVertical ? maxActivityWidth : maxActivityHeight) + Theme.spacingS + shadowPadding
    readonly property real maximumAlongOffset: root.isVertical ? Math.max(0, (height - maxActivityHeight) / 2 - Theme.spacingS - shadowPadding) : Math.max(0, (width - maxActivityWidth) / 2 - Theme.spacingS - shadowPadding)
    readonly property bool scrollEnabled: root.barConfig?.scrollEnabled ?? true
    property bool keyboardFocusArmed: true
    readonly property int keyboardFocusPolicy: KeyboardFocus.keyboardFocus(controller.keyboardDismissRequested && root.keyboardFocusArmed && !controller.keyboardYielded, null)
    readonly property bool wantsFocusGrab: KeyboardFocus.wantsGrab(controller.keyboardDismissRequested && !controller.keyboardYielded, null)
    readonly property var transientFocusWindows: islandTransientSurfaces.focusWindows
    property var dismissWindow: null
    readonly property string registryKey: IslandHostRegistry.key(root.screen?.name, root.barId)
    property string registeredKey: ""

    property int popoutRevision: 0
    readonly property bool satelliteSurfacesOpen: {
        root.popoutRevision;
        const screenName = root.screen?.name;
        if (!screenName)
            return false;
        return !!PopoutManager.currentPopoutsByScreen[screenName] || !!ModalManager.currentModalsByScreen[screenName];
    }

    // A non-embedded island follows popout rules: whatever would close a bar popout on this screen collapses it.
    readonly property QtObject screenPopout: {
        root.popoutRevision;
        return PopoutManager.currentPopoutsByScreen[root.screenName] ?? null;
    }
    readonly property QtObject screenModal: {
        const modal = ModalManager.currentModalsByScreen[root.screenName] ?? null;
        return modal?.keepPopoutsOpen ? null : modal;
    }
    onScreenPopoutChanged: root.collapseForSurface(root.screenPopout)
    onScreenModalChanged: root.collapseForSurface(root.screenModal)

    function collapseForSurface(surfaceObject) {
        if (root.embedded || !surfaceObject)
            return;
        // Otherwise the notification would re-expand the sheet over the new surface when it ends.
        if (controller.notificationActive) {
            if (controller.suspendedExpanded) {
                controller.suspendedActivity = "";
                controller.suspendedExpanded = false;
            }
            return;
        }
        if (controller.expanded)
            controller.requestCollapse();
    }

    // A reopened popout (new trigger, or mid close animation) keeps its identity, so screenPopout never changes.
    function collapseForOpenedPopout() {
        if (root.screenPopout?.shouldBeVisible)
            root.collapseForSurface(root.screenPopout);
    }

    function requestKeyboardFocus() {
        if (!controller.keyboardDismissRequested) {
            keyboardActivationTimer.stop();
            keyboardFocusArmed = false;
            keyboardRearmTimer.restart();
            return;
        }
        keyboardRearmTimer.stop();
        keyboardFocusArmed = true;
        keyboardActivationTimer.restart();
    }

    function containsGlobalPoint(gx, gy, padding) {
        const pad = padding !== undefined ? padding : Theme.spacingL;
        const items = [surface.inputMaskItem, root.fittsStripItem];
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (!item || item.width <= 0 || item.height <= 0)
                continue;
            const topLeft = item.mapToItem(null, 0, 0);
            if (!topLeft)
                continue;
            const left = topLeft.x + root.sectionOriginX;
            const top = topLeft.y + root.sectionOriginY;
            if (gx >= left - pad && gx < left + item.width + pad && gy >= top - pad && gy < top + item.height + pad)
                return true;
        }
        return false;
    }

    function syncRegistration() {
        if (root.registeredKey === root.registryKey)
            return;
        if (root.registeredKey)
            IslandHostRegistry.unregister(root.registeredKey, root);
        root.registeredKey = root.registryKey;
        IslandHostRegistry.register(root.registeredKey, root);
    }

    onRegistryKeyChanged: syncRegistration()
    Component.onCompleted: syncRegistration()
    Component.onDestruction: IslandHostRegistry.unregister(root.registeredKey, root)

    function sameEdgeSlots() {
        const stored = ConnectedModeState.surfaceDescriptors[root.screenName] ?? {};
        return ["popout", "modal"].filter(slot => (stored[slot]?.visible ?? false) && stored[slot].barSide === root.edge);
    }
    function ownBarPopout() {
        const popout = PopoutManager.currentPopoutsByScreen[root.screenName];
        return popout?.shouldBeVisible && popout.sourceRegistration?.context?.barId === root.barId ? popout : null;
    }
    // Connected chrome: the frame SDF draws the body, so a popout or modal presented on the same edge would share its silhouette.
    readonly property bool sameEdgeSurfacePresented: root.embedded && !!root.screenName && (root.connectedChrome ? root.sameEdgeSlots().length > 0 : (root.popoutRevision, root.ownBarPopout() !== null))
    onSameEdgeSurfacePresentedChanged: {
        if (root.sameEdgeSurfacePresented && controller.expanded)
            controller.requestCollapse();
    }

    // The guard runs both ways, but only for deliberate opens: a hover peek or an arriving notification must not take the user's popout away.
    function closeSameEdgeSurfaces() {
        if (!root.embedded || !root.screenName || !controller.keyboardDismissRequested)
            return;
        if (!root.connectedChrome) {
            if (root.ownBarPopout())
                PopoutManager.closePopoutForScreen(root.screen);
            return;
        }
        const slots = root.sameEdgeSlots();
        if (slots.includes("popout"))
            PopoutManager.closePopoutForScreen(root.screen);
        const modal = slots.includes("modal") ? ModalManager.currentModalsByScreen[root.screenName] : null;
        if (modal)
            ModalManager.closeModal(modal);
    }

    ConnectedSurfaceLease {
        id: lease

        claimPrefix: "island"
        slot: "island"
        retractsDock: true
        screenName: root.screenName
        enabled: root.connectedChrome
        active: root.connectedChrome
        presented: controller.expanded
        dockBlocked: controller.expanded
        dockSide: root.edge
        isCurrentOwner: name => name === root.screenName
        onRecoveryRequested: root.publishSurface()
    }

    function surfaceBodyRect() {
        return {
            "x": root.hostOriginX + surface.currentVisualX,
            "y": root.hostOriginY + surface.currentVisualY,
            "width": surface.currentVisualWidth,
            "height": surface.currentVisualHeight
        };
    }

    // Held while expanded or still springing back; a settled compact body sits inside the band and needs no slot.
    function publishSurface() {
        if (!root.connectedChrome || (!controller.expanded && !surface.motionRunning)) {
            lease.release();
            return;
        }
        lease.publish({
            "kind": "island",
            "barSide": root.edge,
            "visible": true,
            "presented": controller.expanded,
            "surfaceRadius": Theme.connectedSurfaceRadius,
            "bodyRect": root.surfaceBodyRect()
        }, false);
    }

    Connections {
        target: root.Window.window
        enabled: root.editRoomWaiting && root.surfaceResizes && root.surfaceFits

        function onFrameSwapped() {
            controller.editRoomGranted = true;
        }
    }

    Connections {
        target: surface.surfaceMotion

        function onStepped() {
            // settle() emits after running drops, so the latch clears on the last step of the collapse spring.
            if (!controller.expanded && !surface.motionRunning)
                root.sheetOut = false;
            if (!surface.motionRunning)
                root.releaseEditSurface();
            if (!root.connectedChrome)
                return;
            const body = root.surfaceBodyRect();
            lease.updateBody(body.x, body.y, body.width, body.height);
        }
    }

    Timer {
        id: keyboardActivationTimer

        interval: 60
        onTriggered: {
            if (controller.keyboardDismissRequested && !surface.requestActivityFocus())
                islandFocus.forceActiveFocus(Qt.PopupFocusReason);
        }
    }

    Timer {
        id: keyboardRearmTimer

        interval: 80
        onTriggered: root.keyboardFocusArmed = true
    }

    Connections {
        target: PopoutManager

        function onPopoutChanged() {
            root.popoutRevision++;
        }

        function onPopoutOpening() {
            Qt.callLater(root.collapseForOpenedPopout);
        }

        function onScreenshotActiveChanged() {
            if (!PopoutManager.screenshotActive && controller.keyboardDismissRequested)
                root.requestKeyboardFocus();
        }
    }

    IslandController {
        id: controller

        onKeyboardDismissRequestedChanged: root.requestKeyboardFocus()
        onLauncherSessionActiveChanged: {
            if (!launcherSessionActive)
                islandTransientSurfaces.closeAll();
        }

        barConfig: root.barConfig
        screen: root.screen
        edge: root.edge
        sectionOriginX: root.sectionOriginX
        sectionOriginY: root.sectionOriginY
        transientSurfaces: islandTransientSurfaces
        freeMode: root.freeMode
        dotMode: root.dotMode
        embedded: root.embedded
        notch: root.notch
        dotSize: root.dotSize * root.freeScale
        interactionMode: !root.freeMode && root.setting("islandInteractionMode") === "hybrid" ? "hybrid" : "click"
        inputSuspended: PopoutManager.screenshotActive
        alongOffset: root.freeMode || root.embedded ? 0 : Math.max(-root.maximumAlongOffset, Math.min(root.maximumAlongOffset, root.setting("islandAlongOffset")))
        outerGap: root.outerGap
        compactThickness: root.compactThickness
        cornerRadius: root.connectedChrome ? Theme.connectedSurfaceRadius : Theme.windowRadius
        pillRadius: BarMetrics.pillRadius(root.compactThickness, root.barConfig?.widgetStyle ?? "pills")
        homeCompactTight: root.setting("islandHomeCompactTight")
        homeStatusContent: SettingsData.islandHomeStatusContent(root.barConfig)
        homeClockDisplay: SettingsData.islandClockDisplay(root.barConfig)
        homeVolumeDisplay: SettingsData.islandLevelDisplay(root.barConfig, "islandHomeVolumeDisplay")
        homeBrightnessDisplay: SettingsData.islandLevelDisplay(root.barConfig, "islandHomeBrightnessDisplay")
        batteryStyle: root.setting("islandBatteryStyle")
        mediaClockVisible: root.setting("islandMediaClockVisible")
        mediaLyrics: root.setting("islandMediaLyrics")
        // Home and media share the dot face; see mediaFaceToggleAvailable.
        mediaAutoSwitch: !root.dotMode && root.setting("islandMediaAutoSwitch")
        launcherCycleEnabled: SettingsData.launcherStyle === "island"
        dashboardAvailableWidth: Math.max(0, (root.screen?.width ?? root.referenceScreenWidth) - (root.isVertical ? root.crossInsetStart + root.crossInsetEnd + root.outerGap + root.nearInset : root.alongInset) - Theme.spacingL * 2)
        dashboardAvailableHeight: Math.max(0, (root.screen?.height ?? root.referenceScreenHeight) - (root.isVertical ? root.alongInset : root.crossInsetStart + root.crossInsetEnd + root.outerGap + root.nearInset) - Theme.spacingL * 2)
        controlCenterMaxHeight: dashboardAvailableHeight
        notificationExpandAllowed: root.setting("islandNotificationExpand")
        unreadNotificationCount: root.setting("islandNotificationBadgeClearOnOpen") ? NotificationService.unreadCount : NotificationService.notifications.length
        hoverOpenDelay: Math.max(0, Math.min(root.maxHoverDelay, root.setting("islandHoverOpenDelay")))
        hoverCloseDelay: Math.max(0, Math.min(root.maxHoverDelay, root.setting("islandHoverCloseDelay")))
    }

    DLauncher.Controller {
        id: launcherController

        active: controller.launcherSessionActive
        retainResultsOnClose: !SettingsData.dankLauncherV2UnloadOnClose
        viewModeContext: "spotlight"
        forceLinearNavigation: true
    }

    TransientSurfaceTracker {
        id: islandTransientSurfaces
    }

    IslandMediaSource {
        id: mediaSource

        controller: controller
    }

    IslandSystemSource {
        id: systemSource

        controller: controller
        enabled: root.setting("islandSystemOsd") && root.barConfig?.visible !== false
        chargingPulseEnabled: root.setting("islandChargingPulse")
    }

    IslandNotificationSource {
        id: notificationSource

        controller: controller
        targetScreen: root.screen
        enabled: !root.setting("islandNotificationPopups") && root.barConfig?.visible !== false
    }

    DIslandSurface {
        id: surface

        anchors.fill: parent
        controller: controller
        mediaModel: mediaSource
        systemModel: systemSource
        notificationModel: notificationSource
        launcherController: launcherController
        launcherTransientSurfaceTracker: islandTransientSurfaces
        effectiveScreen: root.screen
        hostOriginX: root.hostOriginX
        hostOriginY: root.hostOriginY
        freeMode: root.freeMode
        anchor: root.anchor
        anchorSnaps: root.anchorSnaps
        anchorAlong: root.anchorAlong
        nearInset: root.nearInset
        bandAlongStart: root.bandAlongStart
        bandAlongEnd: root.bandAlongEnd
        hostReady: root.hostReady
        freeMargin: root.freeMargin
        compactFaceOverride: root.dotMode ? dotFaceComponent : null
        chrome: root.chrome
        notch: root.notch
        notchRadius: BarMetrics.gothRadius(root.barConfig)
        bandColor: root.bandColor
        compactBackground: root.embedded && root.setting("islandWidgetBackground") === true && !(root.barConfig?.noBackground ?? false)
        compactBackgroundColor: BarMetrics.widgetFill(root.barConfig)
        opacity: root.freeOpacity
        reducedMotion: SettingsData.reduceMotion || SettingsData.animationDuration <= 0
        springStiffness: Math.max(root.springStiffnessRange[0], Math.min(root.springStiffnessRange[1], root.setting("islandSpringStiffness")))
        springDamping: Math.max(root.springDampingRange[0], Math.min(root.springDampingRange[1], root.setting("islandSpringDamping")))
        springMass: Math.max(root.springMassRange[0], Math.min(root.springMassRange[1], root.setting("islandSpringMass")))
        palette: root.setting("islandPalette")
        highContrast: !root.embedded && root.setting("islandHighContrast")
        transparency: SettingsData.barTransparency(root.barConfig)
        surfaceBase: SettingsData.barSurfaceColor(root.barConfig)
        onScrollWheel: wheel => root.scrollWheel(wheel)

        Behavior on opacity {
            NumberAnimation {
                duration: surface.reducedMotion ? 0 : Theme.mediumDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Component {
        id: dotFaceComponent

        DotCompact {
            controller: controller
            iconName: root.setting("islandFreeIcon")
            iconMode: root.setting("islandFreeIconMode")
            iconPath: root.setting("islandFreeIconPath")
            iconColor: root.setting("islandFreeIconColor")
        }
    }

    FocusScope {
        id: islandFocus

        anchors.fill: parent
        Keys.onEscapePressed: event => {
            controller.requestCollapse();
            event.accepted = true;
        }
    }
}
