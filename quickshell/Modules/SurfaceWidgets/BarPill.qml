import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DBar

Item {
    id: root

    property var axis: null
    property bool surfaceLive: true
    property string section: "center"
    property var popoutTarget: null
    property var parentScreen: null
    property real widgetThickness: 30
    property real barThickness: 48
    property real barSpacing: 4
    property var barConfig: null
    property bool widgetBackground: !(barConfig?.noBackground ?? false)
    property bool noBackground: !widgetBackground
    property var blurBarWindow: null
    property alias content: contentLoader.sourceComponent
    property bool isVerticalOrientation: axis?.isVertical ?? false
    property bool isFirst: false
    property bool isLast: false
    property real sectionSpacing: 0
    property bool enableBackgroundHover: true
    property bool enableCursor: true
    property bool isAutoHideBar: false
    property bool edgeHovered: false
    readonly property bool isMouseHovered: mouseArea.containsMouse || visualContent.hovered || edgeHovered
    property bool isLeftBarEdge: false
    property bool isRightBarEdge: false
    property bool isTopBarEdge: false
    property bool isBottomBarEdge: false
    property real crossEdgeExtension: 0
    property string segmentRole: "solo"
    property real splitOffset: 0
    property int pressedSegment: 0
    readonly property color defaultContentColor: Theme.widgetTextColor
    property color contentColor: defaultContentColor
    readonly property real dpr: parentScreen ? CompositorService.getScreenScale(parentScreen) : 1
    readonly property real horizontalPadding: Theme.snap((barConfig?.widgetPadding ?? SettingsData.barWidgetPaddingDefault) * (widgetThickness / 30), dpr)
    readonly property real contentThickness: widgetThickness - horizontalPadding * 2
    readonly property real visualWidth: Theme.snap(isVerticalOrientation ? widgetThickness : (contentLoader.item ? (contentLoader.item.implicitWidth + horizontalPadding * 2) : 0), dpr)
    readonly property real visualHeight: Theme.snap(isVerticalOrientation ? (contentLoader.item ? (contentLoader.item.implicitHeight + horizontalPadding * 2) : 0) : widgetThickness, dpr)
    readonly property alias visualContent: visualContent
    readonly property alias contentItem: contentLoader.item
    readonly property real gapExtension: sectionSpacing
    readonly property real leftMargin: !isVerticalOrientation ? (isFirst ? gapExtension : gapExtension / 2) : 0
    readonly property real rightMargin: !isVerticalOrientation ? (isLast ? gapExtension : gapExtension / 2) : 0
    readonly property real topMargin: isVerticalOrientation ? (isFirst ? gapExtension : gapExtension / 2) : (axis?.edge === "top" ? crossEdgeExtension : 0)
    readonly property real bottomMargin: isVerticalOrientation ? (isLast ? gapExtension : gapExtension / 2) : (axis?.edge === "bottom" ? crossEdgeExtension : 0)
    readonly property real minTooltipY: {
        if (!parentScreen || !isVerticalOrientation || isAutoHideBar)
            return 0;
        return parentScreen.y > 0 ? barThickness + barSpacing : 0;
    }
    readonly property bool barUsesOverlayLayer: LayerShell.envUsesOverlay("DMS_DANKBAR_LAYER", (barConfig?.useOverlayLayer ?? false) || CompositorService.framePeerSurfacesUseOverlayForScreen(parentScreen))

    readonly property bool mirrored: !isVerticalOrientation && LayoutMirroring.enabled
    readonly property bool leadingJoined: segmentRole === "middle" || segmentRole === "last"
    readonly property bool trailingJoined: segmentRole === "middle" || segmentRole === "first"
    readonly property bool startJoined: isVerticalOrientation || !mirrored ? leadingJoined : trailingJoined
    readonly property bool endJoined: isVerticalOrientation || !mirrored ? trailingJoined : leadingJoined
    readonly property real outerRadius: noBackground ? 0 : BarMetrics.pillRadius(widgetThickness, BarMetrics.widgetStyle(barConfig))
    readonly property real innerRadius: noBackground ? 0 : BarMetrics.segmentInnerRadius
    property var pressSource: null
    readonly property bool pressed: mouseArea.pressed || (pressSource?.pressed ?? false)
    property real pressProgress: pressed && enableBackgroundHover ? 1 : 0
    readonly property real blurRadius: segmentRole === "solo" ? outerRadius : innerRadius
    readonly property bool radiusMotion: !SettingsData.reduceMotion && !Theme.springMotionDisabled
    readonly property real outlineThickness: (barConfig?.widgetOutlineEnabled ?? false) ? (barConfig?.widgetOutlineThickness ?? Theme.outlineWidth) : 0
    readonly property color outlineColor: {
        if (outlineThickness <= 0)
            return "transparent";
        const opacity = barConfig?.widgetOutlineOpacity ?? 1.0;
        switch (barConfig?.widgetOutlineColor || "primary") {
        case "surfaceText":
            return Theme.withAlpha(Theme.surfaceText, opacity);
        case "secondary":
            return Theme.withAlpha(Theme.secondary, opacity);
        default:
            return Theme.withAlpha(Theme.primary, opacity);
        }
    }
    readonly property color defaultFillColor: {
        if (noBackground)
            return "transparent";
        return BarMetrics.widgetFill(barConfig);
    }
    property color fillColor: defaultFillColor
    readonly property bool shadowEnabled: barConfig?.island === true && !SettingsData.islandSetting(barConfig, "islandSatelliteBackground") && !noBackground && fillColor.a > 0 && Theme.elevationEnabled && SettingsData.barElevationEnabled
    readonly property string autoBarShadowDirection: axis?.edge ?? "top"
    readonly property string effectiveShadowDirection: Theme.elevationLightDirection === "autoBar" ? autoBarShadowDirection : Theme.elevationLightDirection

    property real topLeftRadius: cornerRadius(startJoined)
    property real topRightRadius: cornerRadius(isVerticalOrientation ? startJoined : endJoined)
    property real bottomLeftRadius: cornerRadius(isVerticalOrientation ? endJoined : startJoined)
    property real bottomRightRadius: cornerRadius(endJoined)

    Behavior on pressProgress {
        enabled: root.radiusMotion
        NumberAnimation {
            duration: Theme.expressiveDurations.expressiveFastSpatial
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
        }
    }

    signal clicked
    signal pressedAt(real rootX, real rootY)
    signal rightClicked(real rootX, real rootY)
    signal wheel(var wheelEvent)

    function cornerRadius(joined, progress = pressProgress) {
        if (noBackground)
            return 0;
        return BarMetrics.cornerRadius(widgetThickness, BarMetrics.widgetStyle(barConfig), joined, progress);
    }

    function segmentIndexAt(sourceItem, x, y) {
        if (!visualContent.split)
            return 0;
        const pos = sourceItem.mapToItem(visualContent, x, y);
        return (isVerticalOrientation ? pos.y : pos.x) >= splitOffset ? 1 : 0;
    }

    function triggerRipple(sourceItem, mouseX, mouseY) {
        if (sourceItem !== root && "pressed" in sourceItem)
            pressSource = sourceItem;
        pressedSegment = segmentIndexAt(sourceItem, mouseX, mouseY);
        const segment = segmentRepeater.itemAt(pressedSegment);
        if (!segment)
            return;
        const pos = sourceItem.mapToItem(segment, mouseX, mouseY);
        segment.ripple.trigger(pos.x, pos.y);
    }

    function handlePress(mouse, source) {
        if (source !== root && "pressed" in source)
            pressSource = source;
        pressedSegment = segmentIndexAt(source, mouse.x, mouse.y);
        if (mouse.button === Qt.RightButton) {
            const rPos = source.mapToItem(root, mouse.x, mouse.y);
            root.rightClicked(rPos.x, rPos.y);
            return;
        }
        if (enableBackgroundHover)
            triggerRipple(source, mouse.x, mouse.y);
        const rootPos = source.mapToItem(root, mouse.x, mouse.y);
        root.pressedAt(rootPos.x, rootPos.y);
        if (popoutTarget) {
            if (popoutTarget.setBarContext) {
                const pos = root.axis?.edge === "left" ? 2 : (root.axis?.edge === "right" ? 3 : (root.axis?.edge === "top" ? 0 : 1));
                const bottomGap = root.barConfig ? (root.barConfig.bottomGap !== undefined ? root.barConfig.bottomGap : 0) : 0;
                popoutTarget.setBarContext(pos, bottomGap);
            }

            root.positionPopout(popoutTarget);
        }
        root.clicked();
    }

    function positionPopout(popout, visual, width) {
        const context = BarWidgetService.registrationForItem(root)?.context?.surface;
        if (context)
            return context.positionPopout(popout, root, root.section, visual, width);
        if (!popout?.setTriggerPosition)
            return false;
        const globalPos = (visual || root.visualContent).mapToItem(null, 0, 0);
        const currentScreen = parentScreen || Screen;
        const barPosition = root.axis?.edge === "left" ? 2 : (root.axis?.edge === "right" ? 3 : (root.axis?.edge === "top" ? 0 : 1));
        const pos = SettingsData.getPopupTriggerPosition(globalPos, currentScreen, barThickness, width ?? root.visualWidth, root.barSpacing, barPosition, root.barConfig);
        popout.setTriggerPosition(pos.x, pos.y, pos.width, section, currentScreen, barPosition, barThickness, root.barSpacing, root.barConfig, root);
        return true;
    }

    function contextMenuAnchor() {
        const registration = BarWidgetService.registrationForItem(root);
        if (registration?.context?.owner?.overflowAnchor) {
            const anchor = registration.context.surface.popupAnchor(root);
            if (anchor) {
                const vertical = axis?.isVertical ?? false;
                return {
                    x: anchor.trigger.x + (vertical ? 0 : anchor.trigger.width / 2),
                    y: anchor.trigger.y + (vertical ? anchor.trigger.width / 2 : 0),
                    isVertical: vertical,
                    edge: axis?.edge ?? "top",
                    screen: anchor.screen
                };
            }
        }
        const screen = parentScreen || Screen;
        const vertical = axis?.isVertical ?? false;
        const edge = axis?.edge ?? "top";
        const gap = Math.max(Theme.spacingXS, barSpacing ?? Theme.spacingXS);
        const edgeInset = barThickness + barSpacing + gap;
        const globalPos = mapToGlobal(width / 2, height / 2);
        const relativeX = globalPos.x - (screen.x || 0);
        const relativeY = globalPos.y - (screen.y || 0);
        if (vertical)
            return {
                x: edge === "left" ? edgeInset : screen.width - edgeInset,
                y: relativeY + minTooltipY,
                isVertical: true,
                edge: edge,
                screen: screen
            };
        return {
            x: relativeX,
            y: edge === "bottom" ? screen.height - edgeInset : edgeInset,
            isVertical: false,
            edge: edge,
            screen: screen
        };
    }

    width: isVerticalOrientation ? barThickness : visualWidth
    height: isVerticalOrientation ? visualHeight : barThickness
    enabled: width > 0 && height > 0

    Item {
        id: visualContent
        width: root.visualWidth
        height: root.visualHeight
        anchors.centerIn: parent

        readonly property real blurRadius: root.blurRadius
        readonly property bool split: root.splitOffset > 0
        readonly property real splitGap: BarMetrics.segmentGap
        property bool hovered: false

        Repeater {
            id: segmentRepeater
            model: visualContent.split ? 2 : 1

            Item {
                id: segment
                required property int index
                readonly property alias ripple: ripple
                readonly property bool leading: index === 0
                readonly property bool joinedStart: visualContent.split && !leading
                readonly property bool joinedEnd: visualContent.split && leading
                readonly property real along: visualContent.split ? (leading ? 0 : root.splitOffset + visualContent.splitGap / 2) : 0
                readonly property real length: {
                    const full = root.isVerticalOrientation ? visualContent.height : visualContent.width;
                    if (!visualContent.split)
                        return full;
                    return leading ? root.splitOffset - visualContent.splitGap / 2 : full - root.splitOffset - visualContent.splitGap / 2;
                }
                readonly property real pressProgress: !visualContent.split || index === root.pressedSegment ? root.pressProgress : 0
                readonly property real startRadius: root.cornerRadius(joinedStart || root.startJoined, pressProgress)
                readonly property real endRadius: root.cornerRadius(joinedEnd || root.endJoined, pressProgress)

                x: root.isVerticalOrientation ? 0 : along
                y: root.isVerticalOrientation ? along : 0
                width: root.isVerticalOrientation ? visualContent.width : Math.max(0, length)
                height: root.isVerticalOrientation ? Math.max(0, length) : visualContent.height

                Loader {
                    anchors.fill: parent
                    active: root.shadowEnabled && width > 0 && height > 0
                    sourceComponent: ElevationShadow {
                        level: BarMetrics.elevationLevel
                        direction: root.effectiveShadowDirection
                        fallbackOffset: Theme.spacingXS
                        targetColor: "transparent"
                        topLeftRadius: fill.topLeftRadius
                        topRightRadius: fill.topRightRadius
                        bottomLeftRadius: fill.bottomLeftRadius
                        bottomRightRadius: fill.bottomRightRadius
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -root.outlineThickness
                    topLeftRadius: fill.topLeftRadius + root.outlineThickness
                    topRightRadius: fill.topRightRadius + root.outlineThickness
                    bottomLeftRadius: fill.bottomLeftRadius + root.outlineThickness
                    bottomRightRadius: fill.bottomRightRadius + root.outlineThickness
                    color: "transparent"
                    border.width: root.outlineThickness
                    border.color: root.outlineColor
                    visible: root.outlineThickness > 0 && !root.noBackground
                }

                Rectangle {
                    id: fill
                    anchors.fill: parent
                    topLeftRadius: segment.startRadius
                    topRightRadius: root.isVerticalOrientation ? segment.startRadius : segment.endRadius
                    bottomLeftRadius: root.isVerticalOrientation ? segment.endRadius : segment.startRadius
                    bottomRightRadius: segment.endRadius
                    color: root.fillColor
                }

                StateLayer {
                    id: stateLayer
                    stateColor: Theme.onSurface
                    topLeftRadius: fill.topLeftRadius
                    topRightRadius: fill.topRightRadius
                    bottomLeftRadius: fill.bottomLeftRadius
                    bottomRightRadius: fill.bottomRightRadius
                    enableRipple: false
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    disabled: !root.enableBackgroundHover || root.noBackground
                    cursorShape: root.enableCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onContainsMouseChanged: visualContent.hovered = containsMouse
                    onPressed: mouse => root.handlePress(mouse, stateLayer)
                }

                DRipple {
                    id: ripple
                    rippleColor: Theme.surfaceText
                    topLeftRadius: fill.topLeftRadius
                    topRightRadius: fill.topRightRadius
                    bottomLeftRadius: fill.bottomLeftRadius
                    bottomRightRadius: fill.bottomRightRadius
                }
            }
        }

        FocusRing {
            topLeftRadius: root.topLeftRadius + Theme.focusRingOffset
            topRightRadius: root.topRightRadius + Theme.focusRingOffset
            bottomLeftRadius: root.bottomLeftRadius + Theme.focusRingOffset
            bottomRightRadius: root.bottomRightRadius + Theme.focusRingOffset
            visible: root.activeFocus
        }

        Loader {
            id: contentLoader
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    MouseArea {
        id: mouseArea
        z: -1
        x: -root.leftMargin
        y: -root.topMargin
        width: root.width + root.leftMargin + root.rightMargin
        height: root.height + root.topMargin + root.bottomMargin
        hoverEnabled: true
        cursorShape: root.enableCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => root.handlePress(mouse, mouseArea)
        onWheel: wheelEvent => {
            wheelEvent.accepted = false;
            root.wheel(wheelEvent);
        }
    }

    property var _blurRegisteredWindow: null
    readonly property var _blurTargetWindow: BlurService.enabled && !!blurBarWindow && !!blurBarWindow.registerBlurWidget && !root.noBackground && root.visible && root.width > 0 && root.height > 0 ? blurBarWindow : null

    on_BlurTargetWindowChanged: _updateBlurRegistration()

    function _updateBlurRegistration() {
        if (_blurRegisteredWindow === _blurTargetWindow)
            return;
        _blurRegisteredWindow?.unregisterBlurWidget?.(visualContent);
        _blurRegisteredWindow = _blurTargetWindow;
        _blurRegisteredWindow?.registerBlurWidget(visualContent);
    }

    Component.onCompleted: _updateBlurRegistration()
    Component.onDestruction: _blurRegisteredWindow?.unregisterBlurWidget?.(visualContent)
}
