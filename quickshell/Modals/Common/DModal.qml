import QtQuick
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    readonly property bool isFloatingWindowSurface: impl.item?.isFloatingWindowSurface ?? true
    readonly property var log: Log.scoped("DModal")

    readonly property bool useHyprlandFocusGrab: CompositorService.useHyprlandFocusGrab
    property string layerNamespace: "dms:modal"
    property Component content: null
    property Item directContent: null
    property real modalWidth: 400
    property real modalHeight: 300
    property var targetScreen
    property bool showBackground: true
    property real backgroundOpacity: Theme.scrimAlpha
    property string positioning: "center"
    property point customPosition: Qt.point(0, 0)
    property bool closeOnEscapeKey: true
    property bool closeOnBackgroundClick: true
    property string animationType: "scale"
    property int animationDuration: Theme.modalAnimationDuration
    property real animationScaleCollapsed: Theme.popupEnterScale
    property real animationOffset: Theme.spacingL
    property list<real> animationEnterCurve: Theme.expressiveCurves.expressiveDefaultSpatial
    property list<real> animationExitCurve: Theme.expressiveCurves.emphasized
    property color backgroundColor: Theme.floatingWindowSurface
    property color borderColor: Theme.outlineVariant
    property real borderWidth: 0
    property real cornerRadius: Theme.windowRadius
    property bool enableShadow: true
    property bool shouldBeVisible: false
    property bool shouldHaveFocus: shouldBeVisible
    property bool allowFocusOverride: false
    property bool allowStacking: false
    property bool keepContentLoaded: false
    property bool keepPopoutsOpen: false
    property var customKeyboardFocus: null
    readonly property alias transientSurfaceTracker: _transientSurfaceTracker
    property bool useOverlayLayer: false

    signal opened
    signal dialogClosed
    signal backgroundClicked

    readonly property var contentLoader: impl.item ? impl.item.contentLoader : null
    readonly property alias modalFocusScope: _modalFocusScope

    TransientSurfaceTracker {
        id: _transientSurfaceTracker
    }

    FocusScope {
        id: _modalFocusScope
        objectName: "modalFocusScope"
        focus: true
        anchors.fill: parent
    }

    // Hyprland OnDemand grab delivers keyboard focus to the modal content surface.
    DFocusGrab {
        windows: (root.contentWindow ? [root.contentWindow] : []).concat(root.transientSurfaceTracker?.focusWindows ?? [])
        wanted: KeyboardFocus.wantsGrab(root.shouldBeVisible && root.shouldHaveFocus, root.customKeyboardFocus)
    }
    readonly property var contentWindow: impl.item ? impl.item.contentWindow : null
    readonly property var effectiveScreen: impl.item ? impl.item.effectiveScreen : null
    readonly property real screenWidth: impl.item ? impl.item.screenWidth : 1920
    readonly property real screenHeight: impl.item ? impl.item.screenHeight : 1080
    readonly property real dpr: impl.item ? impl.item.dpr : 1
    readonly property bool isClosing: impl.item ? (impl.item.isClosing ?? false) : false
    readonly property real alignedX: impl.item ? impl.item.alignedX : 0
    readonly property real alignedY: impl.item ? impl.item.alignedY : 0
    readonly property real alignedWidth: impl.item ? impl.item.alignedWidth : 0
    readonly property real alignedHeight: impl.item ? impl.item.alignedHeight : 0

    function open() {
        _maybeResolveBackend();
        if (impl.item)
            impl.item.open();
    }

    function close() {
        transientSurfaceTracker?.closeAll?.();
        if (impl.item)
            impl.item.close();
    }

    function instantClose() {
        transientSurfaceTracker?.closeAll?.();
        if (impl.item && typeof impl.item.instantClose === "function")
            impl.item.instantClose();
    }

    function toggle() {
        if (impl.item)
            impl.item.toggle();
    }

    readonly property bool _desiredConnected: FrameTransitionState.effectiveConnectedFrameModeActive
    property bool _resolvedConnected: false

    Component.onCompleted: _loadHost(_desiredConnected)

    readonly property bool settingsConnectedFrameModeActive: SettingsData.connectedFrameModeActive

    onSettingsConnectedFrameModeActiveChanged: _maybeResolveBackend()

    function _maybeResolveBackend() {
        if (_resolvedConnected === _desiredConnected)
            return;
        if (impl.item && (impl.item.shouldBeVisible || impl.item.isClosing))
            return;
        _loadHost(_desiredConnected);
    }

    function _loadHost(connected) {
        impl.sourceComponent = null;
        _resolvedConnected = connected;
        impl.sourceComponent = hostComponent;
    }

    Loader {
        id: impl
        onItemChanged: if (item)
            root._wireBackend(item)
    }

    Component {
        id: hostComponent
        DModalHost {
            id: host

            modalHandle: root
            connected: root._resolvedConnected
            handleFocusScope: _modalFocusScope

            onShouldBeVisibleChanged: {
                if (root.shouldBeVisible !== host.shouldBeVisible)
                    root.shouldBeVisible = host.shouldBeVisible;
            }
            onShouldHaveFocusChanged: {
                if (root.shouldHaveFocus !== host.shouldHaveFocus)
                    root.shouldHaveFocus = host.shouldHaveFocus;
            }
            onOpened: root.opened()
            onDialogClosed: {
                root.dialogClosed();
                root._maybeResolveBackend();
            }
            onBackgroundClicked: root.backgroundClicked()
        }
    }

    function _wireBackend(it) {
        it.shouldBeVisible = root.shouldBeVisible;
        it.shouldHaveFocus = root.shouldHaveFocus;
        _modalFocusScope.parent = it.modalFocusScope;
    }

    onShouldBeVisibleChanged: {
        if (!shouldBeVisible)
            transientSurfaceTracker?.closeAll?.();
        if (impl.item && impl.item.shouldBeVisible !== shouldBeVisible)
            impl.item.shouldBeVisible = shouldBeVisible;
    }

    onShouldHaveFocusChanged: {
        if (impl.item && impl.item.shouldHaveFocus !== shouldHaveFocus)
            impl.item.shouldHaveFocus = shouldHaveFocus;
    }
}
