import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

PanelWindow {
    id: root
    readonly property var log: Log.scoped("DOSD")

    property string blurNamespace: "dms:osd"
    WlrLayershell.namespace: blurNamespace

    property alias content: contentLoader.sourceComponent
    property alias contentLoader: contentLoader
    property var modelData
    property string osdKind: ""
    readonly property int osdPosition: SettingsData.osdPositionFor(osdKind)
    property bool shouldBeVisible: false
    property bool _surfaceFrameReady: false
    readonly property bool presented: shouldBeVisible && _surfaceFrameReady
    property int autoHideInterval: 2000
    property bool enableMouseInteraction: false
    property real osdWidth: Theme.osdHeight
    property real osdHeight: Theme.osdHeight
    property color surfaceColor: Theme.hostSurface
    property real surfaceRadius: Theme.fullRadius(alignedWidth, alignedHeight)
    property int animationDuration: Theme.mediumDuration
    property var animationEasing: Theme.emphasizedEasing
    property Component sheet: null
    property real sheetWidth: 0
    property bool expanded: false

    signal osdShown
    signal osdHidden

    function show() {
        if (SessionData.suppressOSD || expanded)
            return;
        if (shouldBeVisible) {
            hideTimer.restart();
            return;
        }
        OSDManager.showOSD(root);
        closeTimer.stop();
        shouldBeVisible = true;
        visible = true;
        hideTimer.restart();
        osdShown();
    }

    function hide() {
        if (expanded) {
            closeSheet();
            return;
        }
        shouldBeVisible = false;
        closeTimer.restart();
    }

    function expand() {
        if (!sheet || !shouldBeVisible || expanded)
            return;
        hideTimer.stop();
        expanded = true;
    }

    function closeSheet() {
        if (sheetLoader.item) {
            sheetLoader.item.close();
            return;
        }
        finishSheet();
    }

    function finishSheet() {
        expanded = false;
        shouldBeVisible = false;
        hideTimer.stop();
        closeTimer.stop();
        visible = false;
        osdHidden();
    }

    function resetHideTimer() {
        if (shouldBeVisible) {
            hideTimer.restart();
        }
    }

    function updateHoverState() {
        let isHovered = (enableMouseInteraction && mouseArea.containsMouse) || osdContainer.childHovered;
        if (enableMouseInteraction) {
            if (isHovered) {
                hideTimer.stop();
            } else if (shouldBeVisible) {
                hideTimer.restart();
            }
        }
    }

    function setChildHovered(hovered) {
        osdContainer.childHovered = hovered;
        updateHoverState();
    }

    screen: modelData
    visible: false
    onVisibleChanged: {
        if (!visible)
            _surfaceFrameReady = false;
    }

    Connections {
        target: osdContainer.Window.window
        enabled: root.visible && !root._surfaceFrameReady

        function onFrameSwapped() {
            root._surfaceFrameReady = true;
        }
    }

    readonly property var quickshellScreens: Quickshell.screens

    onQuickshellScreensChanged: {
        if (!visible && !shouldBeVisible)
            return;
        const currentScreenName = screen?.name;
        if (!currentScreenName) {
            hide();
            return;
        }
        for (let i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === currentScreenName)
                return;
        }
        expanded = false;
        shouldBeVisible = false;
        visible = false;
        hideTimer.stop();
        closeTimer.stop();
        osdHidden();
    }

    WlrLayershell.layer: LayerShell.fromEnv("DMS_OSD_LAYER", WlrLayer.Overlay, {
        "allow": ["top", "overlay"],
        "invalidLayer": WlrLayer.Overlay,
        "label": "OSDs"
    })
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    WindowBlur {
        targetWindow: root
        surfaceColor: Theme.withAlpha(root.surfaceColor, osdContainer.popupSurfaceAlpha)
        blurX: shadowBuffer
        blurY: shadowBuffer
        blurWidth: presented ? alignedWidth : 0
        blurHeight: presented ? alignedHeight : 0
        blurRadius: root.surfaceRadius
    }

    color: "transparent"

    readonly property real dpr: CompositorService.getScreenScale(screen)
    readonly property real screenWidth: screen.width
    readonly property real screenHeight: screen.height
    readonly property real shadowBuffer: Theme.elevationRenderPadding(Theme.elevationLevel2, Theme.elevationLightDirection, Theme.spacingXS, Theme.spacingS, Theme.spacingL)
    readonly property real alignedWidth: Theme.px(osdWidth, dpr)
    readonly property real alignedHeight: Theme.px(osdHeight, dpr)

    readonly property bool isVerticalLayout: osdPosition === SettingsData.Position.LeftCenter || osdPosition === SettingsData.Position.RightCenter

    readonly property var barEdgeOffsets: {
        const offsets = {
            "top": 0,
            "bottom": 0,
            "left": 0,
            "right": 0
        };
        const configs = SettingsData.barConfigs;
        if (!screen || !configs)
            return offsets;
        const defaultBar = SettingsData.getPrimaryBarConfig();
        for (var i = 0; i < configs.length; i++) {
            const bc = configs[i];
            if (!bc || !(bc.enabled ?? true) || !(bc.visible ?? true))
                continue;
            if (SettingsData.isIslandBarConfig(bc))
                continue;
            if (!SettingsData.barConfigCoversScreen(bc, screen))
                continue;
            const innerPadding = bc.innerPadding ?? (defaultBar?.innerPadding ?? SettingsData.barInnerPaddingDefault);
            const thickness = Theme.barThickness(innerPadding, dpr);
            const spacing = bc.spacing ?? (defaultBar?.spacing ?? 4);
            const bottomGap = bc.bottomGap ?? (defaultBar?.bottomGap ?? 0);
            const offset = thickness + spacing + bottomGap;
            switch (bc.position ?? SettingsData.Position.Top) {
            case SettingsData.Position.Top:
                offsets.top = Math.max(offsets.top, offset);
                break;
            case SettingsData.Position.Bottom:
                offsets.bottom = Math.max(offsets.bottom, offset);
                break;
            case SettingsData.Position.Left:
                offsets.left = Math.max(offsets.left, offset);
                break;
            case SettingsData.Position.Right:
                offsets.right = Math.max(offsets.right, offset);
                break;
            }
        }
        offsets.top = Math.max(offsets.top, SettingsData.dankIslandEdgeOffset(screen, "top"));
        offsets.bottom = Math.max(offsets.bottom, SettingsData.dankIslandEdgeOffset(screen, "bottom"));
        offsets.left = Math.max(offsets.left, SettingsData.dankIslandEdgeOffset(screen, "left"));
        offsets.right = Math.max(offsets.right, SettingsData.dankIslandEdgeOffset(screen, "right"));
        return offsets;
    }

    function dockOffsetForEdge(side) {
        return SettingsData.dockReservationForEdge(screen, side);
    }

    function edgeInset(side) {
        return Theme.spacingM + Math.max(barEdgeOffsets[side], dockOffsetForEdge(side));
    }

    function placeAlong(align, extent, size, startSide, endSide) {
        switch (align) {
        case -1:
            return Theme.snap(edgeInset(startSide), dpr);
        case 1:
            return Theme.snap(extent - size - edgeInset(endSide), dpr);
        default:
            return Theme.snap((extent - size) / 2, dpr);
        }
    }

    readonly property int alignX: {
        switch (osdPosition) {
        case SettingsData.Position.Left:
        case SettingsData.Position.Bottom:
        case SettingsData.Position.LeftCenter:
            return -1;
        case SettingsData.Position.Top:
        case SettingsData.Position.Right:
        case SettingsData.Position.RightCenter:
            return 1;
        default:
            return 0;
        }
    }

    readonly property int alignY: {
        switch (osdPosition) {
        case SettingsData.Position.Top:
        case SettingsData.Position.Left:
        case SettingsData.Position.TopCenter:
            return -1;
        case SettingsData.Position.Right:
        case SettingsData.Position.Bottom:
        case SettingsData.Position.BottomCenter:
            return 1;
        default:
            return 0;
        }
    }

    readonly property real alignedX: placeAlong(alignX, screenWidth, alignedWidth, "left", "right")
    readonly property real alignedY: placeAlong(alignY, screenHeight, alignedHeight, "top", "bottom")

    anchors {
        top: true
        left: true
    }

    readonly property real windowX: Math.max(0, Theme.snap(alignedX - shadowBuffer, dpr))
    readonly property real windowY: Math.max(0, Theme.snap(alignedY - shadowBuffer, dpr))

    WlrLayershell.margins {
        left: root.windowX
        top: root.windowY
    }

    implicitWidth: alignedWidth + (shadowBuffer * 2)
    implicitHeight: alignedHeight + (shadowBuffer * 2)

    readonly property var scaleSpringParams: Theme.springPreset("default", animationDuration)

    SpringMotion {
        id: osdScaleSpring
        reducedMotion: root.animationDuration <= 0
        positionEpsilon: 0.001
        velocityEpsilon: positionEpsilon * damping / Math.max(0.001, 2 * mass)
        stiffness: root.scaleSpringParams.stiffness
        damping: root.scaleSpringParams.damping
        value: root.presented ? 1 : Theme.popupEnterScale

        Component.onCompleted: snapTo(root.presented ? 1 : Theme.popupEnterScale)
    }

    onPresentedChanged: osdScaleSpring.retarget(root.presented ? 1 : Theme.popupEnterScale)

    Timer {
        id: hideTimer

        interval: autoHideInterval
        repeat: false
        onTriggered: {
            if (expanded)
                return;
            if (!enableMouseInteraction || !mouseArea.containsMouse) {
                hide();
            } else {
                hideTimer.restart();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: Math.max(animationDuration + 50, Math.round(osdScaleSpring.settleDurationMs) + 50)
        onTriggered: {
            if (!shouldBeVisible) {
                visible = false;
                osdHidden();
            }
        }
    }

    Item {
        id: osdContainer
        x: shadowBuffer
        y: shadowBuffer
        width: alignedWidth
        height: alignedHeight
        opacity: presented ? 1 : 0
        scale: osdScaleSpring.value

        property bool childHovered: false
        readonly property real popupSurfaceAlpha: Theme.popupTransparency

        ElevationShadow {
            id: bgShadowLayer
            anchors.fill: parent
            z: -2
            level: Theme.elevationLevel2
            fallbackOffset: Theme.spacingXS
            targetRadius: root.surfaceRadius
            targetColor: Theme.withAlpha(root.surfaceColor, osdContainer.popupSurfaceAlpha)
            borderColor: Theme.outlineVariant
            borderWidth: 0
            shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1"
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: enableMouseInteraction
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: true
            z: -1
            onContainsMouseChanged: updateHoverState()
        }

        onChildHoveredChanged: updateHoverState()

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: root.visible
            asynchronous: false
        }

        Behavior on opacity {
            NumberAnimation {
                duration: animationDuration
                easing.type: animationEasing
            }
        }
    }

    mask: Region {
        item: bgShadowLayer
    }

    LazyLoader {
        id: sheetLoader
        active: root.expanded

        DOSDSheet {
            host: root
            onPresented: root.visible = false
            onDismissed: root.finishSheet()
        }
    }
}
