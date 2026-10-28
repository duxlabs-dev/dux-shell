pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Session

Item {
    id: root
    property string screenName: ""
    property bool asynchronous: false
    readonly property bool hasCustomWallpaper: SettingsData.lockScreenWallpaperPath !== ""

    function encodeFileUrl(path) {
        if (!path)
            return "";
        return "file://" + path.split('/').map(s => encodeURIComponent(s)).join('/');
    }
    readonly property bool ready: wallpaperBackground.active ? (wallpaperBackground.item?.ready ?? false) : (backdropLoader.item?.ready || backdropLoader.item?.liveReady || false)
    readonly property string renderKey: LockPlacementService.backgroundKey(screenName, width, height)

    Rectangle {
        anchors.fill: parent
        color: SettingsData.effectiveWallpaperBackgroundColor
    }

    Loader {
        id: backdropLoader
        anchors.fill: parent
        active: {
            if (root.hasCustomWallpaper)
                return false;
            var currentWallpaper = SessionData.getMonitorWallpaper(screenName);
            return !currentWallpaper || (currentWallpaper && currentWallpaper.startsWith("#"));
        }
        asynchronous: root.asynchronous

        sourceComponent: DBackdrop {
            screenName: root.screenName
            blur: Theme.lockScreenBlur
            blurMax: Theme.lockScreenBlurMax
        }
    }

    Loader {
        id: wallpaperBackground
        anchors.fill: parent

        readonly property string wallpaperSource: {
            if (root.hasCustomWallpaper)
                return root.encodeFileUrl(SettingsData.lockScreenWallpaperPath);
            var w = SessionData.getMonitorWallpaper(screenName);
            return (w && !w.startsWith("#")) ? encodeFileUrl(w) : "";
        }
        readonly property string fillModeName: {
            if (SettingsData.lockScreenWallpaperFillMode !== "")
                return SettingsData.lockScreenWallpaperFillMode;
            return root.hasCustomWallpaper ? "Fill" : SessionData.getMonitorWallpaperFillMode(root.screenName);
        }

        readonly property real screenScale: CompositorService.getScreenScale(Quickshell.screens.find(s => s.name === root.screenName) ?? null)
        readonly property size decodeSize: Qt.size(Math.round(width * screenScale), Math.round(height * screenScale))

        active: wallpaperSource !== "" && width > 0 && height > 0
        asynchronous: root.asynchronous

        sourceComponent: fillModeName === "Scrolling" ? scrollWallpaperComp : plainWallpaperComp

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: Theme.lockScreenBlur
            blurMax: Theme.lockScreenBlurMax
            blurMultiplier: 1
        }

        Behavior on opacity {
            NumberAnimation {
                duration: LockMetrics.effectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
            }
        }
    }

    Component {
        id: plainWallpaperComp
        Image {
            readonly property bool ready: status === Image.Ready || status === Image.Error
            source: wallpaperBackground.wallpaperSource
            sourceSize: wallpaperBackground.decodeSize
            fillMode: Theme.getFillMode(wallpaperBackground.fillModeName)
            smooth: true
            cache: true
            asynchronous: root.asynchronous
        }
    }

    Component {
        id: scrollWallpaperComp
        Item {
            readonly property bool ready: scrollSource.status === Image.Ready || scrollSource.status === Image.Error
            Image {
                id: scrollSource
                anchors.fill: parent
                visible: false
                source: wallpaperBackground.wallpaperSource
                sourceSize: wallpaperBackground.decodeSize
                asynchronous: root.asynchronous
                cache: true
            }

            ShaderEffectSource {
                id: scrollSrc
                sourceItem: scrollSource
                hideSource: true
                live: false
            }

            ShaderEffect {
                anchors.fill: parent

                readonly property var scrollPos: SessionData.getMonitorScrollPosition(screenName)

                property variant source1: scrollSrc
                property variant source2: scrollSrc
                property real progress: 0.0
                property real fillMode: Theme.getShaderFillMode(wallpaperBackground.fillModeName)
                property real scrollX: scrollPos.scrollX
                property real scrollY: scrollPos.scrollY
                property real imageWidth1: scrollSource.implicitWidth > 0 ? scrollSource.implicitWidth : 1
                property real imageHeight1: scrollSource.implicitHeight > 0 ? scrollSource.implicitHeight : 1
                property real imageWidth2: imageWidth1
                property real imageHeight2: imageHeight1
                property real screenWidth: width > 0 ? width : 1
                property real screenHeight: height > 0 ? height : 1
                property vector4d fillColor: Qt.vector4d(0, 0, 0, 1)

                fragmentShader: Qt.resolvedUrl("../../Shaders/qsb/wp_fade.frag.qsb")
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.screenOffColor
        opacity: Theme.lockScreenScrimAlpha
    }
}
