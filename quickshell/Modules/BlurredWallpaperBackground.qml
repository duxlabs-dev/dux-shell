import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Services

Variants {
    readonly property var log: Log.scoped("BlurredWallpaperBackground")
    model: SettingsData.getFilteredScreens("wallpaper")

    PanelWindow {
        id: blurWallpaperWindow

        required property var modelData

        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "dms:blurwallpaper"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        color: "transparent"

        visible: root.contentReady && !root.surfaceBounce

        updatesEnabled: root.renderActive || root._settleFrames > 0

        mask: Region {
            item: Item {}
        }

        Item {
            id: root
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: SettingsData.effectiveWallpaperBackgroundColor
            }

            function encodeFileUrl(path) {
                if (!path)
                    return "";
                return "file://" + path.split('/').map(s => encodeURIComponent(s)).join('/');
            }

            property string source: SessionData.getMonitorWallpaperImage(modelData.name) || ""
            readonly property bool isColorSource: source.startsWith("#")
            readonly property string displaySource: {
                if (!source || isColorSource)
                    return "";
                return source.startsWith("file://") ? source : encodeFileUrl(source);
            }
            property bool contentReady: false
            property bool surfaceBounce: false

            // Live stack is captured into frozenLayer once stable, then unloaded; if the capture stalls the stack just stays live.
            property bool liveActive: false
            property bool frozenValid: false
            property string _frozenSource: ""
            property bool loadFailed: false
            property int _freezeWaitFrames: 0

            readonly property var backingWindow: Window.window
            readonly property bool showsBackdrop: !source || isColorSource || loadFailed
            readonly property bool backdropBusy: showsBackdrop && !(backdropLoader.item?.ready ?? false)
            readonly property bool renderActive: backdropBusy || liveActive || _freezeWaitFrames > 0
            property int _settleFrames: 3

            readonly property int maxTextureSize: 8192
            readonly property int textureWidth: Math.min(modelData.width, maxTextureSize)
            readonly property int textureHeight: Math.min(modelData.height, maxTextureSize)

            Component.onCompleted: {
                if (!displaySource) {
                    contentReady = true;
                    return;
                }
                liveActive = true;
            }

            onDisplaySourceChanged: {
                invalidate();
                loadFailed = false;
                _freezeWaitFrames = 0;
                if (!displaySource) {
                    liveActive = false;
                    frozenValid = false;
                    _frozenSource = "";
                    contentReady = true;
                    return;
                }
                liveActive = true;
            }

            function regenerate() {
                invalidate();
                if (!displaySource)
                    return;
                if (liveActive) {
                    scheduleFreeze();
                    return;
                }
                liveActive = true;
            }

            function handleDisplayable() {
                contentReady = true;
                if (liveLoader.item?.currentFailed) {
                    if (!frozenValid)
                        loadFailed = true;
                    liveActive = false;
                }
                invalidate();
            }

            function scheduleFreeze() {
                if (!liveLoader.item?.stable)
                    return;
                frozenLayer.scheduleUpdate();
                _freezeWaitFrames = 3;
                _settleFrames = 3;
                // No wedge watchdog: an occluded surface may never produce frames, the freeze just waits
                backingWindow?.update();
            }

            function completeFreeze() {
                const live = liveLoader.item;
                if (!live || !live.stable)
                    return;
                frozenValid = true;
                _frozenSource = displaySource;
                liveActive = false;
                log.info("froze blur layer for", modelData.name);
                invalidate();
            }

            onTextureWidthChanged: regenerate()
            onTextureHeightChanged: regenerate()

            function invalidate() {
                _settleFrames = 3;
                backingWindow?.update();
                if (!_wedgeBounced)
                    wedgeWatchdog.restart();
            }

            onRenderActiveChanged: invalidate()
            onBackingWindowChanged: invalidate()

            // Same wedge recovery as WallpaperBackground
            property bool _wedgeBounced: false

            Timer {
                id: wedgeWatchdog
                interval: 3000
                repeat: false
                onTriggered: {
                    if (!root.backingWindow || !blurWallpaperWindow.visible || IdleService.isShellLocked)
                        return;
                    log.warn("no frame swapped on", modelData.name, "since last invalidate, re-attaching surface");
                    root._wedgeBounced = true;
                    surfaceReattach.restart();
                }
            }

            Timer {
                id: surfaceReattach
                interval: 0
                repeat: false
                onTriggered: {
                    root.surfaceBounce = true;
                    Qt.callLater(() => {
                        root.surfaceBounce = false;
                    });
                }
            }

            Connections {
                target: root.backingWindow
                function onFrameSwapped() {
                    if (root._settleFrames > 0)
                        root._settleFrames--;
                    root._wedgeBounced = false;
                    wedgeWatchdog.stop();
                    if (root._freezeWaitFrames > 0 && --root._freezeWaitFrames === 0)
                        root.completeFreeze();
                }
                function onVisibleChanged() {
                    root.invalidate();
                }
                function onWidthChanged() {
                    root.regenerate();
                }
                function onHeightChanged() {
                    root.regenerate();
                }
            }

            Connections {
                target: blurWallpaperWindow
                function onResourcesLost() {
                    root.frozenValid = false;
                    root.regenerate();
                }
            }

            readonly property var quickshellScreens: Quickshell.screens
            readonly property string settingsWallpaperFillMode: SettingsData.wallpaperFillMode
            readonly property color settingsWallpaperBackgroundColor: SettingsData.effectiveWallpaperBackgroundColor

            onQuickshellScreensChanged: regenerate()
            onSettingsWallpaperFillModeChanged: regenerate()
            onSettingsWallpaperBackgroundColorChanged: invalidate()

            Connections {
                target: SessionData
                function onIsLightModeChanged() {
                    if (SessionData.perModeWallpaper) {
                        var newSource = SessionData.getMonitorWallpaperImage(modelData.name) || "";
                        if (newSource !== root.source) {
                            root.source = newSource;
                        }
                    }
                }
                function onMonitorWallpaperFillModesChanged() {
                    root.regenerate();
                }
                function onPerMonitorWallpaperChanged() {
                    root.regenerate();
                }
            }

            // Theme changes repaint DBackdrop but nothing else wakes the render loop
            readonly property color themePrimary: Theme.primary
            readonly property color themeBackground: Theme.background
            readonly property bool idleShellLocked: IdleService.isShellLocked

            onThemePrimaryChanged: {
                if (!showsBackdrop)
                    return;
                invalidate();
            }

            onThemeBackgroundChanged: {
                if (!showsBackdrop)
                    return;
                invalidate();
            }

            onIdleShellLockedChanged: {
                if (idleShellLocked)
                    return;
                invalidate();
            }

            Connections {
                target: liveLoader.item
                function onBecameDisplayable() {
                    root.handleDisplayable();
                }
                function onStableChanged() {
                    if (liveLoader.item.stable)
                        root.scheduleFreeze();
                }
                function onTransitioningChanged() {
                    root.invalidate();
                }
            }

            Loader {
                id: backdropLoader
                anchors.fill: parent
                active: root.showsBackdrop
                asynchronous: true

                sourceComponent: DBackdrop {
                    screenName: modelData.name
                    blur: Theme.wallpaperBlur
                    onInvalidated: root.invalidate()
                }
            }

            ShaderEffectSource {
                id: frozenLayer
                anchors.fill: parent
                sourceItem: liveContainer
                live: false
                mipmap: false
                recursive: false
                smooth: true
                visible: root.frozenValid || root.liveActive
                textureSize: Qt.size(root.textureWidth, root.textureHeight)
            }

            Item {
                id: liveContainer
                anchors.fill: parent
                visible: root.liveActive

                Loader {
                    id: liveLoader
                    anchors.fill: parent
                    active: root.liveActive
                    asynchronous: false

                    // Cached images reach Ready synchronously during creation, before Connections retargets
                    onLoaded: {
                        if (item.displayableNow)
                            root.handleDisplayable();
                        if (item.stable)
                            root.scheduleFreeze();
                    }

                    sourceComponent: BlurredWallpaperLive {
                        wallpaperSource: root.displaySource
                        initialSource: root._frozenSource
                        screenName: modelData.name
                        blurTextureSize: Qt.size(root.textureWidth, root.textureHeight)
                    }
                }
            }
        }
    }
}
