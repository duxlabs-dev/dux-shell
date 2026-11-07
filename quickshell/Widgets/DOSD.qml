import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

Item {
    id: root

    property alias content: contentLoader.sourceComponent
    property alias contentLoader: contentLoader
    property var modelData
    readonly property var screen: modelData
    property string osdKind: ""
    readonly property int osdPosition: SettingsData.osdPositionFor(osdKind)
    property bool shouldBeVisible: false
    readonly property bool presented: shouldBeVisible && frameGate.ready
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

    property string _attachedScreenName: ""
    readonly property var surface: IdleSurfaces.surfaceFor("osd", _attachedScreenName)
    readonly property bool attached: _attachedScreenName !== ""
    readonly property Item maskItem: sheetLoader.item ?? bgShadowLayer
    readonly property int surfaceKeyboardFocus: sheetLoader.item?.keyboardFocus ?? WlrKeyboardFocus.None
    readonly property var blurRegion: sheetLoader.item?.blurRegion ?? blur.effectiveRegion

    signal osdShown
    signal osdHidden

    function show() {
        if (SessionData.suppressOSD || expanded)
            return;
        if (shouldBeVisible) {
            hideTimer.restart();
            return;
        }
        _attach();
        if (!attached)
            return;
        OSDManager.showOSD(root);
        closeTimer.stop();
        shouldBeVisible = true;
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
        _detach();
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

    function _attach() {
        const name = screen?.name ?? "";
        if (!name)
            return;
        const target = IdleSurfaces.surfaceFor("osd", name);
        if (!target)
            return;
        surfaceRoot.parent = null;
        surfaceRoot.parent = target.hostItem;
        _attachedScreenName = name;
    }

    function _detach() {
        surfaceRoot.parent = root;
        _attachedScreenName = "";
    }

    onAttachedChanged: {
        if (attached)
            return;
        surfaceRoot.parent = root;
        if (!shouldBeVisible && !expanded)
            return;
        finishSheet();
    }

    readonly property var quickshellScreens: Quickshell.screens

    onQuickshellScreensChanged: {
        if (!attached && !shouldBeVisible)
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
        finishSheet();
    }

    WindowBlur {
        id: blur
        targetWindow: root.surface
        applyToWindow: false
        surfaceColor: Theme.withAlpha(root.surfaceColor, osdContainer.popupSurfaceAlpha)
        blurX: root.frameX + root.shadowBuffer
        blurY: root.frameY + root.shadowBuffer
        blurWidth: root.presented ? root.alignedWidth : 0
        blurHeight: root.presented ? root.alignedHeight : 0
        blurRadius: root.surfaceRadius
    }

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

    readonly property real frameX: Math.max(0, Theme.snap(alignedX - shadowBuffer, dpr))
    readonly property real frameY: Math.max(0, Theme.snap(alignedY - shadowBuffer, dpr))

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

        interval: root.autoHideInterval
        repeat: false
        onTriggered: {
            if (root.expanded)
                return;
            if (!root.enableMouseInteraction || !mouseArea.containsMouse) {
                root.hide();
            } else {
                hideTimer.restart();
            }
        }
    }

    Timer {
        id: closeTimer
        interval: Math.max(root.animationDuration + 50, Math.round(osdScaleSpring.settleDurationMs) + 50)
        onTriggered: {
            if (root.shouldBeVisible)
                return;
            root._detach();
            root.osdHidden();
        }
    }

    Item {
        id: surfaceRoot

        readonly property var host: root
        anchors.fill: parent

        SurfaceFrameGate {
            id: frameGate
            surfaceVisible: root.attached
        }

        Item {
            id: osdContainer
            x: root.frameX + root.shadowBuffer
            y: root.frameY + root.shadowBuffer
            width: root.alignedWidth
            height: root.alignedHeight
            visible: !(sheetLoader.item?.opened ?? false)
            opacity: root.presented ? 1 : 0
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
                hoverEnabled: root.enableMouseInteraction
                acceptedButtons: Qt.NoButton
                propagateComposedEvents: true
                z: -1
                onContainsMouseChanged: root.updateHoverState()
            }

            onChildHoveredChanged: root.updateHoverState()

            Loader {
                id: contentLoader
                anchors.fill: parent
                active: root.attached
                asynchronous: false
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.animationDuration
                    easing.type: root.animationEasing
                }
            }
        }

        Loader {
            id: sheetLoader
            anchors.fill: parent
            active: root.expanded

            sourceComponent: DOSDSheet {
                host: root
                onDismissed: root.finishSheet()
            }
        }
    }
}
