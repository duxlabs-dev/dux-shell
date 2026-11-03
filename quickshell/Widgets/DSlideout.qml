pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

PanelWindow {
    id: root

    property string layerNamespace: "dms:slideout"
    WlrLayershell.namespace: layerNamespace

    property bool isVisible: false
    property bool hoverDismissEnabled: false
    property bool hoverDismissSuspended: false
    property var targetScreen: null
    property var modelData: null
    property bool triggerUsesOverlayLayer: false
    // Drop off the Overlay layer (back to Top) while an overlay modal
    property bool suppressOverlayLayer: false
    property real slideoutWidth: 480
    property bool expandable: false
    property bool expandedWidth: false
    property real expandedWidthValue: 960
    property real edgeGap: 0
    property string slideEdge: "right"
    readonly property bool slideFromLeft: slideEdge === "left"
    // Opt-in: the frame has a single slideout slot per screen.
    property bool frameSurfaceEnabled: false
    readonly property bool frameOwnsConnectedChrome: frameSurfaceEnabled && mappedVisible && CompositorService.canShareConnectedFrameChromeForScreen(modelData)
    readonly property int frameInsetTop: _frameInset("top")
    readonly property int frameInsetBottom: _frameInset("bottom")
    readonly property int frameInsetEdge: _frameInset(slideEdge)
    readonly property real surfaceOriginX: slideFromLeft ? frameInsetEdge : Math.max(0, (modelData?.width ?? width) - width - frameInsetEdge)
    readonly property real surfaceOriginY: frameInsetTop
    property Component content: null
    property bool contentRequested: false
    property string title: ""
    property alias container: contentContainer
    property alias loadedItem: contentLoader.item
    property real customTransparency: -1
    property bool mappedVisible: false
    signal aboutToHide
    signal revealed

    function show() {
        contentRequested = true;
        mappedVisible = true;
        Qt.callLater(() => {
            isVisible = true;
            revealed();
        });
    }

    function hide() {
        aboutToHide();
        isVisible = false;
    }

    function hideFromHoverDismiss() {
        if (hoverDismissSuspended)
            return;
        hoverDismissEnabled = false;
        slideContainer.slideSlowExit = true;
        hide();
    }

    function cancelHoverDismiss() {
        hoverDismissTracker.cancelPending();
    }

    function containsGlobalPoint(gx, gy) {
        if (!isVisible || !modelData)
            return false;
        const padding = 24;
        const topLeft = slideContainer.mapToItem(null, 0, 0);
        const globalX = surfaceOriginX + topLeft.x;
        const globalY = surfaceOriginY + topLeft.y;
        return gx >= globalX - padding && gx < globalX + slideContainer.width + padding && gy >= globalY - padding && gy < globalY + slideContainer.height + padding;
    }

    function _frameInset(edge) {
        if (!frameOwnsConnectedChrome)
            return 0;
        return Math.max(0, Math.round(Theme.px(SettingsData.frameEdgeReservation(modelData, edge) + SettingsData.dockReservationForEdge(modelData, edge), dpr)));
    }

    readonly property string _frameSlot: ConnectedModeState.surfaceSlot("slideout")
    readonly property bool _frameClaimActive: frameOwnsConnectedChrome && mappedVisible && _slideoutScreenName !== ""
    readonly property real _frameSurfaceOpacity: Theme.connectedSurfaceColor.a
    readonly property var _frameMotion: ({
            "bodyX": surfaceOriginX + slideContainer.x,
            "bodyY": surfaceOriginY + slideContainer.y,
            "bodyW": slideContainer.width,
            "bodyH": slideContainer.height,
            "animX": slideoutSlideSnapX
        })
    property string _claimedScreen: ""
    property string _claimedOwner: ""

    function _releaseFrameClaim() {
        if (!_claimedScreen)
            return;
        ConnectedModeState.releaseSurface(_claimedScreen, _frameSlot, _claimedOwner);
        _claimedScreen = "";
        _claimedOwner = "";
    }

    function _syncFrameClaim() {
        const owner = layerNamespace + ":" + _slideoutScreenName;
        if (!_frameClaimActive || _claimedScreen !== _slideoutScreenName || _claimedOwner !== owner)
            _releaseFrameClaim();
        if (!_frameClaimActive)
            return;
        if (ConnectedModeState.claimSurface(_slideoutScreenName, _frameSlot, Object.assign({
            "kind": "slideout",
            "visible": true,
            "presented": true,
            "phase": "open",
            "barSide": slideEdge,
            "omitStartConnector": true,
            "omitEndConnector": true,
            "opacity": _frameSurfaceOpacity
        }, _frameMotion), owner)) {
            _claimedScreen = _slideoutScreenName;
            _claimedOwner = owner;
        }
    }

    on_FrameClaimActiveChanged: _syncFrameClaim()
    on_SlideoutScreenNameChanged: _syncFrameClaim()
    onSlideEdgeChanged: _syncFrameClaim()
    on_FrameSurfaceOpacityChanged: _syncFrameClaim()
    on_FrameMotionChanged: {
        if (_claimedScreen)
            ConnectedModeState.setSurfaceMotion(_claimedScreen, _frameSlot, _claimedOwner, _frameMotion);
    }
    Component.onDestruction: _releaseFrameClaim()

    function toggle() {
        if (isVisible) {
            hide();
        } else {
            show();
        }
    }

    visible: root.mappedVisible
    screen: modelData

    anchors.top: true
    anchors.bottom: true
    anchors.right: !root.slideFromLeft
    anchors.left: root.slideFromLeft

    implicitWidth: expandable ? expandedWidthValue : slideoutWidth
    implicitHeight: modelData ? modelData.height : 800

    color: "transparent"

    HoverDismissTracker {
        id: hoverDismissTracker
        parent: root.contentItem
        enabled: root.hoverDismissEnabled && !root.hoverDismissSuspended && root.isVisible
        shouldDismiss: function () {
            return !PopoutManager.cursorOverBar(PopoutManager.hoverCursorGlobalX, PopoutManager.hoverCursorGlobalY);
        }
        onDismissRequested: root.hideFromHoverDismiss()
        onHoverMoved: (sceneX, sceneY) => PopoutManager.updateHoverCursor(root.surfaceOriginX + sceneX, root.surfaceOriginY + sceneY)
    }

    readonly property bool slideoutBlurActive: root.visible && !root.frameOwnsConnectedChrome && BlurService.enabled && Theme.connectedSurfaceBlurEnabled

    readonly property string _slideoutScreenName: modelData?.name ?? ""

    WlrLayershell.layer: (!suppressOverlayLayer && (triggerUsesOverlayLayer || CompositorService.framePeerSurfacesUseOverlayForScreen(modelData))) ? WlrLayershell.Overlay : WlrLayershell.Top
    // Frame-owned: sit exactly in the frame cutout so the claimed body matches the frame's own geometry.
    WlrLayershell.exclusiveZone: frameOwnsConnectedChrome ? -1 : 0

    margins {
        top: root.frameInsetTop
        bottom: root.frameInsetBottom
        left: root.slideFromLeft ? root.frameInsetEdge : 0
        right: root.slideFromLeft ? 0 : root.frameInsetEdge
    }
    WlrLayershell.keyboardFocus: isVisible && !ModalManager.currentModalsByScreen[_slideoutScreenName] ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property real dpr: CompositorService.getScreenScale(root.screen)
    readonly property real alignedWidth: Theme.px(expandable && expandedWidth ? expandedWidthValue : slideoutWidth, dpr)
    onAlignedWidthChanged: widthSpring.retarget(alignedWidth)
    readonly property real alignedHeight: Theme.px(modelData ? modelData.height : 800, dpr)
    readonly property real alignedEdgeGap: frameOwnsConnectedChrome ? 0 : Theme.px(edgeGap, dpr)
    readonly property real slideoutSlideSnapX: Theme.snap(slideContainer.slideOffset, dpr)

    onIsVisibleChanged: {
        slideSpring.retarget(isVisible ? 0 : (slideFromLeft ? -slideContainer.width : slideContainer.width));
        if (isVisible || slideSpring.running)
            return;
        mappedVisible = false;
    }

    mask: Region {
        item: Rectangle {
            x: root.slideFromLeft ? root.alignedEdgeGap : (root.width - slideContainer.width - root.alignedEdgeGap)
            y: root.alignedEdgeGap
            width: root.isVisible ? slideContainer.width : 0
            height: root.isVisible ? root.height - root.alignedEdgeGap * 2 : 0
        }
    }

    Item {
        id: slideContainer
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: root.slideFromLeft ? undefined : parent.right
        anchors.left: root.slideFromLeft ? parent.left : undefined
        anchors.topMargin: root.alignedEdgeGap
        anchors.bottomMargin: root.alignedEdgeGap
        anchors.rightMargin: root.alignedEdgeGap
        anchors.leftMargin: root.alignedEdgeGap

        property bool slideSlowExit: false
        readonly property var slideSpringParams: Theme.springPreset("default", slideSlowExit ? Math.round(Theme.expressiveDurations.expressiveDefaultSpatial) : Theme.expressiveDurations.expressiveDefaultSpatial)
        readonly property var widthSpringParams: Theme.springPreset("default", Theme.popoutAnimationDuration)

        SpringMotion {
            id: slideSpring
            reducedMotion: false
            positionEpsilon: 0.05
            velocityEpsilon: 0.05
            stiffness: slideContainer.slideSpringParams.stiffness
            damping: slideContainer.slideSpringParams.damping
            value: root.slideFromLeft ? -root.alignedWidth : root.alignedWidth

            Component.onCompleted: snapTo(root.slideFromLeft ? -root.alignedWidth : root.alignedWidth)

            onRunningChanged: {
                if (running)
                    return;
                if (!root.isVisible)
                    root.mappedVisible = false;
                slideContainer.slideSlowExit = false;
            }
        }

        SpringMotion {
            id: widthSpring
            enabled: root.expandable
            reducedMotion: Theme.popoutAnimationDuration <= 0
            positionEpsilon: 0.05
            velocityEpsilon: 0.05
            stiffness: slideContainer.widthSpringParams.stiffness
            damping: slideContainer.widthSpringParams.damping
            value: root.alignedWidth

            Component.onCompleted: snapTo(root.alignedWidth)
        }

        property real slideOffset: slideSpring.value

        width: widthSpring.value
        height: root.alignedHeight - root.alignedEdgeGap * 2

        Item {
            id: contentRect
            clip: true

            readonly property color slideoutSurfaceColor: {
                if (Theme.isConnectedEffect)
                    return Theme.connectedSurfaceColor;
                if (root.customTransparency >= 0)
                    return Theme.withAlpha(Theme.hostSurface, root.customTransparency);
                return Theme.readableSurface;
            }

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width
            x: root.slideoutSlideSnapX

            ElevationShadow {
                anchors.fill: parent
                visible: !Theme.isConnectedEffect
                level: Theme.elevationLevel2
                targetRadius: Theme.windowRadius
                targetColor: contentRect.slideoutSurfaceColor
                shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.isConnectedEffect && !root.frameOwnsConnectedChrome ? contentRect.slideoutSurfaceColor : "transparent"
                radius: Theme.isConnectedEffect ? Theme.connectedSurfaceRadius : Theme.windowRadius
                border.color: Theme.isConnectedEffect ? Theme.withAlpha(BlurService.borderColor, 0) : BlurService.borderColor
                border.width: Theme.isConnectedEffect ? 0 : BlurService.borderWidth
            }

            Item {
                id: contentBody
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: root.slideFromLeft ? undefined : parent.right
                anchors.left: root.slideFromLeft ? parent.left : undefined
                width: root.alignedWidth

                Column {
                    id: headerColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM
                    visible: root.title !== ""

                    Row {
                        width: parent.width
                        height: 32

                        Column {
                            width: parent.width - buttonRow.width
                            spacing: Theme.spacingXS
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                text: root.title
                                font.pixelSize: Theme.fontSizeLarge
                                color: Theme.surfaceText
                                font.weight: Theme.fontWeightMedium
                            }
                        }

                        Row {
                            id: buttonRow
                            spacing: Theme.spacingXS

                            DActionButton {
                                id: expandButton
                                iconName: root.expandedWidth ? "unfold_less" : "unfold_more"
                                tooltipText: root.expandedWidth ? I18n.tr("Collapse") : I18n.tr("Expand")
                                iconSize: Theme.iconSize - 4
                                iconColor: Theme.surfaceText
                                visible: root.expandable
                                onClicked: root.expandedWidth = !root.expandedWidth

                                transform: Rotation {
                                    angle: 90
                                    origin.x: expandButton.width / 2
                                    origin.y: expandButton.height / 2
                                }
                            }

                            DActionButton {
                                id: closeButton
                                iconName: "close"
                                Accessible.name: I18n.tr("Close")
                                iconSize: Theme.iconSize - 4
                                iconColor: Theme.surfaceText
                                onClicked: root.hide()
                            }
                        }
                    }
                }

                Item {
                    id: contentContainer
                    anchors.top: root.title !== "" ? headerColumn.bottom : parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.topMargin: root.title !== "" ? 0 : Theme.spacingL
                    anchors.leftMargin: Theme.spacingL
                    anchors.rightMargin: Theme.spacingL
                    anchors.bottomMargin: Theme.spacingL

                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        active: root.contentRequested
                        sourceComponent: root.content
                    }
                }
            }
        }
    }

    WindowBlur {
        targetWindow: root
        blurEnabled: root.slideoutBlurActive
        surfaceColor: contentRect.slideoutSurfaceColor
        blurX: root.slideoutBlurActive ? slideContainer.x + root.slideoutSlideSnapX : 0
        blurY: root.slideoutBlurActive ? slideContainer.y : 0
        blurWidth: root.slideoutBlurActive ? slideContainer.width : 0
        blurHeight: root.slideoutBlurActive ? slideContainer.height : 0
        blurRadius: Theme.isConnectedEffect ? Theme.connectedSurfaceRadius : Theme.windowRadius
    }
}
