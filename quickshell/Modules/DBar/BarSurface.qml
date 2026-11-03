import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Services
import qs.Modules.SurfaceWidgets
import "BarOutline.js" as BarOutline

Item {
    id: root

    required property var barWindow
    required property var axis
    required property var barConfig

    readonly property bool frameShapesBar: FrameTransitionState.effectiveFrameEnabled && barWindow.usesFrameBarChrome
    readonly property bool gothEnabled: (barConfig?.gothCornersEnabled ?? false) && !(barWindow.flattenForMaximizedWindow && barWindow.hasMaximizedToplevel)
    readonly property int barPos: barConfig?.position ?? 0
    readonly property bool isTop: barPos === SettingsData.Position.Top
    readonly property bool isBottom: barPos === SettingsData.Position.Bottom
    readonly property bool isLeft: barPos === SettingsData.Position.Left
    readonly property bool isRight: barPos === SettingsData.Position.Right
    readonly property bool farEdge: isBottom || isRight
    readonly property bool edgeAttached: (barConfig?.attachToScreenEdge ?? false) && !frameShapesBar
    readonly property bool alongWings: !(barWindow.spansEdge ?? true)
    readonly property real crossSize: axis.isVertical ? (parent?.width ?? 0) : (parent?.height ?? 0)
    readonly property real wingCrossCap: Math.max(0, crossSize - Math.min(rt, crossSize / 2))
    readonly property real wing: gothEnabled ? barWindow._wingR : 0
    readonly property real wingAlong: Math.max(0, motion.currentOffsetAlong)
    readonly property real wingCross: alongWings ? Math.min(wingAlong, wingCrossCap) : wingAlong
    readonly property real windowLength: axis.isVertical ? barWindow.height : barWindow.width
    readonly property string startSide: axis.isVertical ? "top" : "left"
    readonly property string endSide: axis.isVertical ? "bottom" : "right"
    readonly property var startNeighbour: alongWings ? null : ShellLayout.adjacentCover(barWindow.screen, startSide, barConfig, windowLength)
    readonly property var endNeighbour: alongWings ? null : ShellLayout.adjacentCover(barWindow.screen, endSide, barConfig, windowLength)
    readonly property real alongOrigin: axis.isVertical ? 0 : barWindow.renderedSpacing
    readonly property real startCover: coveredBy(startNeighbour)
    readonly property real endCover: coveredBy(endNeighbour)
    readonly property real alongWing: alongWings ? wing : 0
    readonly property real crossWing: alongWings ? 0 : wing
    readonly property real rt: {
        if (frameShapesBar)
            return SettingsData.frameRounding;
        if (barConfig?.squareCorners ?? false)
            return 0;
        if (barWindow.flattenForMaximizedWindow && barWindow.hasMaximizedToplevel)
            return 0;
        return Theme.windowRadius;
    }
    readonly property bool motionRunning: motion.running
    readonly property alias leadingWing: leadingWing
    readonly property alias trailingWing: trailingWing

    readonly property bool hasPerBarOverride: (barConfig?.shadowIntensity ?? 0) > 0
    readonly property var elevLevel: BarMetrics.elevationLevel
    readonly property bool shadowEnabled: Theme.elevationEnabled && (SettingsData.barElevationEnabled ?? true)
    readonly property string autoBarShadowDirection: isTop ? "top" : (isBottom ? "bottom" : (isLeft ? "left" : "right"))
    readonly property string globalShadowDirection: Theme.elevationLightDirection === "autoBar" ? autoBarShadowDirection : Theme.elevationLightDirection
    readonly property string perBarShadowDirectionMode: barConfig?.shadowDirectionMode ?? "inherit"
    readonly property string perBarManualShadowDirection: {
        switch (barConfig?.shadowDirection) {
        case "top":
        case "topLeft":
        case "topRight":
        case "bottom":
            return barConfig.shadowDirection;
        default:
            return "top";
        }
    }
    readonly property string effectiveShadowDirection: {
        if (!hasPerBarOverride)
            return globalShadowDirection;
        switch (perBarShadowDirectionMode) {
        case "autoBar":
            return autoBarShadowDirection;
        case "manual":
            return perBarManualShadowDirection === "autoBar" ? autoBarShadowDirection : perBarManualShadowDirection;
        default:
            return globalShadowDirection;
        }
    }
    readonly property real overrideBlurRatio: 0.2
    readonly property real overrideOffsetRatio: 0.5
    readonly property real overrideDefaultOpacityPercent: 60
    readonly property real overrideBlurPx: (barConfig?.shadowIntensity ?? 0) * overrideBlurRatio
    readonly property real overrideOpacity: (barConfig?.shadowOpacity ?? overrideDefaultOpacityPercent) / 100
    readonly property color overrideBaseColor: {
        switch (barConfig?.shadowColorMode ?? "default") {
        case "surface":
            return Theme.surface;
        case "primary":
            return Theme.primary;
        case "secondary":
            return Theme.secondary;
        case "custom":
            return barConfig?.shadowCustomColor ?? Theme.scrimColor;
        default:
            return Theme.scrimColor;
        }
    }
    readonly property real shadowBlurPx: hasPerBarOverride ? overrideBlurPx : (elevLevel.blurPx ?? 0)
    readonly property color shadowColor: hasPerBarOverride ? Theme.withAlpha(overrideBaseColor, overrideOpacity) : Theme.elevationShadowColor(elevLevel)
    readonly property real shadowOffsetMagnitude: hasPerBarOverride ? (overrideBlurPx * overrideOffsetRatio) : Theme.elevationOffsetMagnitude(elevLevel, Theme.spacingXS, effectiveShadowDirection)
    readonly property real shadowOffsetX: Theme.elevationOffsetXFor(hasPerBarOverride ? null : elevLevel, effectiveShadowDirection, shadowOffsetMagnitude)
    readonly property real shadowOffsetY: Theme.elevationOffsetYFor(hasPerBarOverride ? null : elevLevel, effectiveShadowDirection, shadowOffsetMagnitude)

    readonly property real attachedRadius: edgeAttached || frameShapesBar ? 0 : rt
    readonly property real wingRootRadius: gothEnabled ? 0 : rt
    readonly property real attachedCornerRadius: alongWings && gothEnabled ? 0 : attachedRadius
    readonly property real freeCornerRadius: alongWings ? rt : wingRootRadius
    readonly property var shapeTarget: ({
            width: Math.max(0, axis.isVertical ? width - crossWing : width - alongWing * 2),
            height: Math.max(0, axis.isVertical ? height - alongWing * 2 : height - crossWing),
            offsetAlong: wing,
            offsetCross: farEdge ? crossWing : 0,
            topLeftRadius: isTop || isLeft ? attachedCornerRadius : freeCornerRadius,
            topRightRadius: isTop || isRight ? attachedCornerRadius : freeCornerRadius,
            bottomLeftRadius: isBottom || isLeft ? attachedCornerRadius : freeCornerRadius,
            bottomRightRadius: isBottom || isRight ? attachedCornerRadius : freeCornerRadius
        })

    visible: !frameShapesBar
    anchors.fill: parent
    anchors.leftMargin: -(axis.isVertical ? (isRight ? crossWing : 0) : alongWing)
    anchors.rightMargin: -(axis.isVertical ? (isLeft ? crossWing : 0) : alongWing)
    anchors.topMargin: -(axis.isVertical ? alongWing : (isBottom ? crossWing : 0))
    anchors.bottomMargin: -(axis.isVertical ? alongWing : (isTop ? crossWing : 0))

    function coveredBy(neighbour) {
        if (!neighbour || neighbour.tucked)
            return 0;
        return Math.max(0, neighbour.reach - alongOrigin) + neighbour.wing;
    }

    function alongWingCorner(leading) {
        switch (barPos) {
        case SettingsData.Position.Bottom:
            return leading ? "topLeft" : "topRight";
        case SettingsData.Position.Left:
            return leading ? "topRight" : "bottomRight";
        case SettingsData.Position.Right:
            return leading ? "topLeft" : "bottomLeft";
        default:
            return leading ? "bottomLeft" : "bottomRight";
        }
    }

    function applyTarget() {
        if (width <= 0 || height <= 0 || !visible) {
            motion.snapTo(shapeTarget);
            return;
        }
        motion.setTarget(shapeTarget);
    }

    onShapeTargetChanged: applyTarget()
    Component.onCompleted: motion.snapTo(shapeTarget)

    VectorSpringMotion {
        id: motion

        readonly property var preset: Theme.springPreset("default", Theme.shortDuration)
        reducedMotion: Theme.springMotionDisabled || SettingsData.reduceMotion
        stiffness: preset.stiffness
        damping: preset.damping
        mass: preset.mass
        onRunningChanged: {
            if (!running)
                snapTo(root.shapeTarget);
        }
    }

    MouseArea {
        id: emptySurfaceClickArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        z: -999
        onClicked: mouse => {
            if (root.barWindow.handleEmptyBarClick(mouse.button, emptySurfaceClickArea, mouse.x, mouse.y))
                return;
            const activePopout = PopoutManager.getActivePopout(root.barWindow.screen);
            if (activePopout) {
                if (activePopout.dashVisible !== undefined) {
                    activePopout.dashVisible = false;
                } else if (activePopout.notificationHistoryVisible !== undefined) {
                    activePopout.notificationHistoryVisible = false;
                } else {
                    activePopout.close();
                }
            }
            TrayMenuManager.closeAllMenus();
        }
    }

    ElevationShadow {
        visible: root.shadowEnabled && root.width > 0 && root.height > 0
        x: body.x
        y: body.y
        width: body.width
        height: body.height
        shadowEnabled: root.shadowEnabled
        level: root.hasPerBarOverride ? null : root.elevLevel
        direction: root.effectiveShadowDirection
        fallbackOffset: Theme.spacingXS
        topLeftRadius: body.topLeftRadius
        topRightRadius: body.topRightRadius
        bottomLeftRadius: body.bottomLeftRadius
        bottomRightRadius: body.bottomRightRadius
        targetColor: "transparent"
        shadowBlurPx: root.shadowBlurPx
        shadowOffsetX: root.shadowOffsetX
        shadowOffsetY: root.shadowOffsetY
        shadowColor: root.shadowColor
    }

    MorphSurface {
        id: body
        motion: motion
        x: Math.max(0, root.axis.isVertical ? motion.currentOffsetCross : (root.alongWings ? motion.currentOffsetAlong : 0))
        y: Math.max(0, root.axis.isVertical ? (root.alongWings ? motion.currentOffsetAlong : 0) : motion.currentOffsetCross)
        color: root.barWindow._bgColor
    }

    GothCorner {
        id: leadingWing
        radius: root.wingAlong
        radiusX: root.axis.isVertical ? root.wingCross : radius
        radiusY: root.axis.isVertical ? radius : root.wingCross
        color: root.barWindow._bgColor
        visible: root.gothEnabled && radius > 0 && root.startCover <= 0
        x: root.alongWings ? (root.axis.isVertical && root.isRight ? root.width - width : 0) : (root.isLeft ? body.width : 0)
        y: root.alongWings ? (!root.axis.isVertical && root.isBottom ? root.height - height : 0) : (root.isTop ? body.height : 0)
        corner: root.alongWings ? root.alongWingCorner(true) : root.isTop ? "bottomRight" : root.isBottom ? "topRight" : root.isLeft ? "bottomRight" : "bottomLeft"
    }

    GothCorner {
        id: trailingWing
        radius: root.wingAlong
        radiusX: root.axis.isVertical ? root.wingCross : radius
        radiusY: root.axis.isVertical ? radius : root.wingCross
        color: root.barWindow._bgColor
        visible: root.gothEnabled && radius > 0 && root.endCover <= 0
        x: root.axis.isVertical ? (root.alongWings ? (root.isRight ? root.width - width : 0) : (root.isLeft ? body.width : 0)) : root.width - width
        y: root.axis.isVertical ? root.height - height : (root.alongWings ? (root.isBottom ? root.height - height : 0) : (root.isTop ? body.height : 0))
        corner: root.alongWings ? root.alongWingCorner(false) : root.isTop ? "bottomLeft" : root.isBottom ? "topLeft" : root.isLeft ? "topRight" : "topLeft"
    }

    Loader {
        id: border
        readonly property real thickness: Theme.snap(Math.max(Theme.outlineWidth, barConfig?.borderThickness ?? Theme.outlineWidth), CompositorService.getScreenScale(root.barWindow.screen))
        readonly property string colorKey: barConfig?.borderColor || "surfaceText"
        readonly property color baseColor: colorKey === "surfaceText" ? Theme.surfaceText : colorKey === "primary" ? Theme.primary : Theme.secondary
        readonly property bool showFullBorder: (barConfig?.spacing ?? 4) > 0
        readonly property string path: BarOutline.borderPath({
            position: root.axis.edge,
            width: root.width,
            height: root.height,
            body: {
                x: body.x,
                y: body.y,
                width: body.width,
                height: body.height
            },
            corners: {
                topLeft: body.topLeftRadius,
                topRight: body.topRightRadius,
                bottomLeft: body.bottomLeftRadius,
                bottomRight: body.bottomRightRadius
            },
            wing: root.gothEnabled ? leadingWing.radius : 0,
            wingCross: root.gothEnabled ? root.wingCross : 0,
            alongWings: root.alongWings,
            inset: thickness / 2,
            open: !showFullBorder,
            coverStart: root.startCover,
            coverStartWing: root.startNeighbour?.wing ?? 0,
            coverEnd: root.endCover,
            coverEndWing: root.endNeighbour?.wing ?? 0,
            seamStart: root.startNeighbour?.tucked ?? false,
            seamEnd: root.endNeighbour?.tucked ?? false
        })
        z: 100
        anchors.fill: parent
        active: barConfig?.borderEnabled ?? false
        sourceComponent: Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.withAlpha(border.baseColor, barConfig?.borderOpacity ?? 1.0)
                strokeWidth: border.thickness
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.FlatCap

                PathSvg {
                    path: border.path
                }
            }
        }
    }
}
