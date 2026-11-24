import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Common
import qs.Services

Item {
    id: root
    property var toplevel
    property var scale
    required property bool overviewOpen
    property var availableWorkspaceWidth
    property var availableWorkspaceHeight
    property bool restrictToWorkspace: true
    property real monitorDpr: 1
    property real contentOriginX: 0
    property real contentOriginY: 0
    property real contentScale: 0

    readonly property var geometrySpringParams: Theme.springPreset("defaultSpatial")

    SpringMotion {
        id: xSpring
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: root.geometrySpringParams.stiffness
        damping: root.geometrySpringParams.damping
        value: root.initX
    }

    SpringMotion {
        id: ySpring
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: root.geometrySpringParams.stiffness
        damping: root.geometrySpringParams.damping
        value: root.initY
    }

    SpringMotion {
        id: widthSpring
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: root.geometrySpringParams.stiffness
        damping: root.geometrySpringParams.damping
        value: root.targetWindowWidth
    }

    SpringMotion {
        id: heightSpring
        positionEpsilon: 0.05
        velocityEpsilon: 0.05
        stiffness: root.geometrySpringParams.stiffness
        damping: root.geometrySpringParams.damping
        value: root.targetWindowHeight
    }

    readonly property var windowData: toplevel?.lastIpcObject || null
    readonly property var monitorObj: toplevel?.monitor
    readonly property var monitorData: monitorObj?.lastIpcObject || null
    readonly property real effectiveScale: root.scale / root.monitorDpr
    readonly property real overviewScale: root.contentScale > 0 ? root.contentScale : root.effectiveScale

    readonly property real rawX: ((windowData?.at?.[0] ?? 0) - contentOriginX) * overviewScale
    readonly property real rawY: ((windowData?.at?.[1] ?? 0) - contentOriginY) * overviewScale
    readonly property real rawWidth: (windowData?.size?.[0] ?? 100) * overviewScale
    readonly property real rawHeight: (windowData?.size?.[1] ?? 100) * overviewScale
    readonly property real clipLeft: Math.max(0, rawX)
    readonly property real clipTop: Math.max(0, rawY)
    readonly property real clipRight: Math.min(availableWorkspaceWidth, rawX + rawWidth)
    readonly property real clipBottom: Math.min(availableWorkspaceHeight, rawY + rawHeight)
    readonly property bool intersectsViewport: clipRight > clipLeft && clipBottom > clipTop

    property real initX: clipLeft + xOffset
    property real initY: clipTop + yOffset
    property real xOffset: 0
    property real yOffset: 0
    property int widgetMonitorId: 0

    property var targetWindowWidth: Math.max(clipRight - clipLeft, 0)
    property var targetWindowHeight: Math.max(clipBottom - clipTop, 0)
    property bool hovered: false
    property bool pressed: false

    property var iconToWindowRatio: 0.25
    property var iconToWindowRatioCompact: 0.45
    property var entry: windowData?.class ? DesktopEntries.heuristicLookup(Paths.moddedAppId(windowData.class)) : null
    property var iconPath: AppSearchService.windowIcon(windowData?.class, windowData) || Paths.getAppIcon(windowData?.class ?? "", entry) || Quickshell.iconPath("application-x-executable", "image-missing")
    property bool compactMode: Theme.fontSizeSmall * 4 > targetWindowHeight || Theme.fontSizeSmall * 4 > targetWindowWidth

    x: xSpring.value
    y: ySpring.value
    width: widthSpring.value
    height: heightSpring.value
    visible: intersectsViewport
    opacity: (monitorObj?.id ?? -1) == widgetMonitorId ? 1 : 0.4

    onInitXChanged: xSpring.retarget(initX)
    onInitYChanged: ySpring.retarget(initY)
    onTargetWindowWidthChanged: widthSpring.retarget(targetWindowWidth)
    onTargetWindowHeightChanged: heightSpring.retarget(targetWindowHeight)

    ClippingRectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: "transparent"

        ScreencopyView {
            id: windowPreview
            anchors.fill: parent
            captureSource: root.overviewOpen ? root.toplevel?.wayland : null
            live: true

            Rectangle {
                anchors.fill: parent
                radius: Theme.cornerRadius
                color: pressed ? Theme.withAlpha(Theme.surfaceText, Theme.stateLayerDrag) : hovered ? Theme.surfaceHover : Theme.surfaceLight
                border.color: Theme.withAlpha(Theme.outline, 0.3)
                border.width: 1
            }

            ColumnLayout {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.fontSizeSmall * 0.5

                Image {
                    id: windowIcon
                    property var iconSize: {
                        return Math.min(targetWindowWidth, targetWindowHeight) * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio) / (root.monitorData?.scale ?? 1);
                    }

                    SpringMotion {
                        id: iconWidthSpring
                        positionEpsilon: 0.05
                        velocityEpsilon: 0.05
                        stiffness: root.geometrySpringParams.stiffness
                        damping: root.geometrySpringParams.damping
                        value: windowIcon.iconSize
                    }

                    SpringMotion {
                        id: iconHeightSpring
                        positionEpsilon: 0.05
                        velocityEpsilon: 0.05
                        stiffness: root.geometrySpringParams.stiffness
                        damping: root.geometrySpringParams.damping
                        value: windowIcon.iconSize
                    }

                    onIconSizeChanged: {
                        iconWidthSpring.retarget(iconSize);
                        iconHeightSpring.retarget(iconSize);
                    }

                    Layout.alignment: Qt.AlignHCenter
                    source: root.iconPath
                    width: iconWidthSpring.value
                    height: iconHeightSpring.value
                    sourceSize: Qt.size(iconSize, iconSize)
                }
            }
        }
    }
}
