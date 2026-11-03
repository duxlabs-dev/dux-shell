pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modules.DIsland
import qs.Services
import "../../Common/ConnectorGeometry.js" as ConnectorGeometry
import "../../Common/ConnectedSurfaceGeometry.js" as SurfaceGeometry

PanelWindow {
    id: win

    readonly property var log: Log.scoped("FrameWindow")

    required property var targetScreen

    screen: targetScreen
    readonly property bool _frameVisible: CompositorService.frameWindowVisibleForScreen(win.targetScreen)
    visible: win._frameVisible
    updatesEnabled: win._frameVisible

    WlrLayershell.namespace: "dms:frame"
    readonly property bool _dockEditActive: frameDockHostLoader.item?.editActive ?? false
    // The frame, not the bar, supplies this island's focus, grab and input mask.
    readonly property Item _islandHost: {
        const bars = BarWidgetService.frameHostedBars[win._screenName] ?? {};
        for (const id in bars) {
            const host = bars[id]?.islandHost ?? null;
            if (host)
                return host;
        }
        return null;
    }
    readonly property alias islandChrome: islandChrome
    readonly property bool _islandSheetOut: islandChrome.sheetOut
    // A hosted sheet never re-layers the frame: everything it must cover is drawn inside this window (loader z), and a
    // Top→Overlay→Top round trip re-stacks the frame above its own popout windows, painting their blur in front.
    readonly property int dBarLayer: win._usesOverlayLayer || win._dockEditActive ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.layer: win.dBarLayer
    WlrLayershell.keyboardFocus: win._dockEditActive ? WlrKeyboardFocus.Exclusive : islandChrome.keyboardFocusPolicy !== WlrKeyboardFocus.None ? islandChrome.keyboardFocusPolicy : frameDockHostLoader.item?.interactionActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    IslandHostChrome {
        id: islandChrome

        window: win
        host: win._islandHost
    }

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    // Click-through everywhere except the frame gutters and hosted bar strips. Dock edit mode takes the whole screen for its scrim.
    mask: Region {
        Region {
            x: 0
            y: 0
            width: win._dockEditActive ? win._windowRegionWidth : 0
            height: win._dockEditActive ? win._windowRegionHeight : 0
        }
        Region {
            readonly property bool present: win._frameActive && win.cutoutTopInset > 0
            x: 0
            y: 0
            width: present ? win._windowRegionWidth : 0
            height: present ? win.cutoutTopInset : 0
        }
        Region {
            readonly property bool present: win._frameActive && win.cutoutBottomInset > 0
            x: 0
            y: present ? win._windowRegionHeight - win.cutoutBottomInset : 0
            width: present ? win._windowRegionWidth : 0
            height: present ? win.cutoutBottomInset : 0
        }
        Region {
            readonly property bool present: win._frameActive && win.cutoutLeftInset > 0
            x: 0
            y: 0
            width: present ? win.cutoutLeftInset : 0
            height: present ? win._windowRegionHeight : 0
        }
        Region {
            readonly property bool present: win._frameActive && win.cutoutRightInset > 0
            x: present ? win._windowRegionWidth - win.cutoutRightInset : 0
            y: 0
            width: present ? win.cutoutRightInset : 0
            height: present ? win._windowRegionHeight : 0
        }
        // Each frame-hosted dock's hover strip, so hover-reveal works through the frame surface.
        // Region takes no repeater, and a screen holds at most one dock per edge, so four slots cover it.
        Region {
            item: frameDockHostLoader.item?.dockMaskItems[0] ?? null
        }
        Region {
            item: frameDockHostLoader.item?.dockMaskItems[1] ?? null
        }
        Region {
            item: frameDockHostLoader.item?.dockMaskItems[2] ?? null
        }
        Region {
            item: frameDockHostLoader.item?.dockMaskItems[3] ?? null
        }
        Region {
            item: islandChrome.maskItem
        }
    }

    readonly property var barEdges: {
        SettingsData.barConfigs;
        return SettingsData.getActiveBarEdgesForScreen(win.targetScreen);
    }

    readonly property real _dpr: CompositorService.getScreenScale(win.targetScreen)
    readonly property bool _frameActive: FrameTransitionState.effectiveFrameEnabled && SettingsData.isScreenInPreferences(win.targetScreen, SettingsData.frameScreenPreferences)
    readonly property int _windowRegionWidth: win._regionInt(win.width)
    readonly property int _windowRegionHeight: win._regionInt(win.height)
    readonly property string _screenName: win.targetScreen ? win.targetScreen.name : ""
    readonly property int _surfaceRevision: ConnectedModeState.surfaceRevisions[win._screenName] ?? 0
    readonly property var _popoutDescriptor: {
        win._surfaceRevision;
        return ConnectedModeState.surfaceDescriptor(win._screenName, "popout");
    }
    component ConnectorBlurRegion: Region {
        id: connectorBlur
        required property string barSide
        required property var body
        required property string placement
        required property real connectorRadius
        property bool far: false
        property bool bodyActive: true

        readonly property bool _active: bodyActive && connectorRadius > 0
        readonly property var _rect: far ? SurfaceGeometry.farConnectorRect(barSide, body, placement, connectorRadius, win._dpr) : SurfaceGeometry.connectorRect(barSide, body, placement, 0, connectorRadius, win._dpr)
        readonly property string _arcCorner: far ? ConnectorGeometry.arcCorner(win._farConnectorBarSide(barSide, placement), win._farConnectorPlacement(barSide, placement)) : ConnectorGeometry.arcCorner(barSide, placement)
        readonly property var _blur: win._seamPaddedBlurRect(_rect, far ? win._farConnectorBarSide(barSide, placement) : barSide)

        x: _active ? _blur.x : 0
        y: _active ? _blur.y : 0
        width: _active ? _blur.width : 0
        height: _active ? _blur.height : 0

        Region {
            readonly property bool _active: connectorBlur.width > 0 && connectorBlur.height > 0

            intersection: Intersection.Subtract
            radius: connectorBlur.connectorRadius
            x: _active ? Math.round(win._connectorCutoutX(connectorBlur.x, connectorBlur.width, connectorBlur._arcCorner, connectorBlur.connectorRadius)) : 0
            y: _active ? Math.round(win._connectorCutoutY(connectorBlur.y, connectorBlur.height, connectorBlur._arcCorner, connectorBlur.connectorRadius)) : 0
            width: _active ? Math.round(connectorBlur.connectorRadius * 2) : 0
            height: _active ? Math.round(connectorBlur.connectorRadius * 2) : 0
        }
    }
    component DockBlurRegion: Region {
        id: dockBlur
        required property var dockSurface
        readonly property var descriptor: dockSurface?.descriptor ?? ({
                visible: false,
                barSide: "bottom"
            })
        readonly property var geometry: dockSurface?.body ?? Qt.rect(0, 0, 0, 0)
        readonly property real bodyRadius: dockSurface?.radius ?? 0
        readonly property real connectorRadius: dockSurface?.connector ?? 0

        Region {
            id: _dockBodyBlurAnchor

            readonly property bool _active: win._blurSurfacesActive && win._connectedActive && dockBlur.descriptor.visible && dockBlur.geometry.width > 0 && dockBlur.geometry.height > 0

            readonly property var _blur: win._seamPaddedBlurRect(dockBlur.geometry)

            radius: dockBlur.bodyRadius
            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        Region {
            id: _dockBodyBlurCap

            readonly property string _side: dockBlur.descriptor.barSide
            readonly property bool _active: _dockBodyBlurAnchor._active && _dockBodyBlurAnchor.width > 0 && _dockBodyBlurAnchor.height > 0
            readonly property int _capWidth: (_side === "left" || _side === "right") ? Math.round(Math.min(dockBlur.connectorRadius, _dockBodyBlurAnchor.width)) : _dockBodyBlurAnchor.width
            readonly property int _capHeight: (_side === "top" || _side === "bottom") ? Math.round(Math.min(dockBlur.connectorRadius, _dockBodyBlurAnchor.height)) : _dockBodyBlurAnchor.height

            x: !_active ? 0 : (_side === "right" ? _dockBodyBlurAnchor.x + _dockBodyBlurAnchor.width - _capWidth : _dockBodyBlurAnchor.x)
            y: !_active ? 0 : (_side === "bottom" ? _dockBodyBlurAnchor.y + _dockBodyBlurAnchor.height - _capHeight : _dockBodyBlurAnchor.y)
            width: _active ? _capWidth : 0
            height: _active ? _capHeight : 0
        }
        ConnectorBlurRegion {
            barSide: dockBlur.descriptor.barSide
            body: dockBlur.geometry
            placement: "left"
            bodyActive: _dockBodyBlurAnchor._active
            connectorRadius: dockBlur.connectorRadius
        }
        ConnectorBlurRegion {
            barSide: dockBlur.descriptor.barSide
            body: dockBlur.geometry
            placement: "right"
            bodyActive: _dockBodyBlurAnchor._active
            connectorRadius: dockBlur.connectorRadius
        }
    }

    readonly property var _dockSurfaces: {
        win._surfaceRevision;
        return ConnectedModeState.surfaceDescriptorsOfKind(win._screenName, "dock").map(descriptor => {
            const body = SurfaceGeometry.translatedBodyRect(descriptor, win._dpr);
            const radius = Math.max(0, Math.min(descriptor.surfaceRadius >= 0 ? descriptor.surfaceRadius : win._surfaceRadius, body.width / 2, body.height / 2));
            const thickness = SurfaceGeometry.isVertical(descriptor.barSide) ? body.width : body.height;
            const connector = Math.max(0, Math.min(win._ccr, radius, thickness - radius - win._seamOverlap));
            return {
                descriptor: descriptor,
                body: body,
                radius: radius,
                connector: connector
            };
        });
    }
    readonly property var _notifDescriptor: {
        win._surfaceRevision;
        return ConnectedModeState.surfaceDescriptor(win._screenName, "notification");
    }
    readonly property var _islandDescriptor: {
        win._surfaceRevision;
        return ConnectedModeState.surfaceDescriptor(win._screenName, "island");
    }
    // The island body starts inside the bar band; only the part past the cutout is silhouette, and its fillets follow that clamped rect.
    readonly property var _islandSurface: {
        const descriptor = win._islandDescriptor;
        if (!win._connectedActive || !descriptor.visible)
            return null;
        const body = win._clampNear(descriptor.barSide, SurfaceGeometry.bodyRect(descriptor, win._dpr));
        if (body.width < 1 || body.height < 1)
            return null;
        const radius = Math.max(0, Math.min(descriptor.surfaceRadius >= 0 ? descriptor.surfaceRadius : win._surfaceRadius, body.width / 2, body.height / 2));
        return {
            descriptor: descriptor,
            body: body,
            radius: radius,
            connector: SurfaceGeometry.connectorRadii(descriptor, body, win._ccr, radius, win._dpr, true).near
        };
    }
    readonly property var _slideoutDescriptor: {
        win._surfaceRevision;
        return ConnectedModeState.surfaceDescriptor(win._screenName, "slideout");
    }
    readonly property var _slideoutSurface: {
        const descriptor = win._slideoutDescriptor;
        if (!win._connectedActive || !descriptor.visible)
            return null;
        const body = win._clampNear(descriptor.barSide, SurfaceGeometry.animatedBodyRect(descriptor, win._dpr));
        if (body.width < 1 || body.height < 1)
            return null;
        return {
            descriptor: descriptor,
            body: body,
            radii: SurfaceGeometry.connectorRadii(descriptor, body, win._ccr, win._surfaceRadius, win._dpr, true)
        };
    }
    readonly property var _modalDescriptor: {
        win._surfaceRevision;
        return ConnectedModeState.surfaceDescriptor(win._screenName, "modal");
    }
    readonly property bool _usesOverlayLayer: (win._modalDescriptor.presented && win._modalDescriptor.layer === "overlay") || (win._popoutDescriptor.presented && win._popoutDescriptor.layer === "overlay")

    readonly property bool _connectedActive: CompositorService.usesConnectedFrameChromeForScreen(win.targetScreen)
    readonly property bool _dockHostedHere: win._connectedActive && CompositorService.frameHostsDockForScreen(win.targetScreen)

    readonly property string _barSide: {
        const edges = win.barEdges;
        if (edges.includes("top"))
            return "top";
        if (edges.includes("bottom"))
            return "bottom";
        if (edges.includes("left"))
            return "left";
        return "right";
    }
    readonly property real _ccr: Theme.connectedCornerRadius

    readonly property bool _popoutHorizontal: SurfaceGeometry.isHorizontal(win._popoutDescriptor.barSide)
    readonly property bool _modalHorizontal: SurfaceGeometry.isHorizontal(win._modalDescriptor.barSide)
    readonly property var _popoutBodyGeometry: SurfaceGeometry.animatedBodyRect(win._popoutDescriptor, win._dpr)
    readonly property var _modalBodyGeometry: SurfaceGeometry.animatedBodyRect(win._modalDescriptor, win._dpr)
    readonly property var _notifBodyGeometry: SurfaceGeometry.bodyRect(win._notifDescriptor, win._dpr)

    readonly property real _popoutArcExtent: win._popoutHorizontal ? _popoutBodyBlurAnchor.height : _popoutBodyBlurAnchor.width
    readonly property real _modalArcExtent: win._modalHorizontal ? _modalBodyBlurAnchor.height : _modalBodyBlurAnchor.width
    readonly property real _popoutConnectorRadiusLeft: win._effectivePopoutStartCcr
    readonly property real _popoutConnectorRadiusRight: win._effectivePopoutEndCcr
    readonly property real _modalConnectorRadiusLeft: win._effectiveModalStartCcr
    readonly property real _modalConnectorRadiusRight: win._effectiveModalEndCcr
    readonly property real _notifConnectorRadiusLeft: win._effectiveNotifStartCcr
    readonly property real _notifConnectorRadiusRight: win._effectiveNotifEndCcr

    readonly property real _notifSideUnderlapValue: SurfaceGeometry.isVertical(win._notifDescriptor.barSide) ? win._seamOverlap : 0
    readonly property real _notifStartUnderlapValue: win._notifDescriptor.omitStartConnector ? win._seamOverlap : 0
    readonly property real _notifEndUnderlapValue: win._notifDescriptor.omitEndConnector ? win._seamOverlap : 0

    readonly property var _popoutRadii: SurfaceGeometry.connectorRadii(win._popoutDescriptor, win._popoutBodyGeometry, win._ccr, win._surfaceRadius, win._dpr, false)
    readonly property real _effectivePopoutCcr: win._popoutRadii.near
    readonly property real _effectivePopoutFarCcr: win._popoutRadii.far
    readonly property real _effectivePopoutStartCcr: win._popoutRadii.start
    readonly property real _effectivePopoutEndCcr: win._popoutRadii.end
    readonly property real _effectivePopoutFarStartCcr: win._popoutRadii.farStart
    readonly property real _effectivePopoutFarEndCcr: win._popoutRadii.farEnd
    readonly property real _effectivePopoutMaxCcr: Math.max(win._effectivePopoutStartCcr, win._effectivePopoutEndCcr)
    readonly property real _effectivePopoutFarExtent: Math.max(win._effectivePopoutFarStartCcr, win._effectivePopoutFarEndCcr)
    readonly property var _notifNearRadii: SurfaceGeometry.connectorRadii(win._notifDescriptor, win._notifBodyGeometry, win._ccr, win._surfaceRadius, win._dpr, true)
    readonly property var _notifFarRadii: SurfaceGeometry.connectorRadii(win._notifDescriptor, win._notifBodyScene(), win._ccr, win._surfaceRadius, win._dpr, true)
    readonly property real _effectiveNotifCcr: win._notifNearRadii.near
    readonly property real _effectiveNotifFarCcr: win._notifFarRadii.far
    readonly property real _effectiveNotifStartCcr: win._notifNearRadii.start
    readonly property real _effectiveNotifEndCcr: win._notifNearRadii.end
    readonly property real _effectiveNotifFarStartCcr: win._notifFarRadii.farStart
    readonly property real _effectiveNotifFarEndCcr: win._notifFarRadii.farEnd
    readonly property real _effectiveNotifMaxCcr: Math.max(win._effectiveNotifStartCcr, win._effectiveNotifEndCcr)
    readonly property real _effectiveNotifFarExtent: Math.max(win._effectiveNotifFarStartCcr, win._effectiveNotifFarEndCcr)
    readonly property var _modalRadii: SurfaceGeometry.connectorRadii(win._modalDescriptor, win._modalBodyGeometry, win._ccr, win._surfaceRadius, win._dpr, true)
    readonly property real _effectiveModalCcr: win._modalRadii.near
    readonly property real _effectiveModalFarCcr: win._modalRadii.far
    readonly property real _effectiveModalStartCcr: win._modalRadii.start
    readonly property real _effectiveModalEndCcr: win._modalRadii.end
    readonly property real _effectiveModalFarStartCcr: win._modalRadii.farStart
    readonly property real _effectiveModalFarEndCcr: win._modalRadii.farEnd
    readonly property real _effectiveModalFarExtent: Math.max(win._effectiveModalFarStartCcr, win._effectiveModalFarEndCcr)
    readonly property color _surfaceColor: Theme.frameSurfaceColor
    readonly property real _surfaceRadius: Theme.connectedSurfaceRadius
    readonly property real _seamOverlap: Theme.hairline(win._dpr)
    readonly property bool _disableLayer: Quickshell.env("DMS_DISABLE_LAYER") === "true" || Quickshell.env("DMS_DISABLE_LAYER") === "1"
    readonly property bool _elevationShadow: win._connectedActive && Theme.elevationEnabled && (SettingsData.barElevationEnabled || SettingsData.popoutElevationEnabled || SettingsData.modalElevationEnabled) && !win._disableLayer
    function _clampNear(side, b) {
        const r = {
            "x": b.x,
            "y": b.y,
            "width": b.width,
            "height": b.height
        };
        if (side === "top") {
            r.height = Math.max(0, b.y + b.height - win.cutoutTopInset);
            r.y = win.cutoutTopInset;
        } else if (side === "bottom") {
            r.height = Math.max(0, win.height - win.cutoutBottomInset - b.y);
        } else if (side === "left") {
            r.width = Math.max(0, b.x + b.width - win.cutoutLeftInset);
            r.x = win.cutoutLeftInset;
        } else if (side === "right") {
            r.width = Math.max(0, win.width - win.cutoutRightInset - b.x);
        }
        return r;
    }

    function _sdfSlot(s) {
        const b = win._clampNear(s.side, s.body);
        const active = b.width >= 1 && b.height >= 1 ? 1 : 0;
        const sc = s.radii.startCr, ec = s.radii.endCr;
        const extent = (s.side === "top" || s.side === "bottom") ? b.height : b.width;
        const fc = Math.min(s.radii.farCr, extent);
        const omitS = s.radii.farStartCr > 0;
        const omitE = s.radii.farEndCr > 0;
        const bodyR = s.radii.surfaceRadius;
        const nearS = omitS ? bodyR : 0, nearE = omitE ? bodyR : 0;
        const farS = omitS ? 0 : bodyR, farE = omitE ? 0 : bodyR;
        const kS = omitS ? fc : sc, kE = omitE ? fc : ec;
        let ks, cr;
        if (s.side === "top") {
            ks = [kS, kE, fc, fc];
            cr = [nearS, nearE, farE, farS];
        } else if (s.side === "bottom") {
            ks = [fc, fc, kE, kS];
            cr = [farS, farE, nearE, nearS];
        } else if (s.side === "left") {
            ks = [kS, fc, fc, kE];
            cr = [nearS, farS, farE, nearE];
        } else {
            ks = [fc, kS, kE, fc];
            cr = [farS, nearS, nearE, farE];
        }
        return {
            "rect": Qt.vector4d(b.x, b.y, b.width, b.height),
            "corner": Qt.vector4d(cr[0], cr[1], cr[2], cr[3]),
            "k": Qt.vector4d(ks[0], ks[1], ks[2], ks[3]),
            "param": Qt.vector4d(active, 0, 0, 0)
        };
    }

    readonly property var _emptySdfSlot: ({
            "rect": Qt.vector4d(0, 0, 0, 0),
            "corner": Qt.vector4d(0, 0, 0, 0),
            "k": Qt.vector4d(0, 0, 0, 0),
            "param": Qt.vector4d(0, 0, 0, 0)
        })

    // Slots 0-3 hold popout, modal, notification and docks; the island and slideout spring every frame, so each owns a slot alone (4, 5).
    readonly property var _sdfSlots: {
        win._surfaceRevision;
        const src = win._unifiedSurfaces();
        const out = [];
        for (let i = 0; i < 4; i++)
            out.push(i < src.length ? win._sdfSlot(src[i]) : win._emptySdfSlot);
        return out;
    }

    readonly property var _islandSdfSlot: {
        win._surfaceRevision;
        const island = win._islandSurface;
        if (!island)
            return win._emptySdfSlot;
        return win._sdfSlot({
            "side": island.descriptor.barSide,
            "body": island.body,
            "radii": {
                "farCr": 0,
                "startCr": island.connector,
                "endCr": island.connector,
                "farStartCr": 0,
                "farEndCr": 0,
                "surfaceRadius": island.radius
            }
        });
    }

    readonly property var _slideoutSdfSlot: {
        const slideout = win._slideoutSurface;
        if (!slideout)
            return win._emptySdfSlot;
        return win._sdfSlot({
            "side": slideout.descriptor.barSide,
            "body": slideout.body,
            "radii": {
                "farCr": slideout.radii.far,
                "startCr": slideout.radii.start,
                "endCr": slideout.radii.end,
                "farStartCr": slideout.radii.farStart,
                "farEndCr": slideout.radii.farEnd,
                "surfaceRadius": win._surfaceRadius
            }
        });
    }
    function _regionInt(value) {
        return Math.max(0, Math.round(Theme.px(value, win._dpr)));
    }

    function _pointInBand(lx, ly, bx, by, bw, bh, pad) {
        return lx >= bx - pad && lx < bx + bw + pad && ly >= by - pad && ly < by + bh + pad;
    }

    function containsGlobalPoint(gx, gy, padding) {
        if (!win._connectedActive || !win.contentItem)
            return false;
        const origin = win.contentItem.mapToItem(null, 0, 0);
        if (!origin)
            return false;
        const pad = padding !== undefined ? padding : 16;
        const lx = gx - origin.x;
        const ly = gy - origin.y;
        const w = win._windowRegionWidth;
        const h = win._windowRegionHeight;
        const edges = win.barEdges;
        if (edges.includes("top") && win._pointInBand(lx, ly, 0, 0, w, win.cutoutTopInset, pad))
            return true;
        if (edges.includes("bottom") && win._pointInBand(lx, ly, 0, h - win.cutoutBottomInset, w, win.cutoutBottomInset, pad))
            return true;
        if (edges.includes("left") && win._pointInBand(lx, ly, 0, 0, win.cutoutLeftInset, h, pad))
            return true;
        if (edges.includes("right") && win._pointInBand(lx, ly, w - win.cutoutRightInset, 0, win.cutoutRightInset, h, pad))
            return true;
        return false;
    }

    readonly property int cutoutTopInset: {
        SettingsData.barConfigs;
        return win._regionInt(SettingsData.frameEdgeReservation(win.targetScreen, "top"));
    }
    readonly property int cutoutBottomInset: {
        SettingsData.barConfigs;
        return win._regionInt(SettingsData.frameEdgeReservation(win.targetScreen, "bottom"));
    }
    readonly property int cutoutLeftInset: {
        SettingsData.barConfigs;
        return win._regionInt(SettingsData.frameEdgeReservation(win.targetScreen, "left"));
    }
    readonly property int cutoutRightInset: {
        SettingsData.barConfigs;
        return win._regionInt(SettingsData.frameEdgeReservation(win.targetScreen, "right"));
    }
    readonly property int cutoutWidth: Math.max(0, win._windowRegionWidth - win.cutoutLeftInset - win.cutoutRightInset)
    readonly property int cutoutHeight: Math.max(0, win._windowRegionHeight - win.cutoutTopInset - win.cutoutBottomInset)
    readonly property int cutoutRadius: {
        const requested = win._regionInt(SettingsData.frameRounding);
        const maxRadius = Math.floor(Math.min(win.cutoutWidth, win.cutoutHeight) / 2);
        return Math.max(0, Math.min(requested, maxRadius));
    }

    readonly property bool _blurSurfacesActive: BlurService.enabled && SettingsData.frameBlurEnabled && win._frameActive
    readonly property int _blurCutoutCompensation: Theme.frameSurfaceColor.a <= 0.2 ? 1 : 0
    readonly property int _blurCutoutLeft: Math.max(0, win.cutoutLeftInset - win._blurCutoutCompensation)
    readonly property int _blurCutoutTop: Math.max(0, win.cutoutTopInset - win._blurCutoutCompensation)
    readonly property int _blurCutoutRight: Math.min(win._windowRegionWidth, win._windowRegionWidth - win.cutoutRightInset + win._blurCutoutCompensation)
    readonly property int _blurCutoutBottom: Math.min(win._windowRegionHeight, win._windowRegionHeight - win.cutoutBottomInset + win._blurCutoutCompensation)
    readonly property int _blurCutoutRadius: {
        const requested = win.cutoutRadius + win._blurCutoutCompensation;
        const maxRadius = Math.floor(Math.min(_blurCutout.width, _blurCutout.height) / 2);
        return Math.max(0, Math.min(requested, maxRadius));
    }
    readonly property var _emptyRect: ({
            "x": 0,
            "y": 0,
            "width": 0,
            "height": 0
        })

    readonly property var _cutoutEdges: ({
            "left": win.cutoutLeftInset,
            "top": win.cutoutTopInset,
            "right": win._windowRegionWidth - win.cutoutRightInset,
            "bottom": win._windowRegionHeight - win.cutoutBottomInset
        })

    // Chrome fused to a band shares its paint, so the band's blur inset must not leave an unblurred line along the seam.
    function _seamPaddedBlurRect(rect, side) {
        return SurfaceGeometry.bandPaddedRect(rect, win._blurCutoutCompensation, win._cutoutEdges, side);
    }

    QtObject {
        id: _notifBodyBlurAnchor

        readonly property bool _active: win._blurSurfacesActive && win._notifDescriptor.visible && win._notifBodyGeometry.width > 0 && win._notifBodyGeometry.height > 0
        readonly property int x: _active ? Math.round(win._notifBodyGeometry.x) : 0
        readonly property int y: _active ? Math.round(win._notifBodyGeometry.y) : 0
        readonly property int width: _active ? Math.round(win._notifBodyGeometry.width) : 0
        readonly property int height: _active ? Math.round(win._notifBodyGeometry.height) : 0
    }

    Region {
        id: _staticBlurRegion
        x: 0
        y: 0
        width: win._windowRegionWidth
        height: win._windowRegionHeight

        Region {
            id: _blurCutout
            intersection: Intersection.Subtract
            radius: win._blurCutoutRadius
            x: win._blurCutoutLeft
            y: win._blurCutoutTop
            width: Math.max(0, win._blurCutoutRight - win._blurCutoutLeft)
            height: Math.max(0, win._blurCutoutBottom - win._blurCutoutTop)
        }

        Region {
            id: _popoutBodyBlurAnchor

            readonly property bool _active: win._blurSurfacesActive && win._popoutDescriptor.visible

            readonly property var _blur: win._seamPaddedBlurRect(win._popoutBodyGeometry)

            radius: win._surfaceRadius
            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        Region {
            id: _popoutBodyBlurCap

            readonly property string _side: win._popoutDescriptor.barSide
            readonly property real _capThickness: win._popoutBlurCapThickness()
            readonly property bool _active: _popoutBodyBlurAnchor._active && _capThickness > 0 && _popoutBodyBlurAnchor.width > 0 && _popoutBodyBlurAnchor.height > 0
            readonly property int _capWidth: (_side === "left" || _side === "right") ? Math.round(Math.min(_capThickness, _popoutBodyBlurAnchor.width)) : _popoutBodyBlurAnchor.width
            readonly property int _capHeight: (_side === "top" || _side === "bottom") ? Math.round(Math.min(_capThickness, _popoutBodyBlurAnchor.height)) : _popoutBodyBlurAnchor.height

            x: !_active ? 0 : (_side === "right" ? _popoutBodyBlurAnchor.x + _popoutBodyBlurAnchor.width - _capWidth : _popoutBodyBlurAnchor.x)
            y: !_active ? 0 : (_side === "bottom" ? _popoutBodyBlurAnchor.y + _popoutBodyBlurAnchor.height - _capHeight : _popoutBodyBlurAnchor.y)
            width: _active ? _capWidth : 0
            height: _active ? _capHeight : 0
        }
        ConnectorBlurRegion {
            barSide: win._popoutDescriptor.barSide
            body: win._popoutBodyGeometry
            placement: "left"
            bodyActive: _popoutBodyBlurAnchor._active
            connectorRadius: win._popoutConnectorRadiusLeft
        }
        ConnectorBlurRegion {
            barSide: win._popoutDescriptor.barSide
            body: win._popoutBodyGeometry
            placement: "right"
            bodyActive: _popoutBodyBlurAnchor._active
            connectorRadius: win._popoutConnectorRadiusRight
        }
        Region {
            id: _popoutFarStartBodyBlurCap

            readonly property real _radius: win._effectivePopoutFarStartCcr
            readonly property bool _active: _popoutBodyBlurAnchor._active && _radius > 0
            readonly property var _rect: SurfaceGeometry.farBodyCapRect(win._popoutDescriptor.barSide, win._popoutBodyGeometry, "left", _radius, win._dpr)
            readonly property var _blur: win._seamPaddedBlurRect(_rect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        Region {
            id: _popoutFarEndBodyBlurCap

            readonly property real _radius: win._effectivePopoutFarEndCcr
            readonly property bool _active: _popoutBodyBlurAnchor._active && _radius > 0
            readonly property var _rect: SurfaceGeometry.farBodyCapRect(win._popoutDescriptor.barSide, win._popoutBodyGeometry, "right", _radius, win._dpr)
            readonly property var _blur: win._seamPaddedBlurRect(_rect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        ConnectorBlurRegion {
            barSide: win._popoutDescriptor.barSide
            body: win._popoutBodyGeometry
            placement: "left"
            far: true
            bodyActive: _popoutBodyBlurAnchor._active
            connectorRadius: win._effectivePopoutFarStartCcr
        }
        ConnectorBlurRegion {
            barSide: win._popoutDescriptor.barSide
            body: win._popoutBodyGeometry
            placement: "right"
            far: true
            bodyActive: _popoutBodyBlurAnchor._active
            connectorRadius: win._effectivePopoutFarEndCcr
        }

        DockBlurRegion {
            dockSurface: win._dockSurfaces[0] ?? null
        }
        DockBlurRegion {
            dockSurface: win._dockSurfaces[1] ?? null
        }
        DockBlurRegion {
            dockSurface: win._dockSurfaces[2] ?? null
        }
        DockBlurRegion {
            dockSurface: win._dockSurfaces[3] ?? null
        }
        DockBlurRegion {
            dockSurface: win._islandSurface
        }

        Region {
            id: _notifBodySceneBlurAnchor

            readonly property bool _active: _notifBodyBlurAnchor._active
            readonly property var sceneRect: _active ? win._notifBodyScene() : win._emptyRect
            readonly property var _blur: win._seamPaddedBlurRect(sceneRect)

            radius: win._surfaceRadius
            x: _blur.x
            y: _blur.y
            width: _blur.width
            height: _blur.height
        }
        Region {
            id: _notifBodyBlurCap

            readonly property string _side: win._notifDescriptor.barSide
            readonly property real _capRadius: win._effectiveNotifMaxCcr
            readonly property bool _active: _notifBodySceneBlurAnchor._active && _notifBodySceneBlurAnchor.width > 0 && _notifBodySceneBlurAnchor.height > 0 && _capRadius > 0
            readonly property int _capWidth: (_side === "left" || _side === "right") ? Math.round(Math.min(_capRadius, _notifBodySceneBlurAnchor.width)) : _notifBodySceneBlurAnchor.width
            readonly property int _capHeight: (_side === "top" || _side === "bottom") ? Math.round(Math.min(_capRadius, _notifBodySceneBlurAnchor.height)) : _notifBodySceneBlurAnchor.height

            x: !_active ? 0 : (_side === "right" ? _notifBodySceneBlurAnchor.x + _notifBodySceneBlurAnchor.width - _capWidth : _notifBodySceneBlurAnchor.x)
            y: !_active ? 0 : (_side === "bottom" ? _notifBodySceneBlurAnchor.y + _notifBodySceneBlurAnchor.height - _capHeight : _notifBodySceneBlurAnchor.y)
            width: _active ? _capWidth : 0
            height: _active ? _capHeight : 0
        }
        ConnectorBlurRegion {
            barSide: win._notifDescriptor.barSide
            body: _notifBodySceneBlurAnchor.sceneRect
            placement: "left"
            bodyActive: _notifBodySceneBlurAnchor._active
            connectorRadius: win._notifConnectorRadiusLeft
        }
        ConnectorBlurRegion {
            barSide: win._notifDescriptor.barSide
            body: _notifBodySceneBlurAnchor.sceneRect
            placement: "right"
            bodyActive: _notifBodySceneBlurAnchor._active
            connectorRadius: win._notifConnectorRadiusRight
        }
        Region {
            id: _notifFarStartBodyBlurCap

            readonly property real _radius: win._effectiveNotifFarStartCcr
            readonly property bool _active: _notifBodySceneBlurAnchor._active && _radius > 0
            readonly property var _rect: SurfaceGeometry.farBodyCapRect(win._notifDescriptor.barSide, _notifBodySceneBlurAnchor.sceneRect, "left", _radius, win._dpr)
            readonly property var _blur: win._seamPaddedBlurRect(_rect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        Region {
            id: _notifFarEndBodyBlurCap

            readonly property real _radius: win._effectiveNotifFarEndCcr
            readonly property bool _active: _notifBodySceneBlurAnchor._active && _radius > 0
            readonly property var _rect: SurfaceGeometry.farBodyCapRect(win._notifDescriptor.barSide, _notifBodySceneBlurAnchor.sceneRect, "right", _radius, win._dpr)
            readonly property var _blur: win._seamPaddedBlurRect(_rect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        ConnectorBlurRegion {
            barSide: win._notifDescriptor.barSide
            body: _notifBodySceneBlurAnchor.sceneRect
            placement: "left"
            far: true
            bodyActive: _notifBodySceneBlurAnchor._active
            connectorRadius: win._effectiveNotifFarStartCcr
        }
        ConnectorBlurRegion {
            barSide: win._notifDescriptor.barSide
            body: _notifBodySceneBlurAnchor.sceneRect
            placement: "right"
            far: true
            bodyActive: _notifBodySceneBlurAnchor._active
            connectorRadius: win._effectiveNotifFarEndCcr
        }

        Region {
            id: _slideoutBodyBlurAnchor

            readonly property bool _active: win._blurSurfacesActive && win._slideoutSurface !== null

            readonly property var _blur: win._seamPaddedBlurRect(win._slideoutSurface?.body ?? win._emptyRect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        ConnectorBlurRegion {
            barSide: win._slideoutDescriptor.barSide
            body: win._slideoutSurface?.body ?? win._emptyRect
            placement: "left"
            far: true
            connectorRadius: _slideoutBodyBlurAnchor._active ? Math.min(win._slideoutSurface.radii.farStart, win._slideoutSurface.body.width) : 0
        }
        ConnectorBlurRegion {
            barSide: win._slideoutDescriptor.barSide
            body: win._slideoutSurface?.body ?? win._emptyRect
            placement: "right"
            far: true
            connectorRadius: _slideoutBodyBlurAnchor._active ? Math.min(win._slideoutSurface.radii.farEnd, win._slideoutSurface.body.width) : 0
        }

        Region {
            id: _modalBodyBlurAnchor

            readonly property bool _active: win._blurSurfacesActive && win._modalDescriptor.visible && win._modalBodyGeometry.width > 0 && win._modalBodyGeometry.height > 0

            readonly property var _blur: win._seamPaddedBlurRect(win._modalBodyGeometry)

            radius: win._surfaceRadius
            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        Region {
            id: _modalBodyBlurCap

            readonly property string _side: win._modalDescriptor.barSide
            readonly property real _capThickness: win._modalBlurCapThickness()
            readonly property bool _active: _modalBodyBlurAnchor._active && _capThickness > 0 && _modalBodyBlurAnchor.width > 0 && _modalBodyBlurAnchor.height > 0
            readonly property int _capWidth: (_side === "left" || _side === "right") ? Math.round(Math.min(_capThickness, _modalBodyBlurAnchor.width)) : _modalBodyBlurAnchor.width
            readonly property int _capHeight: (_side === "top" || _side === "bottom") ? Math.round(Math.min(_capThickness, _modalBodyBlurAnchor.height)) : _modalBodyBlurAnchor.height

            x: !_active ? 0 : (_side === "right" ? _modalBodyBlurAnchor.x + _modalBodyBlurAnchor.width - _capWidth : _modalBodyBlurAnchor.x)
            y: !_active ? 0 : (_side === "bottom" ? _modalBodyBlurAnchor.y + _modalBodyBlurAnchor.height - _capHeight : _modalBodyBlurAnchor.y)
            width: _active ? _capWidth : 0
            height: _active ? _capHeight : 0
        }
        ConnectorBlurRegion {
            barSide: win._modalDescriptor.barSide
            body: win._modalBodyGeometry
            placement: "left"
            bodyActive: _modalBodyBlurAnchor._active
            connectorRadius: win._modalConnectorRadiusLeft
        }
        ConnectorBlurRegion {
            barSide: win._modalDescriptor.barSide
            body: win._modalBodyGeometry
            placement: "right"
            bodyActive: _modalBodyBlurAnchor._active
            connectorRadius: win._modalConnectorRadiusRight
        }
        Region {
            id: _modalFarStartBodyBlurCap

            readonly property real _radius: win._effectiveModalFarStartCcr
            readonly property bool _active: _modalBodyBlurAnchor._active && _radius > 0
            readonly property var _rect: SurfaceGeometry.farBodyCapRect(win._modalDescriptor.barSide, win._modalBodyGeometry, "left", _radius, win._dpr)
            readonly property var _blur: win._seamPaddedBlurRect(_rect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        Region {
            id: _modalFarEndBodyBlurCap

            readonly property real _radius: win._effectiveModalFarEndCcr
            readonly property bool _active: _modalBodyBlurAnchor._active && _radius > 0
            readonly property var _rect: SurfaceGeometry.farBodyCapRect(win._modalDescriptor.barSide, win._modalBodyGeometry, "right", _radius, win._dpr)
            readonly property var _blur: win._seamPaddedBlurRect(_rect)

            x: _active ? _blur.x : 0
            y: _active ? _blur.y : 0
            width: _active ? _blur.width : 0
            height: _active ? _blur.height : 0
        }
        ConnectorBlurRegion {
            barSide: win._modalDescriptor.barSide
            body: win._modalBodyGeometry
            placement: "left"
            far: true
            bodyActive: _modalBodyBlurAnchor._active
            connectorRadius: win._effectiveModalFarStartCcr
        }
        ConnectorBlurRegion {
            barSide: win._modalDescriptor.barSide
            body: win._modalBodyGeometry
            placement: "right"
            far: true
            bodyActive: _modalBodyBlurAnchor._active
            connectorRadius: win._effectiveModalFarEndCcr
        }
    }

    function _notifBodyScene() {
        const isHoriz = SurfaceGeometry.isHorizontal(win._notifDescriptor.barSide);
        const body = win._notifBodyGeometry;
        const start = win._notifStartUnderlapValue;
        const end = win._notifEndUnderlapValue;
        const side = win._notifSideUnderlapValue;
        if (isHoriz) {
            return {
                "x": body.x - start,
                "y": body.y,
                "width": body.width + start + end,
                "height": body.height
            };
        }
        return {
            "x": body.x - (win._notifDescriptor.barSide === "left" ? side : 0),
            "y": body.y - start,
            "width": body.width + side,
            "height": body.height + start + end
        };
    }

    function _modalBlurCapThickness() {
        const extent = win._modalArcExtent;
        return Math.max(0, Math.min(win._effectiveModalCcr, extent - win._surfaceRadius));
    }

    function _popoutBlurCapThickness() {
        const extent = win._popoutArcExtent;
        return Math.max(0, Math.min(win._effectivePopoutMaxCcr, extent - win._surfaceRadius));
    }

    function _unifiedSurfaces() {
        const arr = [];
        const p = win._popoutBodyGeometry;
        if (win._popoutDescriptor.visible && win._popoutDescriptor.screenName === win._screenName && p.width > 0 && p.height > 0)
            arr.push({
                "side": win._popoutDescriptor.barSide,
                "body": {
                    "x": p.x,
                    "y": p.y,
                    "width": p.width,
                    "height": p.height
                },
                "radii": {
                    "farCr": win._effectivePopoutFarCcr,
                    "startCr": win._effectivePopoutStartCcr,
                    "endCr": win._effectivePopoutEndCcr,
                    "farStartCr": win._effectivePopoutFarStartCcr,
                    "farEndCr": win._effectivePopoutFarEndCcr,
                    "surfaceRadius": win._surfaceRadius
                }
            });
        const m = win._modalBodyGeometry;
        if (win._frameActive && win._modalDescriptor.visible && m.width > 0 && m.height > 0)
            arr.push({
                "side": win._modalDescriptor.barSide,
                "body": {
                    "x": m.x,
                    "y": m.y,
                    "width": m.width,
                    "height": m.height
                },
                "radii": {
                    "farCr": win._effectiveModalFarCcr,
                    "startCr": win._effectiveModalStartCcr,
                    "endCr": win._effectiveModalEndCcr,
                    "farStartCr": win._effectiveModalFarStartCcr,
                    "farEndCr": win._effectiveModalFarEndCcr,
                    "surfaceRadius": win._surfaceRadius
                }
            });
        const n = win._notifBodyScene();
        const nb = win._notifBodyGeometry;
        if (win._frameActive && win._notifDescriptor.visible && nb.width > 0 && nb.height > 0)
            arr.push({
                "side": win._notifDescriptor.barSide,
                "body": {
                    "x": n.x,
                    "y": n.y,
                    "width": n.width,
                    "height": n.height
                },
                "radii": {
                    "farCr": win._effectiveNotifFarCcr,
                    "startCr": win._effectiveNotifStartCcr,
                    "endCr": win._effectiveNotifEndCcr,
                    "farStartCr": win._effectiveNotifFarStartCcr,
                    "farEndCr": win._effectiveNotifFarEndCcr,
                    "surfaceRadius": win._surfaceRadius
                }
            });
        for (const surface of win._dockSurfaces) {
            const dk = surface.body;
            if (!win._connectedActive || !surface.descriptor.visible || dk.width <= 0 || dk.height <= 0)
                continue;
            arr.push({
                "side": surface.descriptor.barSide,
                "body": {
                    "x": dk.x,
                    "y": dk.y,
                    "width": dk.width,
                    "height": dk.height
                },
                "radii": {
                    "farCr": surface.connector,
                    "startCr": surface.connector,
                    "endCr": surface.connector,
                    "farStartCr": 0,
                    "farEndCr": 0,
                    "surfaceRadius": surface.radius
                }
            });
        }
        return arr;
    }

    function _farConnectorBarSide(sourceSide, placement) {
        if (sourceSide === "top" || sourceSide === "bottom")
            return placement === "left" ? "left" : "right";
        return placement === "left" ? "top" : "bottom";
    }

    function _farConnectorPlacement(sourceSide, placement) {
        if (sourceSide === "top")
            return "right";
        if (sourceSide === "bottom")
            return "left";
        if (sourceSide === "left")
            return "right";
        return "left";
    }

    function _connectorCutoutX(connectorX, connectorWidth, arcCorner, radius) {
        const r = radius === undefined ? win._effectivePopoutCcr : radius;
        return (arcCorner === "topLeft" || arcCorner === "bottomLeft") ? connectorX - r : connectorX + connectorWidth - r;
    }

    function _connectorCutoutY(connectorY, connectorHeight, arcCorner, radius) {
        const r = radius === undefined ? win._effectivePopoutCcr : radius;
        return (arcCorner === "topLeft" || arcCorner === "topRight") ? connectorY - r : connectorY + connectorHeight - r;
    }

    function _buildBlur(forceRepublish) {
        try {
            if (!BlurService.enabled || !SettingsData.frameBlurEnabled || !win._frameActive || !win.visible) {
                win.BackgroundEffect.blurRegion = null;
                return;
            }
            if (forceRepublish)
                win.BackgroundEffect.blurRegion = null;
            win.BackgroundEffect.blurRegion = _staticBlurRegion;
        } catch (e) {
            win.log.warn("Failed to set blur region:", e);
        }
    }

    function _teardownBlur() {
        try {
            win.BackgroundEffect.blurRegion = null;
        } catch (e) {}
    }

    DeferredAction {
        id: blurRebuildAction
        onTriggered: win._runBlurRebuild()
    }

    function _scheduleBlurRebuild() {
        blurRebuildAction.schedule();
    }
    function _runBlurRebuild() {
        _buildBlur(false);
    }

    function _republishFrameBlur() {
        _buildBlur(true);
    }

    function _requestContentUpdate() {
        try {
            if (win.contentItem && typeof win.contentItem.update === "function")
                win.contentItem.update();
        } catch (e) {}
    }

    function _scheduleSurfaceRefresh() {
        surfaceRefreshAction.restart();
    }

    function _runSurfaceRefresh() {
        if (!win.visible)
            return;
        _requestContentUpdate();
        _republishFrameBlur();
    }

    DeferredAction {
        id: surfaceRefreshAction
        onTriggered: win._runSurfaceRefresh()
    }

    Connections {
        target: SettingsData
        function onFrameBlurEnabledChanged() {
            win._scheduleBlurRebuild();
        }
        function onFrameEnabledChanged() {
            win._scheduleBlurRebuild();
        }
        function onFrameThicknessChanged() {
            win._scheduleBlurRebuild();
        }
        function onFrameBarSizeChanged() {
            win._scheduleBlurRebuild();
        }
        function onFrameRoundingChanged() {
            win._scheduleBlurRebuild();
        }
        function onFrameScreenPreferencesChanged() {
            win._scheduleBlurRebuild();
        }
        function onBarConfigsChanged() {
            win._scheduleBlurRebuild();
        }
        function onConnectedFrameModeActiveChanged() {
            win._scheduleBlurRebuild();
        }
        function onFrameCloseGapsChanged() {
            win._scheduleBlurRebuild();
        }
    }

    readonly property bool blurServiceEnabled: BlurService.enabled

    onBlurServiceEnabledChanged: _scheduleBlurRebuild()

    onVisibleChanged: {
        if (visible) {
            win._scheduleBlurRebuild();
            win._scheduleSurfaceRefresh();
        } else {
            surfaceRefreshAction.cancel();
            _teardownBlur();
        }
    }

    on_SurfaceRevisionChanged: win._scheduleSurfaceRefresh()

    onResourcesLost: {
        blurRebuildAction.cancel();
        surfaceRefreshAction.cancel();
        win._teardownBlur();
    }

    onWindowConnected: {
        win._scheduleSurfaceRefresh();
        win._scheduleBlurRebuild();
    }

    Component.onCompleted: {
        KeyboardFocus.registerBarWindow(win);
        win._scheduleBlurRebuild();
        win._scheduleSurfaceRefresh();
    }
    Component.onDestruction: {
        KeyboardFocus.unregisterBarWindow(win);
        blurRebuildAction.cancel();
        surfaceRefreshAction.cancel();
        win._teardownBlur();
    }

    FrameBorder {
        anchors.fill: parent
        visible: win._frameActive && !win._connectedActive
        cutoutTopInset: win.cutoutTopInset
        cutoutBottomInset: win.cutoutBottomInset
        cutoutLeftInset: win.cutoutLeftInset
        cutoutRightInset: win.cutoutRightInset
        cutoutRadius: win.cutoutRadius
    }

    ShaderEffect {
        anchors.fill: parent
        visible: win._connectedActive
        fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/connected_arc.frag.qsb")

        readonly property var _level: Theme.elevationLevel2
        readonly property color _shadowTint: Theme.elevationShadowColor(_level)
        readonly property var _ambient: Theme.elevationAmbient(_level)
        property real widthPx: width
        property real heightPx: height
        property real cutoutRadius: win.cutoutRadius
        property vector4d cutout: Qt.vector4d(win.cutoutLeftInset, win.cutoutTopInset, win.width - win.cutoutRightInset, win.height - win.cutoutBottomInset)
        property vector4d surfaceColor: Qt.vector4d(win._surfaceColor.r, win._surfaceColor.g, win._surfaceColor.b, win._surfaceColor.a)
        property vector4d shadowColor: Qt.vector4d(_shadowTint.r, _shadowTint.g, _shadowTint.b, win._elevationShadow ? _shadowTint.a : 0)
        property vector4d shadowParam: Qt.vector4d(Math.max(0, _level.blurPx), Math.max(0, _level.spreadPx), Theme.elevationOffsetXFor(_level, Theme.elevationLightDirection, 4), Theme.elevationOffsetYFor(_level, Theme.elevationLightDirection, 4))
        property vector4d ambientParam: Qt.vector4d(_ambient.blurPx, _ambient.spreadPx, win._elevationShadow ? _ambient.alpha : 0, 0)
        property vector4d chromeRect0: win._sdfSlots[0].rect
        property vector4d chromeCorner0: win._sdfSlots[0].corner
        property vector4d chromeK0: win._sdfSlots[0].k
        property vector4d chromeParam0: win._sdfSlots[0].param
        property vector4d chromeRect1: win._sdfSlots[1].rect
        property vector4d chromeCorner1: win._sdfSlots[1].corner
        property vector4d chromeK1: win._sdfSlots[1].k
        property vector4d chromeParam1: win._sdfSlots[1].param
        property vector4d chromeRect2: win._sdfSlots[2].rect
        property vector4d chromeCorner2: win._sdfSlots[2].corner
        property vector4d chromeK2: win._sdfSlots[2].k
        property vector4d chromeParam2: win._sdfSlots[2].param
        property vector4d chromeRect3: win._sdfSlots[3].rect
        property vector4d chromeCorner3: win._sdfSlots[3].corner
        property vector4d chromeK3: win._sdfSlots[3].k
        property vector4d chromeParam3: win._sdfSlots[3].param
        property vector4d chromeRect4: win._islandSdfSlot.rect
        property vector4d chromeCorner4: win._islandSdfSlot.corner
        property vector4d chromeK4: win._islandSdfSlot.k
        property vector4d chromeParam4: win._islandSdfSlot.param
        property vector4d chromeRect5: win._slideoutSdfSlot.rect
        property vector4d chromeCorner5: win._slideoutSdfSlot.corner
        property vector4d chromeK5: win._slideoutSdfSlot.k
        property vector4d chromeParam5: win._slideoutSdfSlot.param
    }

    Loader {
        anchors.fill: parent
        // A hosted sheet paints over a dock on its edge until it has sprung back.
        z: win._islandSheetOut ? 2 : 1
        active: win._connectedActive
        sourceComponent: FrameBarHost {
            frameWindow: win
            targetScreen: win.targetScreen
        }
    }

    Loader {
        id: frameDockHostLoader
        anchors.fill: parent
        z: 1
        active: win._dockHostedHere
        sourceComponent: FrameDockHost {
            frameWindow: win
            targetScreen: win.targetScreen
        }
    }
}
