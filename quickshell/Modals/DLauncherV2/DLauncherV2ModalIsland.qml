pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.DLauncherV2.Components
import qs.Services

Item {
    id: root

    property var modalHandle: root
    property bool triggerUsesOverlayLayer: false
    property bool usingFallback: false
    property bool _islandWasOpen: false

    readonly property var log: Log.scoped("DLauncherV2ModalIsland")
    readonly property var router: PopoutService.dankIslandRouter
    readonly property bool spotlightOpen: usingFallback ? fallback.spotlightOpen : (router?.launcherOpen ?? false)
    readonly property bool shouldBeVisible: usingFallback ? fallback.shouldBeVisible : false
    readonly property string layerNamespace: usingFallback ? fallback.layerNamespace : "dms:launcher"
    readonly property bool isClosing: usingFallback ? fallback.isClosing : false
    readonly property bool keyboardActive: usingFallback ? fallback.keyboardActive : spotlightOpen
    readonly property bool contentVisible: usingFallback ? fallback.contentVisible : spotlightOpen
    readonly property var spotlightContent: usingFallback ? fallback.spotlightContent : null
    readonly property bool openedFromOverview: usingFallback ? fallback.openedFromOverview : false
    readonly property var effectiveScreen: usingFallback ? fallback.effectiveScreen : null
    readonly property real screenWidth: usingFallback ? fallback.screenWidth : Theme.mediumBreakpoint * 2
    readonly property real screenHeight: usingFallback ? fallback.screenHeight : Theme.mediumBreakpoint
    readonly property real dpr: usingFallback ? fallback.dpr : 1
    readonly property int modalWidth: usingFallback ? fallback.modalWidth : LauncherMetrics.sizeWidth(SettingsData.dankLauncherV2Size)
    readonly property int modalHeight: usingFallback ? fallback.modalHeight : LauncherMetrics.sizeHeight(SettingsData.dankLauncherV2Size, LauncherMetrics.islandEdgeInset, false)
    readonly property real modalX: usingFallback ? fallback.modalX : 0
    readonly property real modalY: usingFallback ? fallback.modalY : 0
    readonly property real alignedX: usingFallback ? fallback.alignedX : 0
    readonly property real alignedY: usingFallback ? fallback.alignedY : 0
    readonly property real alignedWidth: usingFallback ? fallback.alignedWidth : 0
    readonly property real alignedHeight: usingFallback ? fallback.alignedHeight : 0
    readonly property bool frameOwnsConnectedChrome: false
    readonly property string resolvedConnectedBarSide: ""
    readonly property bool launcherArcExtenderActive: false

    signal dialogClosed

    // Last-used routing already went through PopoutService, so a standard bar owns the launcher here.
    function _lastUsedOwnsLauncher() {
        return SettingsData.sharedShortcutsFollowLastUsed(CompositorService.getFocusedScreen());
    }

    function _openIsland(query, mode) {
        if (root._lastUsedOwnsLauncher()) {
            usingFallback = true;
            return false;
        }
        const accepted = router?.openLauncher?.(query || "", mode || "") ?? false;
        if (accepted) {
            usingFallback = false;
            return true;
        }
        usingFallback = true;
        return false;
    }

    function show() {
        if (!root._openIsland("", ""))
            fallback.show();
    }

    function showWithQuery(query) {
        if (!root._openIsland(query, ""))
            fallback.showWithQuery(query);
    }

    function showWithMode(mode) {
        if (!root._openIsland("", mode))
            fallback.showWithMode(mode);
    }

    function hide() {
        if (usingFallback) {
            fallback.hide();
            return;
        }
        PopoutService.closeIslandActivity("launcher");
    }

    function toggle() {
        if (usingFallback && fallback.spotlightOpen) {
            fallback.toggle();
            return;
        }
        if (root._lastUsedOwnsLauncher()) {
            usingFallback = true;
            fallback.toggle();
            return;
        }
        const accepted = router?.toggleLauncher?.("", "") ?? false;
        if (!accepted) {
            usingFallback = true;
            fallback.toggle();
        }
    }

    function toggleWithQuery(query) {
        if (spotlightOpen) {
            hide();
            return;
        }
        showWithQuery(query);
    }

    function toggleWithMode(mode) {
        if (spotlightOpen) {
            hide();
            return;
        }
        showWithMode(mode);
    }

    onSpotlightOpenChanged: {
        if (usingFallback)
            return;
        if (spotlightOpen) {
            _islandWasOpen = true;
            return;
        }
        if (!_islandWasOpen)
            return;
        _islandWasOpen = false;
        dialogClosed();
    }

    DLauncherV2ModalHost {
        id: fallback

        connected: root.modalHandle?._resolvedConnected ?? false
        spotlight: !connected
        modalHandle: root.modalHandle
        triggerUsesOverlayLayer: root.triggerUsesOverlayLayer
    }

    Connections {
        target: fallback

        function onDialogClosed() {
            root.usingFallback = false;
            root.dialogClosed();
        }
    }
}
