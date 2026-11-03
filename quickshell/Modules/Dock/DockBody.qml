pragma ComponentBehavior: Bound
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.SurfaceWidgets
import qs.Modules.DBar
import qs.Modules.DBar.Widgets as BarWidgets
import qs.Modules.ControlCenter.Widgets
import "../../Common/settings/DockConfig.js" as DockConfig

FocusScope {
    id: dock

    required property var hostWindow
    required property var config
    required property var modelData
    readonly property var screen: modelData
    property bool editMode: false
    property bool widgetLibraryOpen: false
    onEditModeChanged: {
        widgetLibraryOpen = false;
        if (!editMode)
            return;
        closeExpansion();
        tooltipRevealDelay.stop();
        dockTooltip.hide();
        forceActiveFocus();
    }
    function addWidget(widgetId) {
        SettingsData.updateDockConfig(config.id, {
            widgets: config.widgets.concat([
                {
                    id: config.id + "_" + Date.now(),
                    widgetId,
                    enabled: true
                }
            ])
        });
    }
    function closeWidgetLibrary() {
        widgetLibraryOpen = false;
        forceActiveFocus();
    }
    function reorderUnits(from, to) {
        const strip = appProvider.item?.stripItem ?? null;
        const apps = strip?.items ?? [];
        const current = DockConfig.unitList(config.widgets, DockConfig.pinUnits(apps), config.order);
        const next = DockConfig.move(current, current.indexOf(from), current.indexOf(to));
        if (next === current)
            return;
        const pins = strip ? DockConfig.reorderPins(strip.pinnedApps, apps, next) : null;
        if (pins)
            strip.setPinnedApps(pins);
        SettingsData.updateDockConfig(config.id, {
            order: next
        });
    }
    function removeWidget(instanceId) {
        SettingsData.updateDockConfig(config.id, {
            widgets: config.widgets.filter(item => item.id !== instanceId)
        });
    }
    function openWidgetSettings() {
        editMode = false;
        SettingsUiState.dockHubSelection = config.id;
        PopoutService.openSettingsWithTab("dock_widgets");
    }
    property var expansionOwner: null
    readonly property string chromeOwnerId: dockLease.claimId
    readonly property real expansionExtent: expansionOwner ? Math.min(320, (isVertical ? screen.width : screen.height) / 2) : 0
    readonly property real effectiveBarThickness: DockConfig.effectiveThickness(config)
    readonly property real widgetThickness: config.iconSize
    // Bar widgets size off bar metrics, so hand them the bar thickness matching the dock icon size.
    readonly property var widgetConfig: Object.assign({}, config, {
        fontScale: (config.iconSize / 40) * Theme.fontSizeMedium / Theme.barTextSize(widgetThickness),
        iconScale: 1.6
    })
    property alias axis: dockAxis
    property var clockButtonRef: null
    property var controlCenterButtonRef: null
    property var systemUpdateButtonRef: null
    readonly property bool interactionActive: editMode || expansionOwner !== null || widgetStrip.interactionActive || (appProvider.item?.interactionActive ?? false)

    function revealWidgetItem(item) {
        revealSticky = true;
        revealHold.restart();
        if (item)
            widgetStrip.revealItem(item);
    }
    function openExpansion(item) {
        if (!item?.attachedContent)
            return false;
        if (expansionOwner === item) {
            closeExpansion();
            return true;
        }
        expansionOwner = item;
        item.forceActiveFocus();
        return true;
    }
    function closeExpansion() {
        const owner = expansionOwner;
        expansionOwner = null;
        owner?.forceActiveFocus();
    }
    Keys.onEscapePressed: event => {
        if (expansionOwner)
            closeExpansion();
        else
            editMode = false;
        event.accepted = true;
    }
    onConfigChanged: {
        if (expansionOwner && !config.widgets.some(item => item.enabled !== false && item.id === expansionOwner.widgetInstanceId))
            closeExpansion();
    }
    AxisContext {
        id: dockAxis
        edge: dock.connectedBarSide
    }
    // Widget pills fill the content lane exactly, so nothing overhangs the padding.
    SurfaceContext {
        id: widgetContext
        kind: "dock"
        host: dock
        config: dock.widgetConfig
        thickness: dock.widgetThickness
    }
    SurfaceWidgetFactory {
        id: widgetFactory
        surfaceContext: widgetContext
    }

    Loader {
        id: appProvider
        readonly property var widget: dock.config.widgets.find(item => item.widgetId === "appsDock" && item.enabled !== false) ?? null
        active: widget !== null
        visible: false
        sourceComponent: BarWidgets.AppsDock {
            surfaceContext: widgetContext
            widgetData: appProvider.widget
            barConfig: dock.config
            parentScreen: dock.screen
            axis: dock.axis
            barThickness: dock.widgetThickness
            widgetThickness: dock.widgetThickness
            renderItems: false
            mixedStrip: widgetStrip
        }
    }

    property var contextMenu
    property var trashContextMenu

    readonly property real primaryStartInset: {
        if (isVertical && config.mode === "taskbar")
            return 0;
        return Math.max(config.mode === "taskbar" ? 0 : dockGeometry.frameInset, SettingsData.taskbarInsetForEdge(screen, isVertical ? "top" : "left"));
    }
    readonly property real primaryEndInset: {
        if (isVertical && config.mode === "taskbar")
            return 0;
        return Math.max(config.mode === "taskbar" ? 0 : dockGeometry.frameInset, SettingsData.taskbarInsetForEdge(screen, isVertical ? "bottom" : "right"));
    }
    readonly property real availablePrimary: Math.max(0, (isVertical ? height : width) - ((config.mode === "taskbar" ? 0 : config.margin) + (usesConnectedFrameChrome ? 0 : borderThickness)) * 2 - primaryStartInset - primaryEndInset)
    readonly property var shapeTarget: ({
            width: dockBackground.targetWidth,
            height: dockBackground.targetHeight,
            offsetAlong: 0,
            offsetCross: 0,
            topLeftRadius: surfaceTopLeftRadius,
            topRightRadius: surfaceTopRightRadius,
            bottomLeftRadius: surfaceBottomLeftRadius,
            bottomRightRadius: surfaceBottomRightRadius
        })
    onShapeTargetChanged: surfaceMotion.setTarget(shapeTarget)
    readonly property bool motionRunning: surfaceMotion.running || slideXSpring.running || slideYSpring.running
    VectorSpringMotion {
        id: surfaceMotion
        reducedMotion: Theme.springMotionDisabled
        enabled: dock.visible
        stiffness: dock.slideSpringParams.stiffness
        damping: dock.slideSpringParams.damping
        Component.onCompleted: snapTo(dock.shapeTarget)
        onRunningChanged: dockChromeSync.schedule()
    }
    readonly property bool isVertical: dock.config.position === SettingsData.Position.Left || dock.config.position === SettingsData.Position.Right

    property bool autoHide: dock.config.autoHide || dock.config.smartAutoHide
    property real backgroundTransparency: SettingsData.barTransparency(dock.config)
    property bool groupByApp: dock.config.groupByApp
    readonly property int borderThickness: dock.config.borderEnabled ? dock.config.borderThickness : 0
    readonly property string connectedBarSide: dock.config.position === SettingsData.Position.Top ? "top" : dock.config.position === SettingsData.Position.Bottom ? "bottom" : dock.config.position === SettingsData.Position.Left ? "left" : "right"
    readonly property bool frameDockExclusionActive: dockGeometry.frameExclusionActive
    readonly property real connectedJoinInset: dockGeometry.connectedJoinInset
    readonly property real dockFrameInset: dockGeometry.frameInset
    readonly property real animatedSurfaceRadius: Math.max(0, surfaceMotion.currentTopLeftRadius, surfaceMotion.currentTopRightRadius, surfaceMotion.currentBottomLeftRadius, surfaceMotion.currentBottomRightRadius)
    onAnimatedSurfaceRadiusChanged: dockChromeSync.schedule()
    readonly property real surfaceRadius: config.mode === "taskbar" ? (usesConnectedFrameChrome ? Theme.connectedSurfaceRadius : 0) : Theme.windowRadius
    readonly property color surfaceColor: usesConnectedFrameChrome ? Theme.connectedSurfaceColor : Theme.withAlpha(Theme.hostSurface, backgroundTransparency)
    readonly property real surfaceTopLeftRadius: usesConnectedFrameChrome && (dock.config.position === SettingsData.Position.Top || dock.config.position === SettingsData.Position.Left) ? 0 : surfaceRadius
    readonly property real surfaceTopRightRadius: usesConnectedFrameChrome && (dock.config.position === SettingsData.Position.Top || dock.config.position === SettingsData.Position.Right) ? 0 : surfaceRadius
    readonly property real surfaceBottomLeftRadius: usesConnectedFrameChrome && (dock.config.position === SettingsData.Position.Bottom || dock.config.position === SettingsData.Position.Left) ? 0 : surfaceRadius
    readonly property real surfaceBottomRightRadius: usesConnectedFrameChrome && (dock.config.position === SettingsData.Position.Bottom || dock.config.position === SettingsData.Position.Right) ? 0 : surfaceRadius
    readonly property real horizontalConnectorExtent: usesConnectedFrameChrome && !isVertical ? Theme.connectedCornerRadius : 0
    readonly property real verticalConnectorExtent: usesConnectedFrameChrome && isVertical ? Theme.connectedCornerRadius : 0

    readonly property bool hasApps: widgetStrip.preferredLength > 0

    readonly property real effectiveBarHeight: dockGeometry.visualThickness

    readonly property real barSpacing: ShellLayout.dockAdjacentThickness(screen, connectedBarSide)

    readonly property real adjacentTopBarHeight: isVertical && !autoHide ? ShellLayout.dockAdjacentThickness(screen, "top") : 0
    readonly property real adjacentLeftBarWidth: !isVertical && !autoHide ? ShellLayout.dockAdjacentThickness(screen, "left") : 0

    readonly property real dockMargin: dock.config.margin
    readonly property real effectiveDockMargin: dockGeometry.effectiveMargin
    readonly property real joinedEdgeMargin: dockGeometry.joinedEdgeMargin
    readonly property real _dpr: (dock.screen && dock.screen.devicePixelRatio) ? dock.screen.devicePixelRatio : 1
    DockGeometry {
        id: dockGeometry

        screen: dock.screen || dock.modelData
        edge: dock.connectedBarSide
        dockVisible: dock.visible
        autoHide: dock.autoHide
        thickness: dock.effectiveBarThickness + dock.expansionExtent
        reserveThickness: dock.effectiveBarThickness
        overlay: dock.config.useOverlayLayer
        borderThickness: dock.borderThickness
        exclusiveOffset: dock.config.mode === "taskbar" ? 0 : dock.config.bottomGap
        margin: dock.config.mode === "taskbar" ? 0 : dock.config.margin
        barSpacing: dock.barSpacing
        dpr: dock._dpr
    }

    // Dock window origin in screen-relative coordinates (FrameWindow space).
    function _dockWindowOriginX() {
        if (!dock.isVertical)
            return 0;
        if (dock.config.position === SettingsData.Position.Right)
            return (dock.screen ? dock.screen.width : 0) - dock.width;
        return 0;
    }
    function _dockWindowOriginY() {
        if (dock.isVertical)
            return 0;
        if (dock.config.position === SettingsData.Position.Bottom)
            return (dock.screen ? dock.screen.height : 0) - dock.height;
        return 0;
    }

    readonly property string _dockScreenName: dock.modelData ? dock.modelData.name : (dock.screen ? dock.screen.name : "")
    readonly property bool usesConnectedFrameChrome: !dock.config.useOverlayLayer && CompositorService.usesConnectedFrameChromeForScreen(dock._dockScreenName)
    readonly property bool usesOverlayLayer: CompositorService.framePeerSurfacesUseOverlayForScreen(dock._dockScreenName) || dock.config.useOverlayLayer
    readonly property bool fullscreenOnScreen: CompositorService.fullscreenToplevelOnScreen(dock._dockScreenName)
    readonly property bool hiddenForFullscreen: usesOverlayLayer && fullscreenOnScreen && !dock.config.showOnFullscreen
    readonly property bool geometryReady: dock.width > 0 && dock.height > 0 && dockBackground.width > 0 && dockBackground.height > 0

    readonly property rect surfaceBounds: Qt.rect(_dockWindowOriginX() + dockBackground.x + dockContainer.x + dockMouseArea.x + dockCore.x + dockSlide.x, _dockWindowOriginY() + dockBackground.y + dockContainer.y + dockMouseArea.y + dockCore.y + dockSlide.y, dockBackground.width, dockBackground.height)

    function _syncDockChromeState() {
        const currentDockId = dock.config?.id ?? "";
        if (dockLease.dockId !== currentDockId) {
            dockLease.release();
            dockLease.dockId = currentDockId;
        }
        const presented = dock.geometryReady && (hostWindow?.visible ?? true) && (dock.reveal || slideXSpring.running || slideYSpring.running) && dock.hasApps;
        const phase = !presented ? "hidden" : ((!dock.reveal && (slideXSpring.running || slideYSpring.running)) ? "closing" : ((slideXSpring.running || slideYSpring.running) ? "opening" : "open"));
        const bodyX = dock._dockWindowOriginX() + dockBackground.x + dockContainer.x + dockMouseArea.x + dockCore.x;
        const bodyY = dock._dockWindowOriginY() + dockBackground.y + dockContainer.y + dockMouseArea.y + dockCore.y;
        const bodyW = dock.hasApps ? dockBackground.width : 0;
        const bodyH = dock.hasApps ? dockBackground.height : 0;
        dockLease.publish({
            "kind": "dock",
            "screenName": dock._dockScreenName,
            "phase": phase,
            "visible": presented,
            "presented": presented,
            "reveal": presented,
            "barSide": dock.connectedBarSide,
            "bodyRect": {
                "x": bodyX,
                "y": bodyY,
                "width": bodyW,
                "height": bodyH
            },
            "animationOffset": {
                "x": dockSlide.x,
                "y": dockSlide.y
            },
            "scale": 1,
            "surfaceRadius": dock.animatedSurfaceRadius,
            "opacity": Theme.connectedSurfaceColor.a,
            "bodyX": bodyX,
            "bodyY": bodyY,
            "bodyW": bodyW,
            "bodyH": bodyH,
            "slideX": dockSlide.x,
            "slideY": dockSlide.y
        });
    }

    function _syncDockSlide() {
        if (!dock._dockScreenName || !dock.usesConnectedFrameChrome)
            return;
        dockLease.updateAnim(dockSlide.x, dockSlide.y);
    }

    ConnectedSurfaceLease {
        id: dockLease
        property string dockId: dock.config?.id ?? ""
        property bool superseded: false
        claimPrefix: "dock"
        slot: ConnectedModeState.surfaceSlot("dock", dockId)
        screenName: dock._dockScreenName
        enabled: dock.usesConnectedFrameChrome
        active: dock.hasApps
        isCurrentOwner: name => {
            const owner = ConnectedModeState.surfaceOwnerId(name, slot);
            if (claimId && owner && owner !== claimId)
                superseded = true;
            return !superseded;
        }
        onRecoveryRequested: dockChromeSync.schedule()
    }

    DeferredAction {
        id: dockSlideSync
        enabled: dock.usesConnectedFrameChrome
        onTriggered: dock._syncDockSlide()
    }

    function _queueSlideSync() {
        if (!dock.usesConnectedFrameChrome)
            return;
        dockSlideSync.schedule();
    }

    DeferredAction {
        id: dockChromeSync
        onTriggered: dock._syncDockChromeState()
    }

    readonly property var slideSpringParams: dock.usesConnectedFrameChrome ? Theme.springPreset("default", Theme.variantDuration(Theme.popoutAnimationDuration, dock.reveal)) : Theme.springPreset("fast", Theme.shortDuration)

    SpringMotion {
        id: slideXSpring
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: dock.slideSpringParams.stiffness
        damping: dock.slideSpringParams.damping
        value: dockSlide.targetX

        onRunningChanged: if (!running)
            dock._syncDockChromeState()
    }

    SpringMotion {
        id: slideYSpring
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: dock.slideSpringParams.stiffness
        damping: dock.slideSpringParams.damping
        value: dockSlide.targetY

        onRunningChanged: if (!running)
            dock._syncDockChromeState()
    }

    property bool contextMenuOpen: !!(widgetStrip.interactionActive || (dock.contextMenu && dock.contextMenu.visible && dock.contextMenu.surfaceContext?.host === dock) || (dock.trashContextMenu && dock.trashContextMenu.visible && dock.trashContextMenu.surfaceContext?.host === dock))
    property bool revealSticky: false

    readonly property bool shouldHideForWindows: {
        if (!dock.config.smartAutoHide)
            return false;
        CompositorService.windowStateRevision;
        return CompositorService.windowsOverlapDock(dock.modelData?.name ?? "", dock.config.position, dockGeometry.motionThickness, dock.screen?.width ?? 0, dock.screen?.height ?? 0);
    }

    Timer {
        id: revealHold
        interval: 250
        repeat: false
        onTriggered: dock.revealSticky = false
    }

    // Flip `reveal` false when a modal claims this edge; reuses the slide animation
    readonly property bool _modalRetractActive: {
        if (!dock._dockScreenName)
            return false;
        return ConnectedModeState.dockRetractActiveForSide(dock._dockScreenName, dock.connectedBarSide);
    }

    property bool startupRevealDone: false

    Timer {
        id: startupRevealTimer
        interval: 200
        running: true
        onTriggered: dock.startupRevealDone = true
    }

    readonly property bool overviewReveal: dock.config.openOnOverview && CompositorService.overviewActiveForScreen(dock._dockScreenName)
    readonly property bool hoverOrActive: dockMouseArea.containsMouse || dock.interactionActive || contextMenuOpen || revealSticky

    onOverviewRevealChanged: {
        if (overviewReveal && usesConnectedFrameChrome) {
            slideXSpring.snapTo(dockSlide.targetX);
            slideYSpring.snapTo(dockSlide.targetY);
            dock._syncDockChromeState();
        }
    }

    property bool reveal: {
        if ((!startupRevealDone && !overviewReveal) || !dock.geometryReady || !(hostWindow?.visible ?? true))
            return false;

        if (_modalRetractActive)
            return false;

        if (overviewReveal)
            return true;

        if (hiddenForFullscreen || !dock.config.enabled)
            return false;

        if (dock.config.smartAutoHide)
            return !shouldHideForWindows || hoverOrActive;

        return !autoHide || hoverOrActive;
    }

    onContextMenuOpenChanged: {
        if (!contextMenuOpen && autoHide && !dockMouseArea.containsMouse) {
            revealSticky = true;
            revealHold.restart();
        }
    }

    Component.onCompleted: dockChromeSync.schedule()
    Component.onDestruction: {
        dockChromeSync.cancel();
        dockSlideSync.cancel();
        dockLease.release();
    }

    on_DockScreenNameChanged: dockChromeSync.schedule()
    onRevealChanged: {
        if (!reveal)
            editMode = false;
        dock._syncDockChromeState();
        if (!reveal) {
            tooltipRevealDelay.stop();
            dockTooltip.hide();
        } else {
            tooltipRevealDelay.restart();
        }
    }
    onHoveredButtonChanged: showTooltipForHoveredButton()
    onWidthChanged: dock._syncDockChromeState()
    onHeightChanged: dock._syncDockChromeState()
    onVisibleChanged: dock._syncDockChromeState()
    onHasAppsChanged: dock._syncDockChromeState()
    property bool _switchingPosition: false

    onConnectedBarSideChanged: {
        dock._switchingPosition = true;
        slideXSpring.snapTo(dock.isVertical ? dockSlide.targetX : 0);
        slideYSpring.snapTo(!dock.isVertical ? dockSlide.targetY : 0);
        dockChromeSync.schedule();
        Qt.callLater(() => {
            dock._switchingPosition = false;
        });
    }
    onUsesConnectedFrameChromeChanged: dock._syncDockChromeState()

    Connections {
        target: BarWidgetService
        function onDockEditRequested(dockId) {
            if (dockId === dock.config.id)
                dock.editMode = true;
        }
    }

    readonly property bool settingsConnectedFrameModeActive: SettingsData.connectedFrameModeActive

    onSettingsConnectedFrameModeActiveChanged: {
        dockSlideSync.cancel();
        dock._syncDockChromeState();
    }

    readonly property real dockReserveZone: dockGeometry.reserveZone
    readonly property bool shouldReserveDockSpace: dock.config.enabled && dockGeometry.shouldReserveSpace

    readonly property real surfaceExclusiveZone: {
        if (!dock.shouldReserveDockSpace)
            return -1;
        if (dock.frameDockExclusionActive)
            return -1;
        return dock.dockReserveZone;
    }

    property real animationHeadroom: Math.ceil(dock.config.iconSize * 0.35)
    readonly property real stripOverflow: animationHeadroom + dock.config.spacing

    readonly property real surfaceImplicitWidth: isVertical ? (Theme.px(dockGeometry.surfaceThickness + dock.config.iconSize * 0.3, _dpr) + animationHeadroom) : 0
    readonly property real surfaceImplicitHeight: !isVertical ? (Theme.px(dockGeometry.surfaceThickness + dock.config.iconSize * 0.3, _dpr) + animationHeadroom) : 0

    readonly property real blurX: dockBackground.x + dockContainer.x + dockMouseArea.x + dockCore.x + dockSlide.x
    readonly property real blurY: dockBackground.y + dockContainer.y + dockMouseArea.y + dockCore.y + dockSlide.y
    readonly property real blurWidth: dock.hasApps && dock.reveal ? dockBackground.width : 0
    readonly property real blurHeight: dock.hasApps && dock.reveal ? dockBackground.height : 0
    readonly property real blurRadius: dock.animatedSurfaceRadius

    Item {
        id: maskItem
        visible: false
        readonly property bool expanded: dock.reveal
        readonly property bool chrome: dock.usesConnectedFrameChrome
        readonly property bool atEndEdge: dock.config.position === SettingsData.Position.Bottom || dock.config.position === SettingsData.Position.Right
        readonly property real innerReach: borderThickness + animationHeadroom
        readonly property real bodyX: dockBackground.x + dockContainer.x + dockMouseArea.x + dockCore.x + dockSlide.x
        readonly property real bodyY: dockBackground.y + dockContainer.y + dockMouseArea.y + dockCore.y + dockSlide.y
        x: {
            if (chrome) {
                const baseX = dockCore.x + dockMouseArea.x;
                if (isVertical && atEndEdge)
                    return baseX - (expanded ? animationHeadroom + borderThickness + dock.horizontalConnectorExtent : 0);
                return baseX - (expanded ? borderThickness + dock.horizontalConnectorExtent : 0);
            }
            if (!isVertical)
                return dockCore.x + dockMouseArea.x - (expanded ? borderThickness : 0);
            if (!atEndEdge)
                return 0;
            return expanded ? Math.min(bodyX - innerReach, dock.width - 1) : dock.width - 1;
        }
        y: {
            if (chrome) {
                const baseY = dockCore.y + dockMouseArea.y;
                if (!isVertical && atEndEdge)
                    return baseY - (expanded ? animationHeadroom + borderThickness + dock.verticalConnectorExtent : 0);
                return baseY - (expanded ? borderThickness + dock.verticalConnectorExtent : 0);
            }
            if (isVertical)
                return dockCore.y + dockMouseArea.y - (expanded ? borderThickness : 0);
            if (!atEndEdge)
                return 0;
            return expanded ? Math.min(bodyY - innerReach, dock.height - 1) : dock.height - 1;
        }
        width: {
            if (dock.hiddenForFullscreen && !expanded)
                return 0;
            if (chrome)
                return dockMouseArea.width + (isVertical && expanded ? animationHeadroom : 0) + (expanded ? borderThickness * 2 + dock.horizontalConnectorExtent * 2 : 0);
            if (!isVertical)
                return dockMouseArea.width + (expanded ? borderThickness * 2 : 0);
            if (!expanded)
                return 1;
            return atEndEdge ? dock.width - x : Math.max(bodyX + dockBackground.width + innerReach, 1);
        }
        height: {
            if (dock.hiddenForFullscreen && !expanded)
                return 0;
            if (chrome)
                return dockMouseArea.height + (!isVertical && expanded ? animationHeadroom : 0) + (expanded ? borderThickness * 2 + dock.verticalConnectorExtent * 2 : 0);
            if (isVertical)
                return dockMouseArea.height + (expanded ? borderThickness * 2 : 0);
            if (!expanded)
                return 1;
            return atEndEdge ? dock.height - y : Math.max(bodyY + dockBackground.height + innerReach, 1);
        }
    }

    readonly property alias inputMaskItem: maskItem

    readonly property var hoveredButton: widgetStrip.hoveredButton

    DTooltip {
        id: dockTooltip
        targetScreen: dock.screen
        persistent: dock.config.enabled && (dock.hostWindow?.visible ?? false) && !dock.fullscreenOnScreen
    }

    Timer {
        id: tooltipRevealDelay
        interval: 250
        repeat: false
        onTriggered: dock.showTooltipForHoveredButton()
    }

    function showTooltipForHoveredButton() {
        dockTooltip.hide();
        if (dock.editMode || !dock.hoveredButton || !dock.reveal || slideXSpring.running || slideYSpring.running)
            return;

        const buttonLocalPos = dock.hoveredButton.mapToItem(null, 0, 0);
        const tooltipText = dock.hoveredButton.tooltipText || "";
        if (!tooltipText)
            return;

        const screenHeight = dock.screen ? dock.screen.height : 0;

        const gap = Theme.spacingS;
        const bgMargin = dockGeometry.bodyEdgeMargin;
        const btnW = dock.hoveredButton.width;
        const btnH = dock.hoveredButton.height;

        if (!dock.isVertical) {
            const isBottom = dock.config.position === SettingsData.Position.Bottom;
            const tooltipX = buttonLocalPos.x + btnW / 2 + adjacentLeftBarWidth;
            const tooltipHeight = 32;
            const totalFromEdge = bgMargin + dockBackground.height + dock.borderThickness + gap;
            const screenRelativeY = isBottom ? (screenHeight - totalFromEdge - tooltipHeight) : totalFromEdge;
            dockTooltip.show(tooltipText, tooltipX, screenRelativeY, dock.screen, false, false);
            return;
        }

        const isLeft = dock.config.position === SettingsData.Position.Left;
        const screenWidth = dock.screen ? dock.screen.width : 0;
        const totalFromEdge = bgMargin + dockBackground.width + dock.borderThickness + gap;
        const tooltipX = isLeft ? totalFromEdge : (screenWidth - totalFromEdge);
        const screenRelativeY = buttonLocalPos.y + btnH / 2 + adjacentTopBarHeight;
        dockTooltip.show(tooltipText, tooltipX, screenRelativeY, dock.screen, isLeft, !isLeft);
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.backdropColor, Theme.scrimAlpha)
        opacity: dock.editMode ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: dock.editMode = false
        }
    }

    Item {
        id: dockCore
        anchors.fill: parent
        x: isVertical && dock.config.position === SettingsData.Position.Right ? animationHeadroom : 0
        y: !isVertical && dock.config.position === SettingsData.Position.Bottom ? animationHeadroom : 0

        MouseArea {
            id: dockMouseArea
            onContainsMouseChanged: {
                if (containsMouse) {
                    dock.revealSticky = true;
                    revealHold.stop();
                } else {
                    if (dock.autoHide && !dock.contextMenuOpen) {
                        revealHold.restart();
                    }
                }
            }
            property var currentScreen: modelData ? modelData : dock.screen
            property real screenWidth: currentScreen ? currentScreen.width : 1920
            property real screenHeight: currentScreen ? currentScreen.height : 1080
            property real maxDockWidth: screenWidth * 0.98
            property real maxDockHeight: screenHeight * 0.98

            height: {
                if (dock.isVertical) {
                    const h = dockBackground.height;
                    return Math.min(h + dock.config.spacing * 2, dock.availablePrimary);
                }
                return dock.reveal ? Theme.px(dockGeometry.motionThickness, _dpr) : 1;
            }
            width: {
                if (dock.isVertical) {
                    return dock.reveal ? Theme.px(dockGeometry.motionThickness, _dpr) : 1;
                }
                const w = dockBackground.width;
                return Math.min(w + dock.config.spacing * 2, dock.availablePrimary);
            }
            x: !dock.isVertical ? Math.round((parent.width - width + dock.primaryStartInset - dock.primaryEndInset) / 2) : (dock.config.position === SettingsData.Position.Right ? parent.width - width : 0)
            y: dock.isVertical ? Math.round((parent.height - height + dock.primaryStartInset - dock.primaryEndInset) / 2) : (dock.config.position === SettingsData.Position.Bottom ? parent.height - height : 0)
            hoverEnabled: true
            acceptedButtons: dock.config.editOnRightClick ? Qt.RightButton : Qt.NoButton
            onClicked: dock.editMode = !dock.editMode

            Behavior on height {
                enabled: !dock._switchingPosition
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on width {
                enabled: !dock._switchingPosition
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutCubic
                }
            }

            onXChanged: dockChromeSync.schedule()
            onYChanged: dockChromeSync.schedule()

            Item {
                id: dockContainer
                anchors.fill: parent
                clip: false
                opacity: dock.startupRevealDone ? 1 : 0

                transform: Translate {
                    id: dockSlide

                    readonly property real targetX: {
                        if (!dock.isVertical)
                            return 0;
                        if (dock.reveal)
                            return 0;
                        if (dock.usesConnectedFrameChrome) {
                            const retractDist = dockBackground.width + dock.config.spacing + 10;
                            return dock.config.position === SettingsData.Position.Right ? retractDist : -retractDist;
                        }
                        const hideDistance = dockGeometry.motionThickness + 10;
                        if (dock.config.position === SettingsData.Position.Right) {
                            return hideDistance;
                        } else {
                            return -hideDistance;
                        }
                    }
                    readonly property real targetY: {
                        if (dock.isVertical)
                            return 0;
                        if (dock.reveal)
                            return 0;
                        if (dock.usesConnectedFrameChrome) {
                            const retractDist = dockBackground.height + dock.config.spacing + 10;
                            return dock.config.position === SettingsData.Position.Bottom ? retractDist : -retractDist;
                        }
                        const hideDistance = dockGeometry.motionThickness + 10;
                        if (dock.config.position === SettingsData.Position.Bottom) {
                            return hideDistance;
                        } else {
                            return -hideDistance;
                        }
                    }

                    x: dock.isVertical ? slideXSpring.value : 0
                    y: !dock.isVertical ? slideYSpring.value : 0

                    onTargetXChanged: slideXSpring.retarget(targetX)
                    onTargetYChanged: slideYSpring.retarget(targetY)

                    onXChanged: dock._queueSlideSync()
                    onYChanged: dock._queueSlideSync()
                }

                Item {
                    id: dockBackground
                    objectName: "dockBackground"
                    visible: dock.hasApps
                    x: !dock.isVertical ? Math.round((parent.width - width + dock.primaryStartInset - dock.primaryEndInset) / 2) : (dock.config.position === SettingsData.Position.Right ? parent.width - width - dockGeometry.bodyEdgeMargin : dockGeometry.bodyEdgeMargin)
                    y: dock.isVertical ? Math.round((parent.height - height + dock.primaryStartInset - dock.primaryEndInset) / 2) : (dock.config.position === SettingsData.Position.Bottom ? parent.height - height - dockGeometry.bodyEdgeMargin : dockGeometry.bodyEdgeMargin)

                    readonly property real targetPrimary: dock.config.mode === "taskbar" ? dock.availablePrimary : Math.min(widgetStrip.restLength + dock.config.spacing * 2, dock.availablePrimary)
                    readonly property real targetWidth: dock.isVertical ? dock.effectiveBarThickness + dock.expansionExtent : targetPrimary
                    readonly property real targetHeight: dock.isVertical ? targetPrimary : dock.effectiveBarThickness + dock.expansionExtent
                    // Magnification expansion bypasses the spring so icons and background stay in sync
                    implicitWidth: surfaceMotion.currentWidth + (dock.isVertical ? 0 : widgetStrip.totalMagnificationExpansion)
                    implicitHeight: surfaceMotion.currentHeight + (dock.isVertical ? widgetStrip.totalMagnificationExpansion : 0)
                    width: implicitWidth
                    height: implicitHeight

                    clip: false

                    MorphSurface {
                        motion: surfaceMotion
                        anchors.fill: parent
                        visible: !usesConnectedFrameChrome && (!FrameTransitionState.effectiveConnectedFrameModeActive || dock.reveal)
                        color: dock.surfaceColor
                    }

                    onXChanged: dockChromeSync.schedule()
                    onYChanged: dockChromeSync.schedule()
                    onWidthChanged: dockChromeSync.schedule()
                    onHeightChanged: dockChromeSync.schedule()
                }

                Item {
                    id: dockConnectedChrome
                    visible: Theme.isConnectedEffect && dock.reveal && dock.hasApps && !FrameTransitionState.effectiveConnectedFrameModeActive
                    readonly property real extraLeft: dock.isVertical ? 0 : Theme.connectedCornerRadius
                    readonly property real extraTop: dock.isVertical ? Theme.connectedCornerRadius : 0
                    readonly property real bodyRadius: dock.surfaceRadius
                    readonly property bool barTop: dock.connectedBarSide === "top"
                    readonly property bool barBottom: dock.connectedBarSide === "bottom"
                    readonly property bool barLeft: dock.connectedBarSide === "left"
                    readonly property bool barRight: dock.connectedBarSide === "right"

                    x: dockBackground.x - extraLeft
                    y: dockBackground.y - extraTop
                    width: dockBackground.width + extraLeft * 2
                    height: dockBackground.height + extraTop * 2

                    ShaderEffect {
                        anchors.fill: parent
                        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/connected_chrome.frag.qsb")

                        property real widthPx: width
                        property real heightPx: height
                        property vector4d surfaceColor: Qt.vector4d(dock.surfaceColor.r, dock.surfaceColor.g, dock.surfaceColor.b, dock.surfaceColor.a)
                        property vector4d shadowColor: Qt.vector4d(0, 0, 0, 0)
                        property vector4d shadowParam: Qt.vector4d(0, 0, 0, 0)
                        property vector4d ambientParam: Qt.vector4d(0, 0, 0, 0)
                        property vector4d bodyRect: Qt.vector4d(dockConnectedChrome.extraLeft, dockConnectedChrome.extraTop, dockBackground.width, dockBackground.height)
                        property vector4d cornerRadius: Qt.vector4d(dockConnectedChrome.barTop || dockConnectedChrome.barLeft ? 0 : dockConnectedChrome.bodyRadius, dockConnectedChrome.barTop || dockConnectedChrome.barRight ? 0 : dockConnectedChrome.bodyRadius, dockConnectedChrome.barBottom || dockConnectedChrome.barRight ? 0 : dockConnectedChrome.bodyRadius, dockConnectedChrome.barBottom || dockConnectedChrome.barLeft ? 0 : dockConnectedChrome.bodyRadius)
                        property vector4d edgeParam: Qt.vector4d(dockConnectedChrome.barTop ? 0 : (dockConnectedChrome.barBottom ? 1 : (dockConnectedChrome.barLeft ? 2 : 3)), Theme.connectedCornerRadius, 0, 0)
                    }
                }

                Rectangle {
                    readonly property real borderThickness: Math.max(1, dock.borderThickness)
                    x: dockBackground.x - borderThickness
                    y: dockBackground.y - borderThickness
                    width: dockBackground.width + borderThickness * 2
                    height: dockBackground.height + borderThickness * 2
                    visible: dock.config.borderEnabled && dock.hasApps && !usesConnectedFrameChrome
                    radius: dock.surfaceRadius + borderThickness
                    color: "transparent"
                    border.width: borderThickness
                    border.color: {
                        const opacity = dock.config.borderOpacity;
                        switch (dock.config.borderColor) {
                        case "secondary":
                            return Theme.withAlpha(Theme.secondary, opacity);
                        case "primary":
                            return Theme.withAlpha(Theme.primary, opacity);
                        default:
                            return Theme.withAlpha(Theme.surfaceText, opacity);
                        }
                    }
                }

                SurfaceStrip {
                    id: widgetStrip
                    spacing: dock.config.itemSpacing ?? Theme.spacingS
                    x: dockBackground.x + (dock.isVertical && dock.config.position === SettingsData.Position.Right ? dock.expansionExtent : 0) + dock.config.spacing
                    y: dockBackground.y + (!dock.isVertical && dock.config.position === SettingsData.Position.Bottom ? dock.expansionExtent : 0) + dock.config.spacing
                    width: dock.isVertical ? dock.widgetThickness : Math.max(0, dockBackground.width - dock.config.spacing * 2)
                    height: dock.isVertical ? Math.max(0, dockBackground.height - dock.config.spacing * 2) : dock.widgetThickness
                    surfaceContext: widgetContext
                    components: widgetFactory.componentMap
                    applicationStrip: appProvider.item?.stripItem ?? null
                    model: DockConfig.surfaceItems(dock.config.widgets, (applicationStrip?.items ?? []).map(item => applicationStrip.overflowExpanded ? Object.assign({}, item, {
                            isInOverflow: false
                        }) : item), dock.config.order)
                    availableSize: dock.isVertical ? height : width
                    expansionLimit: Math.max(0, dock.availablePrimary - widgetStrip.restLength - dock.config.spacing * 2)
                    fillAvailable: dock.config.mode === "taskbar"
                    align: dock.config.mode === "taskbar" ? dock.config.taskbarAlign : "start"
                    onReorderRequested: (from, to) => dock.reorderUnits(from, to)
                    onRemoveRequested: instanceId => dock.removeWidget(instanceId)
                }
                Loader {
                    id: expansion
                    active: dock.expansionOwner !== null
                    sourceComponent: dock.expansionOwner?.attachedContent ?? null
                    x: dockBackground.x + (dock.isVertical && dock.config.position === SettingsData.Position.Left ? dock.effectiveBarThickness : 0)
                    y: dockBackground.y + (!dock.isVertical && dock.config.position === SettingsData.Position.Top ? dock.effectiveBarThickness : 0)
                    width: dock.isVertical ? dock.expansionExtent : dockBackground.width
                    height: dock.isVertical ? dockBackground.height : dock.expansionExtent
                    clip: true
                }
            }
        }
    }

    DockEditChrome {
        id: editChrome
        readonly property real edgeInset: dockGeometry.surfaceThickness + Theme.spacingL
        title: dock.config.name
        canAdd: dock.addableWidgets.length > 0
        x: Math.round(dock.isVertical ? (dock.config.position === SettingsData.Position.Left ? edgeInset : dock.width - width - edgeInset) : (dock.width - width) / 2)
        y: Math.round(dock.isVertical ? (dock.height - height) / 2 : (dock.config.position === SettingsData.Position.Top ? edgeInset : dock.height - height - edgeInset))
        opacity: dock.editMode ? 1 : 0
        visible: opacity > 0
        onAddRequested: dock.widgetLibraryOpen = true
        onSettingsRequested: dock.openWidgetSettings()
        onFinished: dock.editMode = false

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    readonly property var addableWidgets: {
        if (!dock.editMode)
            return [];
        const hasApps = dock.config.widgets.some(item => item.widgetId === "appsDock");
        const plugins = PluginService.getAllPluginVariants().filter(variant => variant.loaded).map(variant => ({
                    id: variant.fullId,
                    text: variant.name,
                    icon: variant.icon
                }));
        return BarWidgetCatalog.widgets.concat(plugins).filter(widget => !widget.barOnly && (widget.id !== "appsDock" || !hasApps));
    }

    MouseArea {
        anchors.fill: parent
        visible: dock.widgetLibraryOpen
        acceptedButtons: Qt.AllButtons
        onClicked: dock.closeWidgetLibrary()
    }

    Loader {
        anchors.centerIn: parent
        active: dock.widgetLibraryOpen
        sourceComponent: CcWidgetLibrary {
            width: Math.min(implicitWidth, dock.width - Theme.spacingL * 2)
            height: Math.min(implicitHeight, dock.height - Theme.spacingL * 2)
            widgets: dock.addableWidgets
            Component.onCompleted: reset()
            onChosen: widgetId => {
                dock.addWidget(widgetId);
                dock.closeWidgetLibrary();
            }
            onDismissed: dock.closeWidgetLibrary()
        }
    }
}
