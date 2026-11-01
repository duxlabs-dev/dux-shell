pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.DDash

Item {
    id: root

    property var paths: []
    property int currentIndex: 0
    property string currentWallpaper: ""
    property bool animate: true

    signal indexRequested(int index)
    signal activated(string path)

    readonly property real itemWidth: Math.round(width * DashMetrics.carouselItemRatio)
    readonly property real pitch: itemWidth + list.spacing

    function syncList() {
        if (list.currentIndex !== root.currentIndex)
            list.currentIndex = root.currentIndex;
    }

    function requestStep(step) {
        const next = Math.max(0, Math.min(paths.length - 1, currentIndex + step));
        if (next !== currentIndex)
            indexRequested(next);
    }

    onCurrentIndexChanged: syncList()
    // ListView resets currentIndex when its model is replaced.
    onPathsChanged: Qt.callLater(syncList)

    Loader {
        anchors.fill: parent
        active: root.paths.length > 0
        sourceComponent: ClippingRectangle {
            radius: DashMetrics.surfaceRadius
            color: "transparent"

            CachingImage {
                anchors.fill: parent
                imagePath: VideoWallpaperService.imageFor(root.paths[root.currentIndex] ?? "")
                maxCacheSize: DashMetrics.wallpaperThumbCache * 2
                animate: false
                opacity: DashMetrics.carouselBackdropAlpha
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Theme.hostSurface
                    }
                    GradientStop {
                        position: 0.5
                        color: "transparent"
                    }
                    GradientStop {
                        position: 1
                        color: Theme.hostSurface
                    }
                }
            }
        }
    }

    // Not a Dank* wrapper: the view only ever follows currentIndex, never the pointer.
    // Flickable snapping with the negative spacing drifts to the neighbour and desyncs from the host.
    ListView {
        id: list

        anchors.fill: parent
        orientation: ListView.Horizontal
        model: root.paths
        spacing: -root.itemWidth * DashMetrics.carouselOverlap
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - root.itemWidth) / 2
        preferredHighlightEnd: preferredHighlightBegin + root.itemWidth
        highlightMoveDuration: root.animate && DashMetrics.animationsEnabled ? DashMetrics.transitionDuration : 0
        interactive: false
        clip: true
        keyNavigationEnabled: false
        activeFocusOnTab: false
        cacheBuffer: root.pitch * 2

        Component.onCompleted: currentIndex = root.currentIndex

        delegate: Item {
            id: slide

            required property int index
            required property string modelData

            readonly property real offset: (x - list.contentX + width / 2 - list.width / 2) / Math.max(1, root.pitch)
            readonly property real distance: Math.min(1, Math.abs(offset))
            readonly property bool selected: modelData === root.currentWallpaper

            width: root.itemWidth
            height: list.height
            scale: 1 - (1 - DashMetrics.carouselSideScale) * distance
            opacity: 1 - (1 - DashMetrics.carouselSideAlpha) * distance
            z: -Math.abs(offset)
            transform: Rotation {
                origin.x: slide.width / 2
                origin.y: slide.height / 2
                axis {
                    x: 0
                    y: 1
                    z: 0
                }
                angle: -Math.max(-1, Math.min(1, slide.offset)) * DashMetrics.carouselAngle
            }

            Rectangle {
                id: frame

                anchors.centerIn: parent
                width: parent.width
                height: Math.min(parent.height - Theme.spacingS * 2, parent.width * DashMetrics.carouselAspect)
                radius: DashMetrics.surfaceRadius
                color: DashMetrics.chipColor

                ClippingRectangle {
                    anchors.fill: parent
                    radius: frame.radius
                    color: "transparent"

                    CachingImage {
                        anchors.fill: parent
                        imagePath: VideoWallpaperService.imageFor(slide.modelData)
                        maxCacheSize: DashMetrics.wallpaperThumbCache * 2
                        animate: false
                        opacity: status === Image.Ready ? 1 : 0

                        Behavior on opacity {
                            enabled: DashMetrics.animationsEnabled
                            NumberAnimation {
                                duration: DashMetrics.fadeDuration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: slide.selected ? Theme.outlineWidthFocused : 0
                    border.color: Theme.primary
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingS
                    width: Theme.iconSize
                    height: Theme.iconSize
                    radius: Theme.fullRadius(width, height)
                    color: Theme.primary
                    visible: slide.selected

                    DIcon {
                        anchors.centerIn: parent
                        name: "check"
                        size: Theme.iconSizeSmall
                        color: Theme.onPrimary
                    }
                }

                StateLayer {
                    cornerRadius: frame.radius
                    stateColor: Theme.primary
                    onClicked: {
                        root.indexRequested(slide.index);
                        root.activated(slide.modelData);
                    }
                }
            }
        }
    }

    DragHandler {
        property int startIndex: 0

        target: null
        yAxis.enabled: false
        onActiveChanged: startIndex = root.currentIndex
        onActiveTranslationChanged: {
            if (!active)
                return;
            const next = Math.max(0, Math.min(root.paths.length - 1, startIndex + Math.round(-activeTranslation.x / root.pitch)));
            if (next !== root.currentIndex)
                root.indexRequested(next);
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
            if (delta === 0)
                return;
            root.requestStep(-Math.sign(delta));
            wheel.accepted = true;
        }
    }
}
