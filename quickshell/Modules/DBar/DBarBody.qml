import QtQuick
import Quickshell
import qs.Common
import qs.Modules.DIsland
import qs.Services
import qs.Widgets

Item {
    id: barWindow
    readonly property var log: Log.scoped("DBarBody")

    required property var hostWindow
    required property var rootWindow
    required property var barConfig
    required property var modelData
    readonly property var screen: modelData
    property var hyprlandOverviewLoader: rootWindow ? rootWindow.hyprlandOverviewLoader : null

    property var leftWidgetsModel
    property var centerWidgetsModel
    property var rightWidgetsModel

    readonly property bool barRevealed: inputMask.showing
    readonly property bool autoHideActive: topBarCore.autoHide

    readonly property bool isIsland: barConfig?.island === true
    // Resolver-owned so the body, the frame and the dismiss window agree during the frame latch.
    readonly property var layoutInstance: ShellLayout.forConfig(screen, _barId)
    readonly property bool hostsIsland: isIsland || (layoutInstance?.hostsIsland ?? false)
    readonly property string islandChromeMode: isIsland ? "own" : usesConnectedFrameChrome && frameHosted ? "none" : "band"
    readonly property bool frameHosted: layoutInstance?.kind === "frame"
    property real hostOffsetX: 0
    property real hostOffsetY: 0
    // A free island's pill lives in IslandFreeHostWindow; this window only carries its satellites.
    readonly property bool islandFree: isIsland && SettingsData.islandFreePlacement(barConfig)
    readonly property bool islandOverlay: isIsland && (islandHost?.floating ?? SettingsData.islandSetting(barConfig, "islandFloating")) && !islandFree
    readonly property var islandHost: islandLoader.item
    readonly property real islandStripThickness: isIsland ? SettingsData.islandStripThickness(barConfig) : 0
    readonly property string islandSatellitePosition: isIsland ? SettingsData.islandSetting(barConfig, "islandSatellitePosition") : "edges"
    readonly property bool islandSatellitesEnabled: !isIsland || SettingsData.islandSetting(barConfig, "islandSatellitesEnabled")
    readonly property bool islandSatellitesHugIsland: isIsland && islandSatellitePosition === "island"
    readonly property real islandSatelliteGap: isIsland ? SettingsData.islandSetting(barConfig, "islandSatelliteGap") : 0
    readonly property bool islandSatelliteBackground: isIsland && SettingsData.islandSetting(barConfig, "islandSatelliteBackground")
    readonly property real islandGothRadius: isIsland ? _wingR : 0
    readonly property color islandSurfaceColor: {
        if (islandHost)
            return islandHost.surfaceColor;
        if (!isIsland)
            return Theme.hostSurface;
        if (SettingsData.islandSetting(barConfig, "islandHighContrast"))
            return Theme.surfaceContainerHighest;
        const palette = SettingsData.islandSetting(barConfig, "islandPalette");
        return palette === "bright" ? Theme.surfaceBright : palette === "dim" ? Theme.surfaceDim : _hostSurface;
    }
    readonly property real islandSatelliteOpacity: isIsland ? SettingsData.islandSatelliteTransparency(barConfig) : 1
    readonly property real islandChromePad: isIsland ? Theme.snap((barConfig?.innerPadding ?? 2) + Theme.spacingXS, _dpr) : 0
    readonly property real islandChromeInset: islandSatelliteBackground ? islandChromePad : 0
    readonly property real islandSatelliteSweep: islandSatelliteBackground && SettingsData.islandSetting(barConfig, "islandSatelliteGothCorners") ? islandGothRadius : 0
    readonly property real islandFlareClearance: ((islandHost?.notch ?? false) ? islandHost.surface.joinRadius * 2.5 : 0) + islandSatelliteSweep
    // Satellites centre on the idle pill face, not the strip; backed ones reach its far edge instead.
    readonly property bool islandSatellitesTrackPill: isIsland && !!islandHost && !islandFree
    readonly property real islandPillFace: islandSatellitesTrackPill ? islandHost.islandController.compactFaceThickness : 0
    readonly property real islandSatelliteDepth: islandSatellitesTrackPill ? Theme.px(Math.min(islandStripThickness, islandHost.outerGap + islandPillFace), _dpr) : islandStripThickness
    readonly property real islandSatelliteCrossCenter: !islandSatellitesTrackPill || islandSatelliteBackground ? islandSatelliteDepth / 2 : islandHost.outerGap + islandPillFace / 2
    readonly property real islandSatelliteCrossShift: Theme.px(islandSatelliteCrossCenter - islandStripThickness / 2, _dpr) * (axis.edge === "bottom" || axis.edge === "right" ? -1 : 1)
    readonly property bool islandSatellitesClipToIsland: islandSatelliteBackground && !islandSatellitesHugIsland && !!islandHost
    readonly property bool islandMotionRunning: islandHost?.motionRunning ?? false
    onIslandMotionRunningChanged: {
        if (islandMotionRunning)
            return;
        _blurRebuildTimer.restart();
        topBarContent.invalidateHoverCandidateCache();
    }
    readonly property bool islandBandInteractive: isIsland && !!islandHost && !islandHost.inputSuspended && ((islandHost.scrollEnabled && !islandHost.floating) || islandHost.satelliteSurfacesOpen)
    readonly property real islandAlongStart: islandSatellitesHugIsland && islandHost ? Math.round(islandHost.currentAlongPos) : 0
    readonly property real islandAlongEnd: islandSatellitesHugIsland && islandHost ? Math.round(islandHost.currentAlongPos + islandHost.currentVisualAlong) : 0
    readonly property real islandFrozenStart: !islandHost ? 0 : Math.min(isVertical ? islandHost.motionStartBounds.y : islandHost.motionStartBounds.x, islandHost.targetAlongPos)
    readonly property real islandFrozenEnd: !islandHost ? 0 : Math.max((isVertical ? islandHost.motionStartBounds.y + islandHost.motionStartBounds.height : islandHost.motionStartBounds.x + islandHost.motionStartBounds.width), islandHost.targetAlongPos + islandHost.targetVisualAlong)
    readonly property bool islandReservesStrip: isIsland && !!islandHost
    readonly property real islandStripClearance: islandSatelliteGap + islandFlareClearance + islandChromeInset
    // Target, not live extent, so widgets return as the sheet starts closing rather than after the spring settles.
    readonly property real islandReachStart: islandReservesStrip ? islandHost.targetAlongPos : 0
    readonly property real islandReachEnd: islandReservesStrip ? islandHost.targetAlongPos + islandHost.targetVisualAlong : 0
    readonly property real islandLeadingSpread: islandMotionRunning ? Math.max(0, islandAlongStart - islandFrozenStart) : 0
    readonly property real islandTrailingSpread: islandMotionRunning ? Math.max(0, islandFrozenEnd - islandAlongEnd) : 0
    readonly property real contentAlongStart: (isVertical ? barUnitInset.y + topBarContent.anchors.topMargin : barUnitInset.x + topBarContent.anchors.leftMargin)
    readonly property real contentAlongEnd: (isVertical ? barUnitInset.y + barUnitInset.height - topBarContent.anchors.bottomMargin : barUnitInset.x + barUnitInset.width - topBarContent.anchors.rightMargin)
    readonly property real leadingSectionSize: _leftSection ? (isVertical ? _leftSection.implicitHeight : _leftSection.implicitWidth) : 0
    readonly property real trailingSectionSize: _rightSection ? (isVertical ? _rightSection.implicitHeight : _rightSection.implicitWidth) : 0
    readonly property real freeSatelliteSeparation: leadingSectionSize > 0 && trailingSectionSize > 0 ? islandSatelliteGap + (islandChromeInset + islandSatelliteSweep) * 2 : 0
    readonly property real freeSatelliteStart: ((isVertical ? height : width) - leadingSectionSize - freeSatelliteSeparation - trailingSectionSize) / 2
    readonly property real islandLeadingOffset: !islandSatellitesHugIsland ? 0 : Math.max(0, islandFree ? freeSatelliteStart - contentAlongStart : islandAlongStart - islandSatelliteGap - islandFlareClearance - islandChromeInset - leadingSectionSize - contentAlongStart)
    readonly property real islandTrailingOffset: !islandSatellitesHugIsland ? 0 : Math.max(0, contentAlongEnd - (islandFree ? freeSatelliteStart + leadingSectionSize + freeSatelliteSeparation + trailingSectionSize : islandAlongEnd + islandSatelliteGap + islandFlareClearance + islandChromeInset + trailingSectionSize))
    // The band moves inside the window when a far-edge bar grows for the sheet; mapToItem alone would not notice.
    readonly property real _bandOrigin: topBarMouseArea.x + topBarMouseArea.y
    // Section rects feed the input masks and the dismiss-window holes; nothing reads them while neither is live.
    readonly property bool sectionRectsLive: clickThroughEnabled || islandSheetOut || (isIsland && !(islandHost?.inputSuspended ?? false))
    readonly property var leadingSectionRect: sectionRectsLive ? sectionRect(_leftSection, false, _revealProgress + islandLeadingOffset + islandTrailingOffset + _bandOrigin) : null
    readonly property var trailingSectionRect: sectionRectsLive ? sectionRect(_rightSection, false, _revealProgress + islandLeadingOffset + islandTrailingOffset + _bandOrigin) : null
    readonly property var centerSectionRect: sectionRectsLive ? sectionRect(_centerSection, true, _revealProgress + _bandOrigin) : null
    property Item islandSlot: null
    readonly property bool configVisible: barConfig?.visible ?? true
    onConfigVisibleChanged: {
        if (!configVisible)
            islandHost?.islandController.requestCollapse();
    }

    function processScrollWheel(wheel) {
        scrollArea.processWheel(wheel);
    }

    property var controlCenterButtonRef: null
    property var clockButtonRef: null
    property var systemUpdateButtonRef: null

    function revealWidgetItem(item) {
        topBarCore.revealSticky = true;
        topBarCore.evaluateReveal();
    }

    function widgetForType(widgetId) {
        return BarWidgetService.resolveWidget(widgetId, {
            screenName: screen?.name,
            barId: barConfig?.id,
            kind: "bar"
        })?.item ?? null;
    }

    function triggerSystemUpdate() {
        if (BarWidgetService.triggerWidgetPopout("systemUpdate", {
            screenName: screen?.name,
            barId: barConfig?.id,
            kind: "bar"
        }))
            return;
        const loader = PopoutService.systemUpdateLoader;
        if (!loader)
            return;
        loader.active = true;
        if (!loader.item)
            return;
        loader.item.screen = screen;
        positionUnresolvedPopout(loader.item, systemUpdateButtonRef);
        PopoutManager.requestPopout(loader.item, undefined, "systemUpdate");
    }

    function positionUnresolvedPopout(popout, item) {
        const section = item?.section || "right";
        const anchor = item ?? dashSectionItem(section);
        if (anchor)
            topBarContent.surfaceContext.positionPopout(popout, anchor, section);
    }

    function triggerControlCenter() {
        if (BarWidgetService.triggerWidgetPopout("controlCenterButton", {
            screenName: screen?.name,
            barId: barConfig?.id,
            kind: "bar"
        }))
            return;
        const loader = PopoutService.controlCenterLoader;
        if (!loader)
            return;
        loader.active = true;
        if (!loader.item)
            return;
        loader.item.triggerScreen = screen;
        positionUnresolvedPopout(loader.item, controlCenterButtonRef);
        loader.item.toggle();
        if (loader.item.shouldBeVisible && NetworkService.wifiEnabled)
            NetworkService.scanWifi();
    }

    function runBarClickAction(action, clickItem, clickX, clickY) {
        switch (action) {
        case "control-center":
            if ((barConfig?.clickActionFollowMouse ?? false) && triggerControlCenterAt(clickItem, clickX, clickY))
                return true;
            triggerControlCenter();
            return true;
        case "spotlight":
            PopoutService.toggleDankLauncherV2();
            return true;
        case "close-window":
            ToplevelManager.activeToplevel?.close();
            return true;
        case "settings":
            PopoutService.toggleSettings();
            return true;
        }
        return false;
    }

    function handleEmptyBarClick(button, clickItem, clickX, clickY) {
        if (button === Qt.MiddleButton)
            return runBarClickAction(barConfig?.middleClickAction ?? "none", clickItem, clickX, clickY);
        if (button === Qt.RightButton)
            return runBarClickAction(barConfig?.rightClickAction ?? "none", clickItem, clickX, clickY);
        return false;
    }

    function triggerControlCenterAt(clickItem, clickX, clickY) {
        const loader = PopoutService.controlCenterLoader;
        if (!loader)
            return false;
        loader.active = true;
        if (!loader.item)
            return false;
        const popout = PopoutService.controlCenterPopout ?? loader.item;
        const context = topBarContent.surfaceContext;
        const point = context?.screenPoint(clickItem, clickX, clickY) ?? null;
        if (popout?.setTriggerPosition && point) {
            const thickness = context.thickness;
            const spacing = barConfig?.spacing ?? 4;
            const position = barConfig?.position ?? 0;
            const trigger = SettingsData.getPopupTriggerPosition(point, screen, thickness, 1, spacing, position, barConfig);
            popout.setTriggerPosition(trigger.x, trigger.y, trigger.width, "center", screen, position, thickness, spacing, barConfig, clickItem);
        }
        loader.item.triggerScreen = screen;
        loader.item.toggle();
        if (loader.item.shouldBeVisible && NetworkService.wifiEnabled)
            NetworkService.scanWifi();
        return true;
    }

    function dashSectionItem(section) {
        const vertical = barWindow.isVertical;
        switch (section) {
        case "left":
            return vertical ? topBarContent.vLeftSection : topBarContent.hLeftSection;
        case "right":
            return vertical ? topBarContent.vRightSection : topBarContent.hRightSection;
        default:
            return vertical ? topBarContent.vCenterSection : topBarContent.hCenterSection;
        }
    }

    function positionDash(popout, position) {
        const clock = widgetForType("clock");
        const explicit = position === "left" || position === "center" || position === "right";
        const section = explicit ? position : (clock?.section || "center");
        const sectionItem = dashSectionItem(section);
        const anchorClock = clock && (!explicit && (section !== "center" || (hostsIsland && SettingsData.islandWidgetSection(barConfig) === "center")) || !sectionItem);
        const item = anchorClock ? clock : sectionItem;
        if (!item || !topBarContent.surfaceContext.positionPopout(popout, item, section, anchorClock ? undefined : sectionItem))
            popout.triggerScreen = barWindow.screen;
        return section;
    }

    function triggerDashTab(tabId, position) {
        const loader = PopoutService.dankDashPopoutLoader;
        if (!loader)
            return false;
        loader.active = true;
        if (!loader.item) {
            return false;
        }

        revealWidgetItem(null);
        const section = positionDash(loader.item, position);
        if (loader.item.requestTab)
            loader.item.requestTab(tabId);
        PopoutManager.requestPopout(loader.item, undefined, (barConfig?.id ?? "default") + "-" + section + "-" + tabId);
        return true;
    }

    function triggerWallpaperBrowser() {
        triggerDashTab("wallpaper");
    }

    property var blurRegion: null
    property var _blurWidgetItems: []

    function registerBlurWidget(item) {
        if (_blurWidgetItems.indexOf(item) >= 0)
            return;
        _blurWidgetItems = _blurWidgetItems.concat([item]);
        _blurRebuildTimer.restart();
    }

    function unregisterBlurWidget(item) {
        const idx = _blurWidgetItems.indexOf(item);
        if (idx < 0)
            return;
        const arr = _blurWidgetItems.slice();
        arr.splice(idx, 1);
        _blurWidgetItems = arr;
        _blurRebuildTimer.restart();
    }

    function refreshBlurRegion() {
        if (!blurRegion)
            return;
        blurRegion.changed();
    }

    Timer {
        id: _blurRebuildTimer
        interval: 1
        onTriggered: barBlur.rebuild()
    }

    onUsesConnectedFrameChromeChanged: _blurRebuildTimer.restart()
    // Rebuild immediately so the bar region never overlaps FrameWindow's during chrome handoff
    onUsesFrameBarChromeChanged: barBlur.rebuild()
    onBarRevealedChanged: barBlur.rebuild()

    Component {
        id: blurRegionComp
        Region {}
    }

    Component {
        id: blurSubRegionComp
        Region {
            property Item w
            item: w
            radius: w?.blurRadius ?? Theme.cornerRadius
        }
    }

    Component {
        id: blurWingRegionComp

        Region {
            id: wingRegion

            property Item wing

            readonly property real sx: topBarMouseArea.x + barUnitInset.x + topBarSlide.x + barBackground.x
            readonly property real sy: topBarMouseArea.y + barUnitInset.y + topBarSlide.y + barBackground.y

            x: sx + wing.x
            y: sy + wing.y
            width: wing.width
            height: wing.height

            Region {
                intersection: Intersection.Subtract
                shape: RegionShape.Ellipse
                x: wingRegion.x + wingRegion.wing.discRect.x
                y: wingRegion.y + wingRegion.wing.discRect.y
                width: wingRegion.wing.discRect.width
                height: wingRegion.wing.discRect.height
            }
        }
    }

    Component {
        id: blurIslandRegionComp

        // Region geometry is int; keep it a pixel inside the fill so its antialiased edge never shows raw blur.
        Region {
            readonly property real left: topBarMouseArea.x + islandLoader.x + topBarSlide.x + (barWindow.islandHost?.currentVisualX ?? 0)
            readonly property real top: topBarMouseArea.y + islandLoader.y + topBarSlide.y + (barWindow.islandHost?.currentVisualY ?? 0)

            function inset(r) {
                return r > 0 ? Math.ceil(r) + 1 : 0;
            }

            x: Math.ceil(left) + 1
            y: Math.ceil(top) + 1
            width: Math.max(0, Math.floor(left + (barWindow.islandHost?.currentVisualWidth ?? 0)) - 1 - x)
            height: Math.max(0, Math.floor(top + (barWindow.islandHost?.currentVisualHeight ?? 0)) - 1 - y)
            topLeftRadius: inset(barWindow.islandHost?.surface.surfaceMotion.currentTopLeftRadius ?? 0)
            topRightRadius: inset(barWindow.islandHost?.surface.surfaceMotion.currentTopRightRadius ?? 0)
            bottomLeftRadius: inset(barWindow.islandHost?.surface.surfaceMotion.currentBottomLeftRadius ?? 0)
            bottomRightRadius: inset(barWindow.islandHost?.surface.surfaceMotion.currentBottomRightRadius ?? 0)
        }
    }

    Component {
        id: blurIslandJoinRegionComp

        Region {
            id: joinRegion

            property Item corner

            readonly property real sx: topBarMouseArea.x + islandLoader.x + topBarSlide.x
            readonly property real sy: topBarMouseArea.y + islandLoader.y + topBarSlide.y

            x: sx + corner.x
            y: sy + corner.y
            width: corner.width
            height: corner.height

            Region {
                intersection: Intersection.Subtract
                shape: RegionShape.Ellipse
                x: joinRegion.x + joinRegion.corner.discRect.x
                y: joinRegion.y + joinRegion.corner.discRect.y
                width: joinRegion.corner.discRect.width
                height: joinRegion.corner.discRect.height
            }
        }
    }

    Component {
        id: blurSatelliteRegionComp

        Region {
            id: satelliteRegion

            property Item surface

            readonly property real sx: topBarMouseArea.x + barUnitInset.x + topBarSlide.x + surface.x
            readonly property real sy: topBarMouseArea.y + barUnitInset.y + topBarSlide.y + surface.y
            readonly property bool horizontal: !surface.isVertical
            readonly property bool far: surface.crossFar
            readonly property int startR: Math.round(surface.alongStartRadius)
            readonly property int endR: Math.round(surface.alongEndRadius)

            x: sx
            y: sy
            width: surface.width
            height: surface.height
            topLeftRadius: far ? startR : 0
            topRightRadius: horizontal ? (far ? endR : 0) : (far ? 0 : startR)
            bottomLeftRadius: horizontal ? (far ? 0 : startR) : (far ? endR : 0)
            bottomRightRadius: far ? 0 : endR

            Region {
                x: satelliteRegion.sx + satelliteRegion.surface.startSweepRect.x
                y: satelliteRegion.sy + satelliteRegion.surface.startSweepRect.y
                width: satelliteRegion.surface.startSweepRect.width
                height: satelliteRegion.surface.startSweepRect.height

                Region {
                    intersection: Intersection.Subtract
                    shape: RegionShape.Ellipse
                    x: satelliteRegion.sx + satelliteRegion.surface.startSweepDisc.x
                    y: satelliteRegion.sy + satelliteRegion.surface.startSweepDisc.y
                    width: satelliteRegion.surface.startSweepDisc.width
                    height: satelliteRegion.surface.startSweepDisc.height
                }
            }

            Region {
                x: satelliteRegion.sx + satelliteRegion.surface.endSweepRect.x
                y: satelliteRegion.sy + satelliteRegion.surface.endSweepRect.y
                width: satelliteRegion.surface.endSweepRect.width
                height: satelliteRegion.surface.endSweepRect.height

                Region {
                    intersection: Intersection.Subtract
                    shape: RegionShape.Ellipse
                    x: satelliteRegion.sx + satelliteRegion.surface.endSweepDisc.x
                    y: satelliteRegion.sy + satelliteRegion.surface.endSweepDisc.y
                    width: satelliteRegion.surface.endSweepDisc.width
                    height: satelliteRegion.surface.endSweepDisc.height
                }
            }
        }
    }

    Component {
        id: blurCornerRegionComp

        // The surface paints square corners at the attached edge and the wing roots (#2975); re-add what the body radius rounds off
        Region {
            id: cornerRegion

            property bool atRight: false
            property bool atBottom: false

            readonly property real r: barBackground.rt
            readonly property bool attachedEdgeCorner: (barBackground.isTop && !atBottom) || (barBackground.isBottom && atBottom) || (barBackground.isLeft && !atRight) || (barBackground.isRight && atRight)
            readonly property bool wingEdgeCorner: (barBackground.isTop && atBottom) || (barBackground.isBottom && !atBottom) || (barBackground.isLeft && atRight) || (barBackground.isRight && !atRight)
            readonly property bool gothCorner: barBackground.alongWings ? attachedEdgeCorner : wingEdgeCorner
            readonly property bool squared: (barBackground.edgeAttached && attachedEdgeCorner) || (barBackground.gothEnabled && gothCorner)

            x: topBarMouseArea.x + barUnitInset.x + topBarSlide.x + (atRight ? barUnitInset.width - r : 0)
            y: topBarMouseArea.y + barUnitInset.y + topBarSlide.y + (atBottom ? barUnitInset.height - r : 0)
            width: squared ? r : 0
            height: squared ? r : 0
        }
    }

    Item {
        id: barBlur
        visible: false

        readonly property bool barHasTransparency: !barWindow.isIsland && barWindow._backgroundAlpha > 0 && barWindow._backgroundAlpha < 1
        readonly property bool islandTranslucent: !!barWindow.islandHost && barWindow.islandHost.surfaceOpacity > 0 && barWindow.islandHost.surfaceOpacity < 1
        readonly property bool islandNotch: barWindow.islandHost?.notch ?? false
        readonly property bool satelliteTranslucent: barWindow.islandSatelliteBackground && barWindow.islandSatellitesEnabled && barWindow.islandSatelliteOpacity > 0 && barWindow.islandSatelliteOpacity < 1

        function rebuild() {
            teardown();
            if (!BlurService.enabled || !BlurService.available)
                return;
            if (!barWindow.barRevealed && CompositorService.isHyprland)
                return;
            // FrameWindow owns the blur region for the whole edge while the bar wears frame chrome
            if (FrameTransitionState.effectiveFrameEnabled && barWindow.usesFrameBarChrome)
                return;

            const widgets = barWindow._blurWidgetItems.filter(w => w && w.visible && w.width > 0 && w.height > 0);
            const hasBar = barHasTransparency;
            if (!hasBar && widgets.length === 0 && !islandTranslucent && !satelliteTranslucent)
                return;

            const region = blurRegionComp.createObject(barWindow);
            if (!region) {
                log.warn("BarBlur: Failed to create blur region");
                return;
            }

            if (hasBar) {
                region.x = Qt.binding(() => topBarMouseArea.x + barUnitInset.x + topBarSlide.x);
                region.y = Qt.binding(() => topBarMouseArea.y + barUnitInset.y + topBarSlide.y);
                region.width = Qt.binding(() => barUnitInset.width);
                region.height = Qt.binding(() => barUnitInset.height);
                region.radius = Qt.binding(() => barBackground.rt);
            }

            const subRegions = [];
            if (islandTranslucent) {
                const islandSub = blurIslandRegionComp.createObject(region);
                if (islandSub)
                    subRegions.push(islandSub);
                for (const corner of barWindow.islandHost.notch ? barWindow.islandHost.surface.joinCorners : []) {
                    const sub = blurIslandJoinRegionComp.createObject(region, {
                        corner: corner
                    });
                    if (sub)
                        subRegions.push(sub);
                }
            }
            if (satelliteTranslucent) {
                for (const surface of [leadingSatelliteSurface, trailingSatelliteSurface]) {
                    const sub = blurSatelliteRegionComp.createObject(region, {
                        surface: surface
                    });
                    if (sub)
                        subRegions.push(sub);
                }
            }
            for (let i = 0; i < widgets.length; i++) {
                const sub = blurSubRegionComp.createObject(region, {
                    w: widgets[i]
                });
                if (sub)
                    subRegions.push(sub);
            }

            if (hasBar && barBackground.gothEnabled && barWindow._wingR > 0) {
                for (const wingItem of [barBackground.leadingWing, barBackground.trailingWing]) {
                    if (!wingItem.visible)
                        continue;
                    const wing = blurWingRegionComp.createObject(region, {
                        wing: wingItem
                    });
                    if (wing)
                        subRegions.push(wing);
                }
            }

            if (hasBar) {
                for (const atRight of [false, true]) {
                    for (const atBottom of [false, true]) {
                        const corner = blurCornerRegionComp.createObject(region, {
                            atRight: atRight,
                            atBottom: atBottom
                        });
                        if (corner)
                            subRegions.push(corner);
                    }
                }
            }

            region.regions = subRegions;

            barWindow.blurRegion = region;
        }

        function teardown() {
            const old = barWindow.blurRegion;
            if (!old)
                return;
            barWindow.blurRegion = null;
            old.destroy();
        }

        onBarHasTransparencyChanged: _blurRebuildTimer.restart()
        onIslandTranslucentChanged: _blurRebuildTimer.restart()
        onIslandNotchChanged: _blurRebuildTimer.restart()
        onSatelliteTranslucentChanged: _blurRebuildTimer.restart()

        readonly property bool blurServiceEnabled: BlurService.enabled
        readonly property bool frameEffectiveEnabled: FrameTransitionState.effectiveFrameEnabled

        onBlurServiceEnabledChanged: rebuild()
        onFrameEffectiveEnabledChanged: rebuild()

        Component.onCompleted: rebuild()
        Component.onDestruction: teardown()
    }

    property alias axis: axis

    AxisContext {
        id: axis
        edge: {
            switch (barConfig?.position ?? 0) {
            case SettingsData.Position.Top:
                return "top";
            case SettingsData.Position.Bottom:
                return "bottom";
            case SettingsData.Position.Left:
                return "left";
            case SettingsData.Position.Right:
                return "right";
            default:
                return "top";
            }
        }
    }

    readonly property bool isVertical: axis.isVertical

    readonly property color _hostSurface: SettingsData.barSurfaceColor(barConfig)
    readonly property string _barId: barConfig?.id ?? "default"
    readonly property real _backgroundAlpha: SettingsData.barTransparency(barConfig)
    readonly property color _bgColor: (FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) ? Theme.frameSurfaceColor : Theme.withAlpha(_hostSurface, _backgroundAlpha)
    readonly property real _dpr: CompositorService.getScreenScale(barWindow.screen)

    property string screenName: modelData.name

    readonly property bool usesConnectedFrameChrome: CompositorService.usesConnectedFrameChromeForScreen(screenName)
    readonly property bool usesFrameBarChrome: CompositorService.frameWindowVisibleForScreen(screenName)
    readonly property var renderBarConfig: SettingsData.effectiveBarConfigForRender(barConfig, usesFrameBarChrome)

    property bool gothCornersEnabled: renderBarConfig?.gothCornersEnabled ?? false
    readonly property real _wingR: BarMetrics.gothRadius(renderBarConfig)

    // Shadow buffer: extra window space for shadow to render beyond bar bounds
    readonly property bool _shadowActive: Theme.elevationEnabled && (typeof SettingsData !== "undefined" ? (SettingsData.barElevationEnabled ?? true) : false)
    readonly property real _shadowBuffer: {
        if (!_shadowActive)
            return 0;
        const hasOverride = (renderBarConfig?.shadowIntensity ?? 0) > 0;
        if (hasOverride) {
            const blur = (renderBarConfig.shadowIntensity ?? 0) * 0.2;
            const offset = blur * 0.5;
            return Theme.snap(Math.max(16, blur + offset + 8), _dpr);
        }
        return Theme.snap(Theme.elevationRenderPadding(Theme.elevationLevel2, "top", 4, 8, 16), _dpr);
    }

    // Flatten/spacing collapse for maximized windows only applies to frame-integrated layout
    readonly property bool flattenForMaximizedWindow: !FrameTransitionState.effectiveFrameEnabled || usesFrameBarChrome

    property bool hasMaximizedToplevel: false
    property bool shouldHideForWindows: false

    function _updateHasMaximizedToplevel() {
        hasMaximizedToplevel = (barConfig?.maximizeDetection ?? true) && CompositorService.maximizedWindowOnScreen(screenName);
    }

    function _updateShouldHideForWindows() {
        if (!(barConfig?.showOnWindowsOpen ?? false) || !(barConfig?.autoHide ?? false)) {
            shouldHideForWindows = false;
            return;
        }
        shouldHideForWindows = CompositorService.windowsHideBar(screenName, barConfig?.position ?? 0, barWindow.effectiveBarThickness + (barConfig?.spacing ?? 4), barWindow.screen?.width ?? 0, barWindow.screen?.height ?? 0);
    }

    readonly property bool edgeAttached: (barConfig?.attachToScreenEdge ?? false) && !(FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome)
    readonly property string barLengthMode: isIsland || (FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) ? "full" : (barConfig?.barLengthMode ?? "full")
    readonly property bool fitToWidgets: barLengthMode === "fit"
    readonly property bool spansEdge: barLengthMode === "full" && ((FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) || (barConfig?.barLengthPadding ?? 0) <= 0)
    property bool _fitSettled: false
    property real effectiveSpacing: isIsland || (FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) ? 0 : ((edgeAttached || (flattenForMaximizedWindow && hasMaximizedToplevel)) ? 0 : (barConfig?.spacing ?? 4))

    property real renderedSpacing: effectiveSpacing
    readonly property real surfaceSpacing: Math.max(effectiveSpacing, renderedSpacing)

    Behavior on renderedSpacing {
        enabled: (barWindow.hostWindow?.visible ?? false) && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    readonly property int notificationCount: NotificationService.notifications.length
    readonly property real effectiveBarThickness: (FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) ? SettingsData.frameBarSize : Theme.barThickness(barConfig?.innerPadding ?? 2, _dpr)
    readonly property real effectiveBarLengthPadding: {
        if (barLengthMode === "percent") {
            const percent = Math.min(100, Math.max(10, barConfig?.barLengthPercent ?? 80));
            return fittedAvailableLength * (1 - percent / 100) / 2;
        }
        if ((FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) || (flattenForMaximizedWindow && hasMaximizedToplevel))
            return 0;
        const pad = Math.max(0, barConfig?.barLengthPadding ?? 0);
        const length = isVertical ? height : width;
        return length > 0 ? Math.min(pad, Math.max(0, length / 2 - renderedSpacing)) : pad;
    }
    readonly property real fittedAvailableLength: {
        const length = isVertical ? topBarMouseArea.height : topBarMouseArea.width;
        const startGap = isVertical && hasAdjacentTopBar ? 0 : renderedSpacing;
        const endGap = isVertical && hasAdjacentBottomBar ? 0 : renderedSpacing;
        return Math.max(0, length - startGap - endGap);
    }
    property real fittedLeadingPad: fitToWidgets ? Math.max(0, topBarContent.fittedLeadingPad) : 0
    property real fittedTrailingPad: fitToWidgets ? Math.max(0, topBarContent.fittedTrailingPad) : 0
    readonly property int lengthPaddingStartPx: Theme.px(fitToWidgets ? fittedLeadingPad : effectiveBarLengthPadding, _dpr)
    readonly property int lengthPaddingEndPx: Theme.px(fitToWidgets ? fittedTrailingPad : effectiveBarLengthPadding, _dpr)
    readonly property bool fitAnimated: fitToWidgets && _fitSettled && (hostWindow?.visible ?? false) && !SettingsData.reduceMotion

    Behavior on fittedLeadingPad {
        enabled: barWindow.fitAnimated
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on fittedTrailingPad {
        enabled: barWindow.fitAnimated
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    DeferredAction {
        id: fitSettle
        onTriggered: barWindow._fitSettled = true
    }
    readonly property bool effectiveOpenOnOverview: (FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome) ? SettingsData.frameShowOnOverview : (barConfig?.openOnOverview ?? false)
    readonly property real widgetThickness: Theme.barWidgetThickness(barConfig?.innerPadding ?? 2, _dpr, isIsland ? -1 : (barConfig?.widgetInset ?? -1), effectiveBarThickness)

    readonly property bool hasAdjacentTopBar: isVertical && ShellLayout.adjacentBar(screen, "top", barConfig) !== null
    readonly property bool hasAdjacentBottomBar: isVertical && ShellLayout.adjacentBar(screen, "bottom", barConfig) !== null
    readonly property bool hasAdjacentLeftBar: !isVertical && ShellLayout.adjacentBar(screen, "left", barConfig) !== null
    readonly property bool hasAdjacentRightBar: !isVertical && ShellLayout.adjacentBar(screen, "right", barConfig) !== null

    readonly property real taskbarStartInset: SettingsData.taskbarInsetForEdge(screen, isVertical ? "top" : "left")
    readonly property real taskbarEndInset: SettingsData.taskbarInsetForEdge(screen, isVertical ? "bottom" : "right")

    readonly property real barSurfaceThickness: Theme.px(effectiveBarThickness + surfaceSpacing + ((renderBarConfig?.gothCornersEnabled ?? false) && !hasMaximizedToplevel && spansEdge ? _wingR : 0), _dpr) + _shadowBuffer
    readonly property bool islandSheetOut: islandHost?.sheetOut ?? false
    readonly property real islandSatelliteShadowBuffer: isIsland && islandSatellitesEnabled && !islandSatelliteBackground ? _shadowBuffer : 0
    // A grown layer surface jumps to its new origin before the client draws at the new size, so a far-edge host never grows for the sheet.
    readonly property bool islandReservesSheet: !!islandHost && (axis.edge === "bottom" || axis.edge === "right")
    readonly property real hostThickness: isIsland ? Math.max(islandHost?.hostThickness ?? 0, islandStripThickness + islandSatelliteShadowBuffer) : Math.max(barSurfaceThickness, islandSheetOut || islandReservesSheet ? islandHost.hostThickness : 0)
    // The host reserves the expanded island's height, so sliding by it would move a compact island off-screen within a frame.
    readonly property real islandCompactThickness: Math.max(islandStripThickness + islandSatelliteShadowBuffer, (islandHost?.outerGap ?? 0) + (islandHost?.compactThickness ?? 0) + (islandHost?.shadowPadding ?? 0))
    readonly property real hideSlideThickness: isIsland ? islandCompactThickness : barSurfaceThickness
    readonly property real surfaceImplicitHeight: !isVertical ? hostThickness : 0
    readonly property real surfaceImplicitWidth: isVertical ? hostThickness : 0

    Component.onCompleted: {
        _updateHasMaximizedToplevel();
        _updateShouldHideForWindows();
        fitSettle.schedule();
    }

    Connections {
        target: PluginService
        function onPluginLoaded(pluginId) {
            log.info("DankBar: Plugin loaded:", pluginId);
            SettingsData.widgetDataChanged();
        }
        function onPluginUnloaded(pluginId) {
            log.info("DankBar: Plugin unloaded:", pluginId);
            SettingsData.widgetDataChanged();
        }
    }

    readonly property var rootWindowBarConfig: rootWindow.barConfig

    onRootWindowBarConfigChanged: {
        _updateHasMaximizedToplevel();
        _updateShouldHideForWindows();
    }

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            barWindow._updateHasMaximizedToplevel();
            barWindow._updateShouldHideForWindows();
        }
        function onWorkspaceStateChanged() {
            barWindow._updateHasMaximizedToplevel();
            barWindow._updateShouldHideForWindows();
        }
    }

    readonly property int barPos: barConfig?.position ?? 0

    readonly property bool reserveExclusiveWhenAutoHidden: FrameTransitionState.effectiveFrameEnabled && usesFrameBarChrome && !!barWindow.screen && SettingsData.isScreenInPreferences(barWindow.screen, SettingsData.frameScreenPreferences)

    readonly property real surfaceExclusiveZone: isIsland ? ((islandFree || (islandHost?.floating ?? false)) ? 0 : SettingsData.islandReserveThickness(barConfig)) : (!(barConfig?.visible ?? true) || (topBarCore.autoHide && !barWindow.reserveExclusiveWhenAutoHidden)) ? -1 : (barWindow.effectiveBarThickness + effectiveSpacing + (usesFrameBarChrome ? 0 : (barConfig?.bottomGap ?? 0)))

    readonly property alias inputMaskItem: inputMask

    Item {
        id: inputMask

        readonly property int barThickness: Theme.px(barWindow.isIsland ? barWindow.islandStripThickness : barWindow.effectiveBarThickness + barWindow.surfaceSpacing, barWindow._dpr)
        readonly property bool inOverviewWithShow: CompositorService.overviewActiveOnScreen(barWindow.screenName) && barWindow.effectiveOpenOnOverview
        readonly property bool effectiveVisible: (barConfig?.visible ?? true) || inOverviewWithShow || topBarCore.islandPinsReveal
        readonly property bool showing: effectiveVisible && (topBarCore.reveal || inOverviewWithShow)

        readonly property int maskThickness: showing ? barThickness : 1

        x: {
            if (!axis.isVertical) {
                return barWindow.lengthPaddingStartPx + barWindow.taskbarStartInset;
            } else {
                switch (barPos) {
                case SettingsData.Position.Left:
                    return 0;
                case SettingsData.Position.Right:
                    return parent.width - maskThickness;
                default:
                    return 0;
                }
            }
        }
        y: {
            if (axis.isVertical) {
                return barWindow.lengthPaddingStartPx + barWindow.taskbarStartInset;
            } else {
                switch (barPos) {
                case SettingsData.Position.Top:
                    return 0;
                case SettingsData.Position.Bottom:
                    return parent.height - maskThickness;
                default:
                    return 0;
                }
            }
        }
        width: axis.isVertical ? maskThickness : Math.max(0, parent.width - barWindow.lengthPaddingStartPx - barWindow.lengthPaddingEndPx - barWindow.taskbarStartInset - barWindow.taskbarEndInset)
        height: axis.isVertical ? Math.max(0, parent.height - barWindow.lengthPaddingStartPx - barWindow.lengthPaddingEndPx - barWindow.taskbarStartInset - barWindow.taskbarEndInset) : maskThickness
    }

    readonly property bool clickThroughEnabled: barConfig?.clickThrough ?? false

    readonly property var _leftSection: topBarContent ? (barWindow.isVertical ? topBarContent.vLeftSection : topBarContent.hLeftSection) : null
    readonly property var _centerSection: topBarContent ? (barWindow.isVertical ? topBarContent.vCenterSection : topBarContent.hCenterSection) : null
    readonly property var _rightSection: topBarContent ? (barWindow.isVertical ? topBarContent.vRightSection : topBarContent.hRightSection) : null
    readonly property real _revealProgress: topBarSlide.x + topBarSlide.y

    function containsGlobalPoint(gx, gy, padding) {
        const pad = padding !== undefined ? padding : 16;
        if (!inputMask.showing)
            return false;
        const topLeft = topBarContent.surfaceContext.screenPoint(inputMask, 0, 0);
        return gx >= topLeft.x - pad && gx < topLeft.x + inputMask.width + pad && gy >= topLeft.y - pad && gy < topLeft.y + inputMask.height + pad;
    }

    // On-demand read for fixtures; the bound rects are null while nothing consumes them.
    function sectionRectFor(sectionId) {
        return sectionId === "center" ? sectionRect(_centerSection, true, 0) : sectionRect(sectionId === "left" ? _leftSection : _rightSection, false, 0);
    }

    function sectionRect(section, isCenter, _dep) {
        if (!section)
            return {
                "x": 0,
                "y": 0,
                "w": 0,
                "h": 0
            };

        const pos = section.mapToItem(barWindow.hostWindow.contentItem, 0, 0);
        const implW = section.implicitWidth || 0;
        const implH = section.implicitHeight || 0;
        const contentSize = isCenter ? (section.contentSize || 0) : 0;
        const spread = !barWindow.islandSatellitesHugIsland || isCenter ? 0 : (section === barWindow._leftSection ? barWindow.islandLeadingSpread : barWindow.islandTrailingSpread);
        const spreadBefore = section === barWindow._rightSection ? spread : 0;

        let offsetX = isCenter && !barWindow.isVertical ? (section.width - implW) / 2 : 0;
        let offsetY = !barWindow.isVertical ? (section.height - implH) / 2 : (isCenter ? (section.height - implH) / 2 : 0);
        let w = implW;
        let h = implH;

        // index centering lays content out asymmetrically; use the real extent
        if (contentSize > 0) {
            if (barWindow.isVertical) {
                offsetY = section.contentStart;
                h = contentSize;
            } else {
                offsetX = section.contentStart;
                w = contentSize;
            }
        }

        const edgePad = Theme.spacingXXS;
        return {
            "x": pos.x + offsetX - edgePad - (barWindow.isVertical ? 0 : spreadBefore),
            "y": pos.y + offsetY - edgePad - (barWindow.isVertical ? spreadBefore : 0),
            "w": w + edgePad * 2 + (barWindow.isVertical ? 0 : spread),
            "h": h + edgePad * 2 + (barWindow.isVertical ? spread : 0)
        };
    }

    Item {
        id: topBarCore
        anchors.fill: parent
        layer.enabled: false

        property bool autoHide: (!barWindow.isIsland || barWindow.islandOverlay) && (barConfig?.autoHide ?? false)
        property bool revealSticky: false
        // In click-through mode the hidden bar's input mask covers the full
        // band while the revealed bar's mask covers only the widget sections,
        // so the pointer position is unknowable while it is over a gap. An
        // enter on the hidden bar therefore only reveals once the pointer
        // reaches a thin strip at the screen edge; anything else (including
        // the spurious enter generated by the mask expanding underneath a
        // resting pointer) keeps the bar hidden.
        property bool gapEnterSuppressed: false
        readonly property bool hoverReveal: topBarMouseArea.containsMouse && !gapEnterSuppressed
        readonly property bool ipcReveal: !!SettingsData.barIpcRevealStates[barConfig?.id ?? ""]

        onRevealChanged: {
            if (reveal && barWindow.clickThroughEnabled)
                revealSettle.restart();
        }

        // The input mask updates lag reveal transitions, generating spurious
        // enter/leave pairs. Hides are deferred until the transition settles;
        // the timer re-evaluates against the post-transition mask.
        Timer {
            id: revealSettle
            interval: 600
            repeat: false
            onTriggered: topBarCore.evaluateReveal()
        }

        function inEdgeStrip(x, y) {
            const band = barWindow.isVertical ? topBarMouseArea.width : topBarMouseArea.height;
            const strip = Math.max(8, band * 0.15);
            switch (barPos) {
            case SettingsData.Position.Bottom:
                return y >= band - strip;
            case SettingsData.Position.Left:
                return x <= strip;
            case SettingsData.Position.Right:
                return x >= band - strip;
            default:
                return y <= strip;
            }
        }

        Timer {
            id: revealHold
            interval: barConfig?.autoHideDelay ?? 250
            repeat: false
            onTriggered: {
                if (!topBarCore.hoverReveal && !topBarCore.popoutPinsReveal && !topBarCore.islandPinsReveal)
                    topBarCore.revealSticky = false;
            }
        }

        property bool hasActivePopout: false

        readonly property bool popoutPinsReveal: !!(hasActivePopout && !(barConfig?.autoHideStrict ?? false))
        readonly property bool islandPinsReveal: !!barWindow.islandHost && (barWindow.islandHost.sheetOut || barWindow.islandHost.transientActive)

        onHasActivePopoutChanged: evaluateReveal()

        onPopoutPinsRevealChanged: evaluateReveal()

        onIslandPinsRevealChanged: evaluateReveal()

        function updateActivePopoutState() {
            if (!barWindow.screen)
                return;
            const screenName = barWindow.screen.name;
            const activePopout = PopoutManager.currentPopoutsByScreen[screenName];
            const activeTrayMenu = TrayMenuManager.activeTrayMenus[screenName];
            const trayOpen = rootWindow.systemTrayMenuOpen;

            const origin = activePopout?.sourceRegistration?.context;
            const hasVisiblePopout = activePopout?.shouldBeVisible && (!origin || (origin.kind === "bar" && origin.barId === barConfig?.id));
            topBarCore.hasActivePopout = !!(hasVisiblePopout || activeTrayMenu || trayOpen);
        }

        Connections {
            target: PopoutManager

            function onPopoutChanged() {
                topBarCore.updateActivePopoutState();
            }

            function onPopoutOpening() {
                topBarCore.evaluateReveal();
            }
        }

        readonly property var trayActiveMenus: TrayMenuManager.activeTrayMenus

        onTrayActiveMenusChanged: updateActivePopoutState()

        property bool reveal: {
            const inOverviewWithShow = CompositorService.overviewActiveOnScreen(barWindow.screenName) && barWindow.effectiveOpenOnOverview;
            if (inOverviewWithShow)
                return true;

            const showOnWindowsSetting = barConfig?.showOnWindowsOpen ?? false;
            if (showOnWindowsSetting && autoHide && CompositorService.windowOverlapSupported) {
                if (barWindow.shouldHideForWindows)
                    return hoverReveal || popoutPinsReveal || islandPinsReveal || revealSticky || ipcReveal;
                return true;
            }

            if (CompositorService.overviewActiveOnScreen(barWindow.screenName))
                return hoverReveal || popoutPinsReveal || islandPinsReveal || revealSticky || ipcReveal;

            return ((barConfig?.visible ?? true) || islandPinsReveal) && (!autoHide || hoverReveal || popoutPinsReveal || islandPinsReveal || revealSticky || ipcReveal);
        }

        readonly property var rootWindowBarConfig: rootWindow.barConfig

        onRootWindowBarConfigChanged: {
            autoHide = (!barWindow.isIsland || barWindow.islandOverlay) && (barConfig?.autoHide ?? false);
            evaluateReveal();
        }

        Component.onCompleted: topBarCore.updateActivePopoutState()

        function evaluateReveal() {
            if (!autoHide) {
                revealHold.stop();
                revealSticky = false;
                return;
            }

            if (topBarMouseArea.containsMouse && !gapEnterSuppressed) {
                SettingsData.setBarIpcReveal(barConfig?.id ?? "", false);
                revealSticky = true;
                revealHold.stop();
                return;
            }

            if (popoutPinsReveal || islandPinsReveal) {
                revealSticky = true;
                revealHold.stop();
                return;
            }

            if (revealSettle.running)
                return;

            revealHold.interval = barConfig?.autoHideDelay ?? 250;
            revealHold.restart();
        }

        MouseArea {
            id: topBarMouseArea
            onContainsMouseChanged: {
                if (!containsMouse) {
                    topBarCore.gapEnterSuppressed = false;
                } else if (barWindow.clickThroughEnabled && !topBarCore.reveal) {
                    topBarCore.gapEnterSuppressed = true;
                }
                topBarCore.evaluateReveal();
            }
            // Switching stretch anchors can leave stale dimensions after an orientation change
            x: barWindow.isIsland ? 0 : !barWindow.isVertical ? barWindow.taskbarStartInset : barPos === SettingsData.Position.Right ? parent.width - width : 0
            y: barWindow.isIsland ? 0 : barWindow.isVertical ? barWindow.taskbarStartInset : barPos === SettingsData.Position.Bottom ? parent.height - height : 0
            width: barWindow.isIsland ? parent.width : barWindow.isVertical ? Theme.px(barWindow.effectiveBarThickness + barWindow.surfaceSpacing, barWindow._dpr) : Math.max(0, parent.width - barWindow.taskbarStartInset - barWindow.taskbarEndInset)
            height: barWindow.isIsland ? parent.height : !barWindow.isVertical ? Theme.px(barWindow.effectiveBarThickness + barWindow.surfaceSpacing, barWindow._dpr) : Math.max(0, parent.height - barWindow.taskbarStartInset - barWindow.taskbarEndInset)
            readonly property bool inOverview: CompositorService.overviewActiveOnScreen(barWindow.screenName) && barWindow.effectiveOpenOnOverview
            hoverEnabled: topBarCore.autoHide && !inOverview && !topBarCore.popoutPinsReveal
            acceptedButtons: barWindow.clickThroughEnabled || barWindow.isIsland ? Qt.NoButton : Qt.RightButton
            enabled: !inOverview && (topBarCore.autoHide || !barWindow.clickThroughEnabled)
            onPositionChanged: mouse => {
                if (!topBarCore.gapEnterSuppressed)
                    return;
                if (!topBarCore.inEdgeStrip(mouse.x, mouse.y))
                    return;
                topBarCore.gapEnterSuppressed = false;
                topBarCore.evaluateReveal();
            }

            Item {
                id: topBarContainer
                anchors.fill: parent

                transform: Translate {
                    id: topBarSlide
                    x: barWindow.isVertical ? Theme.snap(topBarCore.reveal ? 0 : (barPos === SettingsData.Position.Right ? barWindow.hideSlideThickness : -barWindow.hideSlideThickness), barWindow._dpr) : 0
                    y: !barWindow.isVertical ? Theme.snap(topBarCore.reveal ? 0 : (barPos === SettingsData.Position.Bottom ? barWindow.hideSlideThickness : -barWindow.hideSlideThickness), barWindow._dpr) : 0
                    onXChanged: barWindow.refreshBlurRegion()
                    onYChanged: barWindow.refreshBlurRegion()

                    Behavior on x {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on y {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Item {
                    id: barUnitInset
                    property int spacingPx: Theme.px(barWindow.renderedSpacing, barWindow._dpr)
                    readonly property int islandBandPx: Theme.px(barWindow.islandStripThickness, barWindow._dpr)
                    anchors.fill: parent
                    anchors.leftMargin: barWindow.isIsland ? (barWindow.isVertical ? (axis.edge === "left" ? 0 : parent.width - islandBandPx) : barWindow.taskbarStartInset) : !barWindow.isVertical ? spacingPx + barWindow.lengthPaddingStartPx : (axis.edge === "left" ? spacingPx : 0)
                    anchors.rightMargin: barWindow.isIsland ? (barWindow.isVertical ? (axis.edge === "right" ? 0 : parent.width - islandBandPx) : barWindow.taskbarEndInset) : !barWindow.isVertical ? spacingPx + barWindow.lengthPaddingEndPx : (axis.edge === "right" ? spacingPx : 0)
                    anchors.topMargin: barWindow.isIsland ? (barWindow.isVertical ? barWindow.taskbarStartInset : (axis.edge === "top" ? 0 : parent.height - islandBandPx)) : barWindow.isVertical ? (barWindow.hasAdjacentTopBar ? 0 : spacingPx) + barWindow.lengthPaddingStartPx : (axis.outerVisualEdge() === "bottom" ? 0 : spacingPx)
                    anchors.bottomMargin: barWindow.isIsland ? (barWindow.isVertical ? barWindow.taskbarEndInset : (axis.edge === "bottom" ? 0 : parent.height - islandBandPx)) : barWindow.isVertical ? (barWindow.hasAdjacentBottomBar ? 0 : spacingPx) + barWindow.lengthPaddingEndPx : (axis.outerVisualEdge() === "bottom" ? spacingPx : 0)
                    onXChanged: barWindow.refreshBlurRegion()
                    onYChanged: barWindow.refreshBlurRegion()
                    onWidthChanged: barWindow.refreshBlurRegion()
                    onHeightChanged: barWindow.refreshBlurRegion()

                    BarSurface {
                        id: barBackground
                        barWindow: barWindow
                        axis: axis
                        barConfig: barWindow.renderBarConfig
                        visible: !frameShapesBar && !barWindow.isIsland
                        onGothEnabledChanged: _blurRebuildTimer.restart()
                        onWingChanged: barWindow.refreshBlurRegion()
                        onMotionRunningChanged: {
                            if (!motionRunning)
                                barWindow.refreshBlurRegion();
                        }
                    }

                    SectionSurface {
                        id: leadingSatelliteSurface
                        visible: barWindow.islandSatelliteBackground && barWindow.islandSatellitesEnabled && alongSize > 0
                        alongPos: barWindow.isVertical ? topBarContent.y + (barWindow._leftSection?.y ?? 0) : topBarContent.x + (barWindow._leftSection?.x ?? 0)
                        alongSize: barWindow.leadingSectionSize
                        alongExtent: barWindow.isVertical ? barUnitInset.height : barUnitInset.width
                        crossSize: barWindow.islandSatelliteDepth
                        crossExtent: barWindow.isVertical ? barUnitInset.width : barUnitInset.height
                        isVertical: barWindow.isVertical
                        crossFar: axis.edge === "bottom" || axis.edge === "right"
                        edgeAligned: !barWindow.islandSatellitesHugIsland
                        pad: barWindow.islandChromePad
                        sweep: barWindow.islandGothRadius
                        gothEnabled: barWindow.isIsland && SettingsData.islandSetting(barConfig, "islandSatelliteGothCorners")
                        fillColor: Theme.withAlpha(barWindow.islandSurfaceColor, barWindow.islandSatelliteOpacity)
                        dpr: barWindow._dpr
                        clearEdge: barWindow.islandSatellitesClipToIsland ? barWindow.islandHost.currentAlongPos - barWindow.islandSatelliteGap - barWindow.islandFlareClearance - (barWindow.isVertical ? barUnitInset.y : barUnitInset.x) : NaN
                    }

                    SectionSurface {
                        id: trailingSatelliteSurface
                        visible: barWindow.islandSatelliteBackground && barWindow.islandSatellitesEnabled && alongSize > 0
                        trailing: true
                        alongPos: barWindow.isVertical ? topBarContent.y + (barWindow._rightSection?.y ?? 0) : topBarContent.x + (barWindow._rightSection?.x ?? 0)
                        alongSize: barWindow.trailingSectionSize
                        alongExtent: barWindow.isVertical ? barUnitInset.height : barUnitInset.width
                        crossSize: barWindow.islandSatelliteDepth
                        crossExtent: barWindow.isVertical ? barUnitInset.width : barUnitInset.height
                        isVertical: barWindow.isVertical
                        crossFar: axis.edge === "bottom" || axis.edge === "right"
                        edgeAligned: !barWindow.islandSatellitesHugIsland
                        pad: barWindow.islandChromePad
                        sweep: barWindow.islandGothRadius
                        gothEnabled: barWindow.isIsland && SettingsData.islandSetting(barConfig, "islandSatelliteGothCorners")
                        fillColor: Theme.withAlpha(barWindow.islandSurfaceColor, barWindow.islandSatelliteOpacity)
                        dpr: barWindow._dpr
                        clearEdge: barWindow.islandSatellitesClipToIsland ? barWindow.islandHost.currentAlongPos + barWindow.islandHost.currentVisualAlong + barWindow.islandSatelliteGap + barWindow.islandFlareClearance - (barWindow.isVertical ? barUnitInset.y : barUnitInset.x) : NaN
                    }

                    MouseArea {
                        id: emptyBarClickArea
                        anchors.fill: parent
                        z: -2
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (barWindow.handleEmptyBarClick(mouse.button, emptyBarClickArea, mouse.x, mouse.y))
                                return;
                            PopoutManager.dismissAllForScreen(barWindow.screen?.name);
                        }
                    }

                    BarScrollArea {
                        id: scrollArea
                        anchors.fill: parent
                        propagateComposedEvents: true
                        z: -1
                        scrollEnabled: barWindow.barConfig?.scrollEnabled ?? true
                        xBehavior: barWindow.barConfig?.scrollXBehavior ?? "focusWindow"
                        yBehavior: barWindow.barConfig?.scrollYBehavior ?? "workspace"
                        screenName: barWindow.screenName
                        barConfig: barWindow.barConfig
                        onWorkspaceSwitchRequested: direction => topBarContent.switchWorkspace(direction)
                    }

                    DBarContent {
                        id: topBarContent
                        barWindow: barWindow
                        rootWindow: barWindow.rootWindow
                        barConfig: barWindow.barConfig
                        leftWidgetsModel: barWindow.leftWidgetsModel
                        centerWidgetsModel: barWindow.isIsland ? null : barWindow.centerWidgetsModel
                        rightWidgetsModel: barWindow.rightWidgetsModel
                        visible: barWindow.islandSatellitesEnabled
                        leadingSectionOffset: barWindow.islandLeadingOffset
                        trailingSectionOffset: barWindow.islandTrailingOffset
                        sectionCrossOffset: barWindow.islandSatelliteCrossShift
                        reservedStart: barWindow.islandReservesStrip ? barWindow.islandReachStart - barWindow.islandStripClearance - barWindow.contentAlongStart : NaN
                        reservedEnd: barWindow.islandReservesStrip ? barWindow.islandReachEnd + barWindow.islandStripClearance - barWindow.contentAlongStart : NaN
                    }

                    // Passive: tracks cursor without intercepting clicks or scroll
                    HoverHandler {
                        id: hoverPopoutHandler
                        enabled: (barConfig?.hoverPopouts ?? false) && !barWindow.clickThroughEnabled

                        property real lastGlobalX: 0
                        property real lastGlobalY: 0

                        onPointChanged: {
                            const gp = topBarContent.surfaceContext.screenPoint(barUnitInset, point.position.x, point.position.y);
                            lastGlobalX = gp.x;
                            lastGlobalY = gp.y;
                            topBarContent.queueHoverPopout(gp.x, gp.y);
                        }

                        onHoveredChanged: {
                            topBarContent.updateHoverBarHovered(hovered);
                        }
                    }
                }

                // Qt 6.11+ drops pointer delivery outside an ancestor's bounds once its clip cache is set
                // (QQuickItemPrivate::effectivelyClipsEventHandlingChildren), so an edge pill cannot reach the screen edge on its own.
                Repeater {
                    model: 2

                    MouseArea {
                        id: edgeStrip

                        required property int index
                        readonly property bool leading: index === 0
                        readonly property var section: leading ? barWindow._leftSection : barWindow._rightSection
                        readonly property var edgeItem: {
                            const item = leading ? section?.leadingInlineItem : section?.trailingInlineItem;
                            if (!item || !("handlePress" in item) || !item.enabled || !item.visible)
                                return null;
                            if (leading)
                                return item.isFirst && (barWindow.isVertical ? item.isTopBarEdge : item.isLeftBarEdge) ? item : null;
                            return item.isLast && (barWindow.isVertical ? item.isBottomBarEdge : item.isRightBarEdge) ? item : null;
                        }
                        readonly property real sectionStart: !section ? 0 : barWindow.isVertical ? barUnitInset.y + topBarContent.y + section.y : barUnitInset.x + topBarContent.x + section.x
                        readonly property real sectionEnd: !section ? 0 : sectionStart + (barWindow.isVertical ? section.height : section.width)

                        x: barWindow.isVertical || leading ? 0 : sectionEnd
                        y: barWindow.isVertical && !leading ? sectionEnd : 0
                        width: barWindow.isVertical ? parent.width : Math.max(0, leading ? sectionStart : parent.width - sectionEnd)
                        height: barWindow.isVertical ? Math.max(0, leading ? sectionStart : parent.height - sectionEnd) : parent.height
                        visible: !!edgeItem && width > 0 && height > 0
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: (edgeItem?.enableCursor ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: mouse => edgeItem.handlePress(mouse, edgeStrip)
                        onWheel: wheelEvent => {
                            wheelEvent.accepted = false;
                            edgeItem.wheel(wheelEvent);
                        }

                        Binding {
                            target: edgeStrip.edgeItem
                            property: "edgeHovered"
                            value: edgeStrip.containsMouse
                            when: !!edgeStrip.edgeItem
                            restoreMode: Binding.RestoreBindingOrValue
                        }
                    }
                }

                Loader {
                    id: islandLoader
                    anchors.fill: parent
                    active: barWindow.hostsIsland && !barWindow.islandFree

                    // Band-sized and empty until the island loads; Qt's pointer-clip cache is already set by then.
                    PointerOverflowMarker {}

                    sourceComponent: IslandBarHost {
                        barConfig: barWindow.barConfig
                        screen: barWindow.screen
                        hostWindow: barWindow.hostWindow
                        barId: barWindow._barId
                        originOffsetX: topBarMouseArea.x + islandLoader.x
                        originOffsetY: topBarMouseArea.y + islandLoader.y
                        hostOffsetX: barWindow.hostOffsetX
                        hostOffsetY: barWindow.hostOffsetY
                        chrome: barWindow.islandChromeMode
                        frameHosted: barWindow.frameHosted
                        anchorItem: topBarContainer
                        slotItem: barWindow.islandSlot
                        barBody: barWindow
                        bandThickness: barWindow.isVertical ? topBarMouseArea.width : topBarMouseArea.height
                        bandAlongStart: barWindow.isVertical ? barUnitInset.y : barUnitInset.x
                        bandAlongEnd: barWindow.isVertical ? barUnitInset.y + barUnitInset.height : barUnitInset.x + barUnitInset.width
                        bandColor: barWindow._bgColor
                        leadingSectionRect: barWindow.leadingSectionRect
                        centerSectionRect: barWindow.centerSectionRect
                        trailingSectionRect: barWindow.trailingSectionRect
                        onScrollWheel: wheel => scrollArea.processWheel(wheel)
                    }
                }
            }
        }
    }
}
