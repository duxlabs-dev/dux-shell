pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import "../Common/FluidGeometry.js" as FluidGeometry

PanelWindow {
    id: root

    required property var host

    property bool opened: false
    property bool closing: false
    property real shownSheetHeight: sheetHeight

    Behavior on shownSheetHeight {
        enabled: root.opened && !root.closing && !morph.running && root.animationDuration > 0 && !SettingsData.reduceMotion
        NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.variantPopoutResizeCurve
        }
    }

    readonly property real dpr: host.dpr
    readonly property real shadowBuffer: host.shadowBuffer
    readonly property int alignX: host.alignX
    readonly property int alignY: host.alignY
    readonly property rect compact: Qt.rect(host.alignedX, host.alignedY, host.alignedWidth, host.alignedHeight)
    readonly property real insetTop: host.edgeInset("top")
    readonly property real insetBottom: host.edgeInset("bottom")
    readonly property real insetLeft: host.edgeInset("left")
    readonly property real insetRight: host.edgeInset("right")

    readonly property real sheetWidth: Theme.px(Math.min(host.sheetWidth, host.screenWidth - insetLeft - insetRight), dpr)
    readonly property real maxSheetHeight: {
        switch (alignY) {
        case -1:
            return host.screenHeight - compact.y - insetBottom;
        case 1:
            return compact.y + compact.height - insetTop;
        default:
            return 2 * Math.min(compact.y + compact.height / 2 - insetTop, host.screenHeight - insetBottom - compact.y - compact.height / 2);
        }
    }
    readonly property real sheetHeight: Theme.px(Math.min(maxSheetHeight, sheetBody.item?.implicitHeight ?? compact.height), dpr)
    readonly property real sheetX: Math.max(insetLeft, Math.min(alongFrom(alignX, compact.x, compact.width, sheetWidth), host.screenWidth - insetRight - sheetWidth))
    readonly property real sheetY: alongFrom(alignY, compact.y, compact.height, shownSheetHeight)

    readonly property real bandHeight: Math.max(compact.height, maxSheetHeight)
    readonly property real bandX: Math.min(compact.x, sheetX)
    readonly property real bandY: alongFrom(alignY, compact.y, compact.height, bandHeight)
    readonly property real bandRight: Math.max(compact.x + compact.width, sheetX + sheetWidth)
    readonly property real originX: Math.max(0, Theme.snap(bandX - shadowBuffer, dpr))
    readonly property real originY: Math.max(0, Theme.snap(bandY - shadowBuffer, dpr))

    readonly property rect compactLocal: Qt.rect(compact.x - originX, compact.y - originY, compact.width, compact.height)
    readonly property rect sheetLocal: Qt.rect(Theme.snap(sheetX - originX, dpr), Theme.snap(sheetY - originY, dpr), sheetWidth, shownSheetHeight)

    readonly property int animationDuration: Theme.popoutAnimationDuration
    readonly property var springParams: Theme.springPreset("default", animationDuration)
    readonly property real morphTravelPx: Math.max(1, Math.abs(sheetLocal.x - compactLocal.x), Math.abs(sheetLocal.y - compactLocal.y), Math.abs(sheetLocal.width - compactLocal.width), Math.abs(sheetLocal.height - compactLocal.height))
    readonly property bool morphSettled: !morph.running || Math.abs(morph.value - morph.target) < Theme.morphLayerEpsilon
    // A fully transparent surface renders no frames, so the spring would never advance to settle.
    readonly property bool closeFinished: closing && (morphSettled || FluidGeometry.chromeOpacity(morph.value) <= 0)
    readonly property real morphProgress: morphSettled ? morph.target : morph.value
    readonly property real progress: Math.max(0, Math.min(1, morphProgress))
    readonly property rect body: FluidGeometry.limitOvershoot(morphRect(compactLocal, sheetLocal, morphProgress), sheetLocal, Theme.fluidOvershootLimit)
    readonly property real surfaceRadius: host.surfaceRadius + (Theme.windowRadius - host.surfaceRadius) * progress

    signal presented
    signal dismissed

    function alongFrom(align, start, size, target) {
        switch (align) {
        case -1:
            return start;
        case 1:
            return start + size - target;
        default:
            return start + (size - target) / 2;
        }
    }

    function alignIn(align, outer, inner) {
        switch (align) {
        case -1:
            return 0;
        case 1:
            return outer - inner;
        default:
            return (outer - inner) / 2;
        }
    }

    // FluidGeometry only bounds growth; a shrinking axis overshooting its target would crush the fixed-size content.
    function morphRect(from, to, value) {
        const grown = FluidGeometry.interpolate(from, to, value);
        const held = FluidGeometry.interpolate(from, to, Math.min(1, value));
        const holdX = to.width < from.width;
        const holdY = to.height < from.height;
        return Qt.rect(holdX ? held.x : grown.x, holdY ? held.y : grown.y, holdX ? held.width : grown.width, holdY ? held.height : grown.height);
    }

    function present() {
        opened = true;
        presented();
        morph.retarget(1);
        keyScope.forceActiveFocus();
    }

    function close() {
        if (closing)
            return;
        morph.retarget(0);
        closing = true;
    }

    onCloseFinishedChanged: {
        if (closeFinished)
            dismissed();
    }

    screen: host.screen
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: host.blurNamespace
    WlrLayershell.layer: host.WlrLayershell.layer
    WlrLayershell.keyboardFocus: KeyboardFocus.keyboardFocus(opened && !closing)

    anchors {
        top: true
        left: true
    }

    WlrLayershell.margins {
        left: root.originX
        top: root.originY
    }

    implicitWidth: Math.min(host.screenWidth - originX, Theme.snap(bandRight + shadowBuffer, dpr) - originX)
    implicitHeight: Math.min(host.screenHeight - originY, Theme.snap(bandY + bandHeight + shadowBuffer, dpr) - originY)

    SpringMotion {
        id: morph
        enabled: !Theme.springMotionDisabled
        reducedMotion: root.animationDuration <= 0 || SettingsData.reduceMotion
        positionEpsilon: Math.max(0.001, 0.25 / root.dpr / root.morphTravelPx)
        velocityEpsilon: positionEpsilon * damping / Math.max(0.001, 2 * mass)
        stiffness: root.springParams.stiffness
        damping: root.springParams.damping

        Component.onCompleted: snapTo(0)
    }

    WindowBlur {
        targetWindow: root
        surfaceColor: Theme.withAlpha(root.host.surfaceColor, Theme.popupTransparency)
        blurX: surface.x
        blurY: surface.y
        blurWidth: surface.opacity < 1 ? 0 : surface.width
        blurHeight: surface.opacity < 1 ? 0 : surface.height
        blurRadius: root.surfaceRadius
    }

    DFocusGrab {
        windows: [root, dismissWindow].concat(KeyboardFocus.barWindows)
        wanted: KeyboardFocus.wantsGrab(root.opened && !root.closing)
        onCleared: root.close()
    }

    Connections {
        target: surface.Window.window
        enabled: !root.opened

        function onFrameSwapped() {
            root.present();
        }
    }

    FocusScope {
        id: keyScope

        anchors.fill: parent
        Keys.onEscapePressed: root.close()

        MouseArea {
            anchors.fill: parent
            enabled: root.opened
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: root.close()
        }

        Item {
            id: surface

            x: root.body.x
            y: root.body.y
            width: root.body.width
            height: root.body.height
            opacity: root.closing ? FluidGeometry.chromeOpacity(morph.value) : 1

            ElevationShadow {
                anchors.fill: parent
                z: -2
                level: Theme.elevationLevel2
                fallbackOffset: Theme.spacingXS
                targetRadius: root.surfaceRadius
                targetColor: Theme.withAlpha(root.host.surfaceColor, Theme.popupTransparency)
                borderColor: Theme.outlineVariant
                borderWidth: 0
                shadowEnabled: Theme.elevationEnabled && SettingsData.popoutElevationEnabled && Quickshell.env("DMS_DISABLE_LAYER") !== "true" && Quickshell.env("DMS_DISABLE_LAYER") !== "1"
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: wheel => wheel.accepted = true
            }

            Item {
                anchors.fill: parent
                clip: true

                Loader {
                    x: root.alignIn(root.alignX, parent.width, width)
                    y: root.alignIn(root.alignY, parent.height, height)
                    width: root.compact.width
                    height: root.compact.height
                    sourceComponent: root.host.content
                    opacity: root.closing ? 0 : 1 - FluidGeometry.chromeOpacity(morph.value)
                    visible: opacity > 0
                    enabled: !root.opened
                }

                Loader {
                    id: sheetBody

                    x: root.alignIn(root.alignX, parent.width, width)
                    y: root.alignIn(root.alignY, parent.height, height)
                    width: root.sheetWidth
                    height: root.sheetHeight
                    sourceComponent: root.host.sheet
                    opacity: FluidGeometry.contentOpacity(root.body, root.sheetLocal)
                    visible: opacity > 0
                    focus: true
                }
            }
        }
    }

    Connections {
        target: sheetBody.item
        ignoreUnknownSignals: true

        function onCloseRequested() {
            root.close();
        }
    }

    PanelWindow {
        id: dismissWindow

        property bool mapped: false

        screen: root.screen
        visible: root.opened && !root.closing
        color: "transparent"
        exclusiveZone: -1
        // Input only: after the first transparent frame maps it, repainting would damage the whole screen.
        updatesEnabled: !mapped
        WlrLayershell.namespace: root.host.blurNamespace + ":dismiss"
        WlrLayershell.layer: root.WlrLayershell.layer
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            width: dismissWindow.width
            height: dismissWindow.height

            Region {
                x: root.originX
                y: root.originY
                width: root.width
                height: root.height
                intersection: Intersection.Subtract
            }
        }

        Connections {
            target: dismissSurface.Window.window
            enabled: !dismissWindow.mapped

            function onFrameSwapped() {
                dismissWindow.mapped = true;
            }
        }

        MouseArea {
            id: dismissSurface

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: root.close()
        }
    }
}
