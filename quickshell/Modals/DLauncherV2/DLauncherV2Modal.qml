import QtQuick
import qs.Common
import qs.Services

Item {
    id: root
    readonly property var log: Log.scoped("DLauncherV2Modal")

    readonly property bool spotlightOpen: impl.item ? impl.item.spotlightOpen : false
    readonly property bool shouldBeVisible: impl.item ? impl.item.shouldBeVisible : false
    readonly property string layerNamespace: impl.item ? (impl.item.layerNamespace ?? "dms:launcher") : "dms:launcher"
    readonly property bool isClosing: impl.item ? impl.item.isClosing : false
    readonly property bool keyboardActive: impl.item ? impl.item.keyboardActive : false
    readonly property bool contentVisible: impl.item ? impl.item.contentVisible : false
    readonly property var spotlightContent: impl.item ? impl.item.spotlightContent : null
    readonly property bool openedFromOverview: impl.item ? impl.item.openedFromOverview : false
    readonly property var effectiveScreen: impl.item ? impl.item.effectiveScreen : null
    readonly property real screenWidth: impl.item ? impl.item.screenWidth : Theme.mediumBreakpoint * 2
    readonly property real screenHeight: impl.item ? impl.item.screenHeight : Theme.mediumBreakpoint
    readonly property real dpr: impl.item ? impl.item.dpr : 1
    readonly property int modalWidth: impl.item ? impl.item.modalWidth : Theme.launcherWidthDefault
    readonly property int modalHeight: impl.item ? impl.item.modalHeight : Theme.launcherHeightDefault
    readonly property real modalX: impl.item ? impl.item.modalX : 0
    readonly property real modalY: impl.item ? impl.item.modalY : 0
    readonly property real alignedX: impl.item ? impl.item.alignedX : 0
    readonly property real alignedY: impl.item ? impl.item.alignedY : 0
    readonly property real alignedWidth: impl.item ? impl.item.alignedWidth : 0
    readonly property real alignedHeight: impl.item ? impl.item.alignedHeight : 0
    readonly property bool frameOwnsConnectedChrome: impl.item ? (impl.item.frameOwnsConnectedChrome ?? false) : false
    readonly property string resolvedConnectedBarSide: impl.item ? (impl.item.resolvedConnectedBarSide ?? "") : ""
    readonly property bool launcherArcExtenderActive: impl.item ? (impl.item.launcherArcExtenderActive ?? false) : false
    property bool triggerUsesOverlayLayer: false
    property bool edgeHoverManaged: false

    signal dialogClosed

    function show() {
        if (impl.item)
            impl.item.show();
    }

    function showWithQuery(query) {
        if (impl.item)
            impl.item.showWithQuery(query);
    }

    function showWithMode(mode) {
        if (impl.item)
            impl.item.showWithMode(mode);
    }

    function hide() {
        if (impl.item)
            impl.item.hide();
    }

    function toggle() {
        if (impl.item)
            impl.item.toggle();
    }

    function toggleWithQuery(query) {
        if (impl.item)
            impl.item.toggleWithQuery(query);
    }

    function toggleWithMode(mode) {
        if (impl.item)
            impl.item.toggleWithMode(mode);
    }

    readonly property bool _desiredConnected: FrameTransitionState.effectiveConnectedFrameModeActive
    readonly property bool useSpotlightBackend: !_desiredConnected && SettingsData.launcherStyle === "spotlight"
    // Routing decides the host per call inside the island backend; style only picks the face.
    readonly property bool useIslandBackend: SettingsData.launcherStyle === "island"
    readonly property var _desiredBackend: useIslandBackend ? islandComp : hostComp
    property bool _resolvedConnected: false
    property bool _resolvedSpotlight: false

    Component.onCompleted: _loadHost()

    readonly property bool settingsConnectedFrameModeActive: SettingsData.connectedFrameModeActive
    readonly property string settingsLauncherStyle: SettingsData.launcherStyle

    onSettingsConnectedFrameModeActiveChanged: _maybeResolveBackend()
    onSettingsLauncherStyleChanged: _maybeResolveBackend()
    on_DesiredConnectedChanged: _maybeResolveBackend()

    function _maybeResolveBackend() {
        if (impl.sourceComponent === _desiredBackend && _resolvedConnected === _desiredConnected && _resolvedSpotlight === useSpotlightBackend)
            return;
        if (impl.item && (impl.item.spotlightOpen || impl.item.isClosing))
            return;
        _loadHost();
    }

    function _hostDialogClosed() {
        dialogClosed();
        _maybeResolveBackend();
    }

    function _loadHost() {
        impl.sourceComponent = null;
        _resolvedConnected = _desiredConnected;
        _resolvedSpotlight = useSpotlightBackend;
        impl.sourceComponent = _desiredBackend;
    }

    Loader {
        id: impl
    }

    Component {
        id: hostComp
        DLauncherV2ModalHost {
            modalHandle: root
            triggerUsesOverlayLayer: root.triggerUsesOverlayLayer
            connected: root._resolvedConnected
            spotlight: root._resolvedSpotlight
            onDialogClosed: root._hostDialogClosed()
        }
    }

    Component {
        id: islandComp
        DLauncherV2ModalIsland {
            modalHandle: root
            triggerUsesOverlayLayer: root.triggerUsesOverlayLayer
            onDialogClosed: root._hostDialogClosed()
        }
    }
}
