import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Modules.DIsland
import qs.Services
import qs.Widgets

PanelWindow {
    id: barWindow
    readonly property var log: Log.scoped("DBarWindow")

    required property var rootWindow
    required property var barConfig
    property var modelData: item

    property var leftWidgetsModel
    property var centerWidgetsModel
    property var rightWidgetsModel

    readonly property bool isVertical: body.isVertical
    readonly property int barPos: body.barPos
    readonly property bool barRevealed: body.barRevealed
    readonly property bool fullscreenAutoHide: body.fullscreenAutoHide
    readonly property bool isIsland: body.isIsland
    readonly property var islandHost: body.islandHost
    readonly property var leadingSectionRect: body.leadingSectionRect
    readonly property var trailingSectionRect: body.trailingSectionRect

    property alias controlCenterButtonRef: body.controlCenterButtonRef
    property alias clockButtonRef: body.clockButtonRef
    property alias systemUpdateButtonRef: body.systemUpdateButtonRef

    function triggerSystemUpdate() {
        body.triggerSystemUpdate();
    }
    function triggerControlCenter() {
        body.triggerControlCenter();
    }
    function triggerDashTab(tabId, position) {
        return body.triggerDashTab(tabId, position);
    }
    function positionDash(popout, position) {
        return body.positionDash(popout, position);
    }
    function triggerWallpaperBrowser() {
        body.triggerWallpaperBrowser();
    }
    function registerBlurWidget(item) {
        body.registerBlurWidget(item);
    }
    function unregisterBlurWidget(item) {
        body.unregisterBlurWidget(item);
    }
    function containsGlobalPoint(gx, gy, padding) {
        return body.containsGlobalPoint(gx, gy, padding);
    }

    readonly property bool usesOverlayLayer: CompositorService.framePeerSurfacesUseOverlayForScreen(barWindow.screen) || (isIsland ? LayerShell.envUsesOverlay("DMS_DANKISLAND_LAYER", SettingsData.islandSetting(barConfig, "islandUseOverlayLayer")) : (barConfig?.useOverlayLayer ?? false))
    // A hosted sheet must paint over Top-layer surfaces on its edge until it has sprung back, the same as the frame does.
    readonly property int dBarLayer: LayerShell.fromEnv(isIsland ? "DMS_DANKISLAND_LAYER" : "DMS_DANKBAR_LAYER", barWindow.usesOverlayLayer || (!isIsland && islandChrome.sheetOut) ? WlrLayer.Overlay : WlrLayer.Top)

    screen: modelData
    readonly property var layoutInstance: body.layoutInstance
    readonly property bool manualPlacement: layoutInstance?.manualPlacement ?? false
    margins.top: manualPlacement ? layoutInstance?.margins.top ?? 0 : 0
    margins.bottom: manualPlacement ? layoutInstance?.margins.bottom ?? 0 : 0
    margins.left: manualPlacement ? layoutInstance?.margins.left ?? 0 : 0
    margins.right: manualPlacement ? layoutInstance?.margins.right ?? 0 : 0

    EdgeExclusion {
        screen: barWindow.screen
        edge: barWindow.layoutInstance?.edge ?? "top"
        exclusionSize: barWindow.layoutInstance?.exclusionSize ?? 0
    }

    color: "transparent"

    WlrLayershell.layer: dBarLayer
    WlrLayershell.namespace: isIsland ? "dms:dankisland" : "dms:bar"
    WlrLayershell.keyboardFocus: islandChrome.keyboardFocusPolicy

    IslandHostChrome {
        id: islandChrome

        window: barWindow
        host: barWindow.islandHost
    }

    anchors.top: !isVertical ? (barPos === SettingsData.Position.Top) : true
    anchors.bottom: !isVertical ? (barPos === SettingsData.Position.Bottom) : true
    anchors.left: !isVertical ? true : (barPos === SettingsData.Position.Left)
    anchors.right: !isVertical ? true : (barPos === SettingsData.Position.Right)

    implicitHeight: body.surfaceImplicitHeight
    implicitWidth: body.surfaceImplicitWidth
    exclusiveZone: manualPlacement ? -1 : body.surfaceExclusiveZone

    BackgroundEffect.blurRegion: BlurService.enabled ? body.blurRegion : null

    Component.onCompleted: {
        KeyboardFocus.registerBarWindow(barWindow);
        SurfaceRecovery.track(barWindow);
    }
    Component.onDestruction: {
        KeyboardFocus.unregisterBarWindow(barWindow);
        SurfaceRecovery.untrack(barWindow);
    }

    IdleInhibitor {
        window: barWindow
        enabled: SessionService.idleInhibited || IdleService.externalInhibitActive
    }

    readonly property bool sectionMasked: body.clickThroughEnabled || (isIsland && !(islandHost?.inputSuspended ?? false))

    mask: Region {
        item: body.clickThroughEnabled || (isIsland && !body.islandBandInteractive) ? null : body.inputMaskItem

        // Item-bound: a mapToItem snapshot froze mid-churn on output reconnect, leaving the trailing
        // section unclickable (#3594). barRevealed: same ancestor-transform caveat as the island regions.
        Region {
            item: barWindow.sectionMasked && body.barRevealed ? body._leftSection : null
        }

        Region {
            readonly property var r: barWindow.sectionMasked ? body.centerSectionRect : {
                "x": 0,
                "y": 0,
                "w": 0,
                "h": 0
            }
            x: r.x
            y: r.y
            width: r.w
            height: r.h
        }

        Region {
            item: barWindow.sectionMasked && body.barRevealed ? body._rightSection : null
        }

        // Kept as a 1px edge strip while revealed under auto-hide so a pointer resting on the screen edge
        // stays inside the window; otherwise reveal/hide would toggle the mask and flicker.
        Region {
            readonly property bool active: (body.clickThroughEnabled || isIsland) && (!body.inputMaskItem.showing || body.autoHideActive)
            readonly property bool farEdge: body.barPos === SettingsData.Position.Bottom || body.barPos === SettingsData.Position.Right
            x: active ? (barWindow.isVertical ? (farEdge ? body.width - 1 : 0) : body.inputMaskItem.x) : 0
            y: active ? (barWindow.isVertical ? body.inputMaskItem.y : (farEdge ? body.height - 1 : 0)) : 0
            width: active ? (barWindow.isVertical ? 1 : body.inputMaskItem.width) : 0
            height: active ? (barWindow.isVertical ? body.inputMaskItem.height : 1) : 0
        }

        // The slide transform lives on an ancestor, so a hidden bar's pill would otherwise keep its input hole in place.
        Region {
            item: body.barRevealed ? islandChrome.maskItem : null
        }

        Region {
            item: body.barRevealed ? islandChrome.fittsStripItem : null
        }
    }

    DBarBody {
        id: body
        anchors.fill: parent
        hostWindow: barWindow
        modelData: barWindow.modelData
        rootWindow: barWindow.rootWindow
        barConfig: barWindow.barConfig
        leftWidgetsModel: barWindow.leftWidgetsModel
        centerWidgetsModel: barWindow.centerWidgetsModel
        rightWidgetsModel: barWindow.rightWidgetsModel
    }
}
