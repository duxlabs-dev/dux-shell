import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services

Item {
    id: root

    readonly property var log: Log.scoped("BlurredWallpaperLive")

    required property string wallpaperSource
    required property string initialSource
    required property string screenName
    required property size blurTextureSize

    readonly property bool currentFailed: currentWallpaper.status === Image.Error
    readonly property bool displayableNow: currentWallpaper.status === Image.Ready || currentWallpaper.status === Image.Error
    readonly property bool stable: isInitialized && !effectActive && !transitionAnimation.running && !transitionDelayTimer.running && currentWallpaper.status === Image.Ready && currentWallpaper.source.toString() === wallpaperSource && !nextWallpaper.source.toString()

    signal becameDisplayable

    property bool isInitialized: false
    property real transitionProgress: 0
    readonly property bool transitioning: transitionAnimation.running
    property bool effectActive: false
    property bool useNextForEffect: false

    Component.onCompleted: {
        if (initialSource && initialSource !== wallpaperSource && !(CompositorService.isNiri && SessionData.isSwitchingMode) && !ConfigProfileService.switching) {
            currentWallpaper.source = initialSource;
            isInitialized = true;
            changeWallpaper(wallpaperSource);
            return;
        }
        currentWallpaper.source = wallpaperSource;
        isInitialized = true;
    }

    onWallpaperSourceChanged: {
        if (!isInitialized)
            return;
        if (!wallpaperSource) {
            setWallpaperImmediate("");
            return;
        }
        if (!currentWallpaper.source.toString()) {
            setWallpaperImmediate(wallpaperSource);
            return;
        }
        if ((CompositorService.isNiri && SessionData.isSwitchingMode) || ConfigProfileService.switching) {
            setWallpaperImmediate(wallpaperSource);
            return;
        }
        changeWallpaper(wallpaperSource);
    }

    function handleTransitionLoadError(failedSource) {
        log.warn("failed to load candidate wallpaper for", screenName + ":", failedSource);
        transitionDelayTimer.stop();
        transitionAnimation.stop();
        useNextForEffect = false;
        effectActive = false;
        transitionProgress = 0.0;
        nextWallpaper.source = "";
    }

    function setWallpaperImmediate(newSource) {
        transitionDelayTimer.stop();
        transitionAnimation.stop();
        transitionProgress = 0.0;
        effectActive = false;
        currentWallpaper.source = newSource;
        nextWallpaper.source = "";
    }

    function startTransition() {
        useNextForEffect = true;
        effectActive = true;
        if (srcNext.scheduleUpdate)
            srcNext.scheduleUpdate();
        transitionDelayTimer.start();
    }

    function changeWallpaper(newPath) {
        if (!newPath)
            return;
        if (transitioning) {
            transitionAnimation.stop();
            transitionProgress = 0;
            effectActive = false;
            currentWallpaper.source = nextWallpaper.source;
            nextWallpaper.source = "";
        }
        if (newPath === currentWallpaper.source.toString()) {
            if (nextWallpaper.source.toString() || effectActive)
                setWallpaperImmediate(newPath);
            return;
        }
        if (!currentWallpaper.source.toString()) {
            setWallpaperImmediate(newPath);
            return;
        }

        nextWallpaper.source = newPath;

        if (nextWallpaper.status === Image.Ready)
            startTransition();
    }

    Timer {
        id: transitionDelayTimer
        interval: Timing.frame
        repeat: false
        onTriggered: transitionAnimation.start()
    }

    Image {
        id: currentWallpaper
        anchors.fill: parent
        visible: false
        opacity: 1
        asynchronous: true
        retainWhileLoading: true
        smooth: true
        cache: true
        sourceSize: root.blurTextureSize
        fillMode: Theme.getFillMode(SessionData.getMonitorWallpaperFillMode(root.screenName))

        onStatusChanged: {
            if (status === Image.Error) {
                root.log.warn("failed to load active wallpaper for", root.screenName + ":", source);
            }
            if (status === Image.Ready || status === Image.Error) {
                root.becameDisplayable();
            }
        }
    }

    Image {
        id: nextWallpaper
        anchors.fill: parent
        visible: false
        opacity: 0
        asynchronous: true
        retainWhileLoading: true
        smooth: true
        cache: true
        sourceSize: root.blurTextureSize
        fillMode: Theme.getFillMode(SessionData.getMonitorWallpaperFillMode(root.screenName))

        onStatusChanged: {
            if (status === Image.Error) {
                root.handleTransitionLoadError(source);
                return;
            }
            if (status !== Image.Ready)
                return;
            if (!root.transitioning) {
                root.startTransition();
            }
        }
    }

    ShaderEffectSource {
        id: srcNext
        sourceItem: root.effectActive ? nextWallpaper : null
        hideSource: root.effectActive
        live: root.effectActive
        mipmap: false
        recursive: false
        textureSize: root.blurTextureSize
    }

    Rectangle {
        id: dummyRect
        width: 1
        height: 1
        visible: false
        color: "transparent"
    }

    ShaderEffectSource {
        id: srcDummy
        sourceItem: dummyRect
        hideSource: true
        live: false
        mipmap: false
        recursive: false
    }

    Item {
        id: blurredLayer
        anchors.fill: parent

        MultiEffect {
            anchors.fill: parent
            source: currentWallpaper
            visible: currentWallpaper.source !== ""
            blurEnabled: true
            blur: 0.8
            blurMax: 75
            opacity: 1 - root.transitionProgress
            autoPaddingEnabled: false
        }

        MultiEffect {
            anchors.fill: parent
            source: root.useNextForEffect ? srcNext : srcDummy
            visible: nextWallpaper.source !== "" && root.useNextForEffect
            blurEnabled: true
            blur: 0.8
            blurMax: 75
            opacity: root.transitionProgress
            autoPaddingEnabled: false
        }
    }

    NumberAnimation {
        id: transitionAnimation
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: SessionData.wallpaperTransitionDuration
        easing.type: Easing.InOutCubic
        onFinished: {
            if (nextWallpaper.source && nextWallpaper.status === Image.Ready)
                currentWallpaper.source = nextWallpaper.source;
            root.useNextForEffect = false;
            nextWallpaper.source = "";
            root.transitionProgress = 0.0;
            root.effectActive = false;
        }
    }
}
