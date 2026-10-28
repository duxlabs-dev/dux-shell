import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Services
import qs.Modules.Lock
import "../Common/WorkspaceModel.js" as WorkspaceModel

Variants {
    id: variants
    readonly property var log: Log.scoped("WallpaperBackground")
    // An entry present in PanelWindow.onCompleted means we're recreating
    // after a wl_output rebind, not at initial startup.
    property var _seenScreens: ({})
    readonly property bool desktopMenuEnabled: CompositorService.desktopContextMenuEnabled
    // niri skips place-within-backdrop surfaces when hit-testing, so the wallpaper never sees clicks there.
    readonly property bool desktopMenuOnWallpaper: desktopMenuEnabled && !CompositorService.isNiri
    model: SettingsData.getFilteredScreens("wallpaper")

    PanelWindow {
        id: wallpaperWindow

        required property var modelData

        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        color: "transparent"

        visible: root.contentReady && !root.surfaceBounce

        updatesEnabled: root.renderActive || root._settleFrames > 0

        Region {
            id: emptyRegion
        }

        mask: variants.desktopMenuOnWallpaper ? null : emptyRegion

        MouseArea {
            anchors.fill: parent
            z: 1
            enabled: variants.desktopMenuOnWallpaper
            acceptedButtons: Qt.RightButton
            onClicked: mouse => PopoutService.desktopContextMenu?.open(wallpaperWindow.screen, mouse.x, mouse.y, false)
        }

        Loader {
            active: variants.desktopMenuEnabled && CompositorService.isNiri

            sourceComponent: PanelWindow {
                screen: wallpaperWindow.screen
                color: "transparent"

                WlrLayershell.namespace: "dms:desktop-input"
                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: mouse => PopoutService.desktopContextMenu?.open(wallpaperWindow.screen, mouse.x, mouse.y, false)
                }
            }
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

            property string source: SessionData.getMonitorWallpaper(modelData.name) || ""
            property bool isColorSource: source.startsWith("#")
            property string transitionType: SessionData.wallpaperTransition
            property string actualTransitionType: transitionType
            property bool isInitialized: false

            property bool contentReady: false
            property bool surfaceBounce: false

            readonly property bool scrollingEnabled: SessionData.getMonitorWallpaperFillMode(modelData.name) === "Scrolling"
            property int currentWorkspaceIndex: 0
            property int totalWorkspaces: 1
            // Also requires the image to overflow on the compositor's scroll
            // axis — niri scrolls Y, Hyprland scrolls X — otherwise the
            // currentWallpaper Fill fallback handles it.
            property bool effectiveScrolling: scrollingEnabled && totalWorkspaces > 1 && (!imageMetrics.ready || (CompositorService.isNiri && imageMetrics.nativeWidth / imageMetrics.nativeHeight < root.textureWidth / root.textureHeight - 0.01) || (CompositorService.isHyprland && imageMetrics.nativeWidth / imageMetrics.nativeHeight > root.textureWidth / root.textureHeight + 0.01))

            Connections {
                target: SessionData
                enabled: SessionData.perModeWallpaper

                function onIsLightModeChanged() {
                    const newSource = SessionData.getMonitorWallpaper(modelData.name) || "";
                    if (newSource !== root.source)
                        root.source = newSource;
                }
            }

            Connections {
                target: CompositorService.isNiri ? NiriService : null
                enabled: CompositorService.isNiri && root.scrollingEnabled

                function onAllWorkspacesChanged() {
                    root.updateWorkspaceData();
                }
            }

            Connections {
                target: CompositorService.isHyprland ? Hyprland : null
                enabled: CompositorService.isHyprland && root.scrollingEnabled

                function onRawEvent(event) {
                    if (event.name === "workspace" || event.name === "workspacev2") {
                        root.updateWorkspaceData();
                    }
                }
            }

            onTransitionTypeChanged: {
                if (transitionType !== "random") {
                    actualTransitionType = transitionType;
                    return;
                }
                actualTransitionType = SessionData.includedTransitions.length === 0 ? "none" : SessionData.includedTransitions[Math.floor(Math.random() * SessionData.includedTransitions.length)];
            }

            property real transitionProgress: 0
            property real shaderFillMode: Theme.getFillMode(SessionData.getMonitorWallpaperFillMode(modelData.name))
            property vector4d fillColor: Qt.vector4d(0, 0, 0, 1)
            property real edgeSmoothness: 0.1

            property real wipeDirection: 0
            property real discCenterX: 0.5
            property real discCenterY: 0.5
            property real stripesCount: 16
            property real stripesAngle: 0

            readonly property bool transitioning: transitionAnimation.running
            property bool effectActive: false
            property bool useNextForEffect: false
            property string pendingWallpaper: ""
            property string _deferredSource: ""
            // Held true from the moment a wallpaper change is initiated until it
            // settles, so the paused render loop wakes and drives the async load
            // and transition even when nothing else marks the window dirty.
            property bool changePending: false
            // Image is released after srcCurrent grabs it, only the texture stays resident
            property string currentSource: ""
            property bool frozenValid: false
            property int _freezeWaitFrames: 0
            readonly property bool overviewBlurActive: CompositorService.isNiri && SettingsData.blurWallpaperOnOverview && NiriService.inOverview && (currentSource !== "" || showsBackdrop)
            readonly property var backingWindow: Window.window
            readonly property bool showsBackdrop: !source || isColorSource || currentWallpaper.status === Image.Error
            readonly property bool backdropBusy: showsBackdrop && !(backdropLoader.item?.ready ?? false)
            readonly property bool renderActive: backdropBusy || effectActive || overviewBlurActive || pendingWallpaper !== "" || _deferredSource !== "" || changePending || _freezeWaitFrames > 0 || frameAnim.running || currentWallpaper.status === Image.Loading || nextWallpaper.status === Image.Loading || parallaxImage.status === Image.Loading || lockScrollSampler.busy
            property int _settleFrames: 3

            function invalidate() {
                _settleFrames = 3;
                backingWindow?.update();
                if (!_wedgeBounced)
                    wedgeWatchdog.restart();
            }

            onRenderActiveChanged: invalidate()
            onBackingWindowChanged: regenerate()
            onTextureWidthChanged: regenerate()
            onTextureHeightChanged: regenerate()

            function scheduleFreeze() {
                if (root.effectiveScrolling) {
                    finishTransition();
                    return;
                }
                root.frozenValid = true;
                srcCurrent.scheduleUpdate();
                root._freezeWaitFrames = 3;
                invalidate();
            }

            function completeFreeze() {
                if (currentWallpaper.status === Image.Ready && !root.effectiveScrolling)
                    currentWallpaper.source = "";
                finishTransition();
                invalidate();
            }

            function regenerate() {
                invalidate();
                if (!root.currentSource || currentWallpaper.source.toString() || nextWallpaper.source.toString())
                    return;
                currentWallpaper.source = root.currentSource;
            }

            function finishTransition() {
                if (root.transitioning)
                    return;
                root.useNextForEffect = false;
                nextWallpaper.source = "";
                root.transitionProgress = 0.0;
                root.effectActive = false;
                root.changePending = false;

                if (!root.pendingWallpaper)
                    return;
                const pending = root.pendingWallpaper;
                root.pendingWallpaper = "";
                Qt.callLater(() => root.changeWallpaper(pending));
            }

            // No swap after a requested frame: dropped frame callback left the window
            // unexposed (qtwayland mFrameCallbackTimedOut); only surface re-attach recovers.
            property bool _wedgeBounced: false

            Timer {
                id: wedgeWatchdog
                interval: 3000
                repeat: false
                onTriggered: {
                    if (!root.backingWindow || !wallpaperWindow.visible || IdleService.isShellLocked)
                        return;
                    log.warn("no frame swapped on", modelData.name, "since last invalidate, re-attaching surface");
                    root._wedgeBounced = true;
                    surfaceReattach.restart();
                }
            }

            Connections {
                target: root.backingWindow
                function onFrameSwapped() {
                    if (root._settleFrames > 0)
                        root._settleFrames--;
                    root._wedgeBounced = false;
                    wedgeWatchdog.stop();
                    if (root._freezeWaitFrames === 0)
                        return;
                    if (--root._freezeWaitFrames === 0) {
                        root.completeFreeze();
                        return;
                    }
                    root.backingWindow?.update();
                }
                function onVisibleChanged() {
                    root.invalidate();
                }
                function onWidthChanged() {
                    root.invalidate();
                }
                function onHeightChanged() {
                    root.invalidate();
                }
            }

            Connections {
                target: wallpaperWindow
                function onResourcesLost() {
                    root.frozenValid = false;
                    root.regenerate();
                }
            }

            Connections {
                target: Quickshell
                function onScreensChanged() {
                    root.invalidate();
                    root._onOutputRebind();
                }
            }

            readonly property string settingsWallpaperFillMode: SettingsData.wallpaperFillMode
            readonly property color settingsWallpaperBackgroundColor: SettingsData.effectiveWallpaperBackgroundColor

            onSettingsWallpaperFillModeChanged: regenerate()
            onSettingsWallpaperBackgroundColorChanged: invalidate()

            readonly property var sessionMonitorWallpaperFillModes: SessionData.monitorWallpaperFillModes
            readonly property bool sessionPerMonitorWallpaper: SessionData.perMonitorWallpaper

            onSessionMonitorWallpaperFillModesChanged: regenerate()
            onSessionPerMonitorWallpaperChanged: regenerate()

            // Theme changes repaint DBackdrop but nothing else wakes the render loop
            readonly property color themePrimary: Theme.primary
            readonly property color themeBackground: Theme.background

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

            readonly property bool idleShellLocked: IdleService.isShellLocked

            onIdleShellLockedChanged: {
                if (idleShellLocked)
                    return;
                invalidate();
                // Catches silent rebinds during lock that no signal reports.
                if (effectiveScrolling)
                    surfaceReattach.restart();
            }

            function _recheckScreenScale() {
                const newScale = CompositorService.getScreenScale(modelData);
                if (newScale !== root.screenScale) {
                    log.info("screen scale corrected for", modelData.name + ":", root.screenScale, "->", newScale);
                    root.screenScale = newScale;
                }
            }

            // Workspace/scale signals don't re-fire when the output list is
            // unchanged across a rebind, so re-derive scroll state by hand.
            function _onOutputRebind() {
                if (!root.scrollingEnabled)
                    return;
                root.firstScrollUpdate = true;
                Qt.callLater(root.updateWorkspaceData);
                parallaxLoader.rebuild();
                if (root.effectiveScrolling && !IdleService.isShellLocked)
                    surfaceReattach.restart();
            }

            // Bouncing visible re-attaches a layer surface wedged by a rebind;
            // debounced so a burst of signals yields one re-attach.
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
                target: NiriService
                function onDisplayScalesChanged() {
                    root._recheckScreenScale();
                    root.invalidate();
                    root._onOutputRebind();
                }
            }

            Connections {
                target: WlrOutputService
                function onWlrOutputAvailableChanged() {
                    root._recheckScreenScale();
                    root.invalidate();
                    root._onOutputRebind();
                }
            }

            Connections {
                target: CompositorService
                function onRandrDataReady() {
                    if (root._deferredSource) {
                        const src = root._deferredSource;
                        root._deferredSource = "";
                        root.setWallpaperImmediate(src);
                    } else {
                        root._recheckScreenScale();
                    }
                    root._onOutputRebind();
                }
            }

            function handleTransitionLoadError(failedSource) {
                log.warn("failed to load candidate wallpaper for", modelData.name + ":", failedSource);
                transitionDelayTimer.stop();
                transitionAnimation.stop();
                root.useNextForEffect = false;
                root.effectActive = false;
                root.transitionProgress = 0.0;
                root.changePending = false;
                currentWallpaper.layer.enabled = false;
                nextWallpaper.layer.enabled = false;
                nextWallpaper.source = "";

                if (!root.pendingWallpaper)
                    return;
                const pending = root.pendingWallpaper;
                root.pendingWallpaper = "";
                Qt.callLater(() => root.changeWallpaper(pending));
            }

            function updateWorkspaceData() {
                if (!scrollingEnabled)
                    return;

                let newTargetX = 50.0;
                let newTargetY = 50.0;

                if (CompositorService.isNiri) {
                    const outputWorkspaces = NiriService.allWorkspaces.filter(ws => ws.output === modelData.name);
                    totalWorkspaces = outputWorkspaces.length;

                    const activeWs = outputWorkspaces.find(ws => ws.is_active);
                    currentWorkspaceIndex = activeWs ? activeWs.idx : 0;

                    const scrollPercent = totalWorkspaces > 1 ? ((currentWorkspaceIndex - 1) / (totalWorkspaces - 1)) * 100.0 : 0.0;

                    newTargetY = scrollPercent;
                } else if (CompositorService.isHyprland) {
                    const workspaces = Hyprland.workspaces?.values || [];
                    const monitorWorkspaces = workspaces.filter(ws => ws.monitor?.name === modelData.name).sort((a, b) => a.id - b.id);

                    totalWorkspaces = monitorWorkspaces.length;
                    const focusedKey = WorkspaceModel.hyprlandKey(Hyprland.focusedWorkspace);
                    currentWorkspaceIndex = monitorWorkspaces.findIndex(ws => WorkspaceModel.hyprlandKey(ws) === focusedKey);

                    if (currentWorkspaceIndex < 0)
                        currentWorkspaceIndex = 0;

                    const scrollPercent = totalWorkspaces > 1 ? (currentWorkspaceIndex / (totalWorkspaces - 1)) * 100.0 : 0.0;

                    newTargetX = scrollPercent;
                }

                scrollAnim.startAnimation(newTargetX, newTargetY);
            }

            property bool firstScrollUpdate: true

            QtObject {
                id: scrollAnim
                property real startTime: 0
                property real startX: 0.0
                property real startY: 0.0
                property real targetX: 0.0
                property real targetY: 0.0

                property real damping: CompositorService.isNiri ? 63.25 : 89.44
                property real stiffness: CompositorService.isNiri ? 1000.0 : 2000.0
                property real mass: 1.0

                function springPositionJS(t, from, to) {
                    if (t <= 0)
                        return from;
                    const beta = damping / (2 * mass);
                    const omega0 = Math.sqrt(stiffness / mass);
                    const x0 = from - to;
                    const envelope = Math.exp(-beta * t);
                    if (Math.abs(x0 * envelope) < 0.01)
                        return to;

                    if (Math.abs(beta - omega0) < 0.0001) {
                        return to + envelope * (x0 + beta * x0 * t);
                    } else if (beta < omega0) {
                        const omega1 = Math.sqrt(omega0 * omega0 - beta * beta);
                        return to + envelope * (x0 * Math.cos(omega1 * t) + (beta * x0 / omega1) * Math.sin(omega1 * t));
                    } else {
                        const omega2 = Math.sqrt(beta * beta - omega0 * omega0);
                        const cosh = x => (Math.exp(x) + Math.exp(-x)) / 2;
                        const sinh = x => (Math.exp(x) - Math.exp(-x)) / 2;
                        return to + envelope * (x0 * cosh(omega2 * t) + (beta * x0 / omega2) * sinh(omega2 * t));
                    }
                }

                function startAnimation(newTargetX, newTargetY) {
                    const now = Date.now() / 1000.0;
                    const t = Math.max(0, frameAnim.currentTime - startTime);
                    const currentX = springPositionJS(t, startX, targetX);
                    const currentY = springPositionJS(t, startY, targetY);

                    if (Math.abs(newTargetX - currentX) < 0.01 && Math.abs(newTargetY - currentY) < 0.01) {
                        if (root.firstScrollUpdate)
                            root.firstScrollUpdate = false;
                        return;
                    }

                    // First update: use much stiffer spring for quick snap-to
                    if (root.firstScrollUpdate) {
                        root.firstScrollUpdate = false;
                        damping = 200.0;
                        stiffness = 8000.0;
                    } else {
                        // Restore normal spring parameters
                        damping = CompositorService.isNiri ? 63.25 : 89.44;
                        stiffness = CompositorService.isNiri ? 1000.0 : 2000.0;
                    }

                    startX = currentX;
                    startY = currentY;
                    targetX = newTargetX;
                    targetY = newTargetY;
                    startTime = frameAnim.running ? frameAnim.currentTime : now;
                    if (!frameAnim.running) {
                        frameAnim.currentTime = now;
                        frameAnim.running = true;
                    }
                }
            }

            // CPU-side scroll position - computed once per frame instead of per-pixel in shader
            // Initialize at (0, 0) to avoid pillarbox flash; first update will snap to correct position
            property real currentScrollX: 0.0
            property real currentScrollY: 0.0

            function publishScrollPosition() {
                if (effectiveScrolling) {
                    SessionData.setMonitorScrollPosition(modelData.name, currentScrollX, currentScrollY);
                } else {
                    // Not scrolling - publish centered (50, 50)
                    SessionData.setMonitorScrollPosition(modelData.name, 50, 50);
                }
            }

            FrameAnimation {
                id: frameAnim
                running: false

                property real currentTime: 0

                onRunningChanged: {
                    if (running) {
                        currentTime = Date.now() / 1000.0;
                    } else {
                        root.publishScrollPosition();  // Animation settled
                        // Hold the render loop open so the final settled frame
                        // commits before updatesEnabled drops out from under us.
                        root.invalidate();
                    }
                }

                onTriggered: {
                    // Clamp huge frameTime from a paused-render-loop wakeup;
                    // otherwise the spring's `t` jumps past settling.
                    const dt = frameTime > 0.1 ? 0.0 : frameTime;
                    currentTime += dt;

                    const t = currentTime - scrollAnim.startTime;
                    root.currentScrollX = scrollAnim.springPositionJS(t, scrollAnim.startX, scrollAnim.targetX);
                    root.currentScrollY = scrollAnim.springPositionJS(t, scrollAnim.startY, scrollAnim.targetY);

                    const settledX = Math.abs(scrollAnim.targetX - root.currentScrollX) < 0.01;
                    const settledY = Math.abs(scrollAnim.targetY - root.currentScrollY) < 0.01;

                    if (settledX && settledY) {
                        running = false;
                    }
                }
            }

            Component.onCompleted: {
                isInitialized = true;
                if (!source || isColorSource) {
                    contentReady = true;
                }

                if (scrollingEnabled) {
                    updateWorkspaceData();
                }

                Qt.callLater(publishScrollPosition);

                // Detect rebind via _seenScreens; schedule surface re-attach
                // (deferred to unlock if locked).
                const wasSeen = variants._seenScreens[modelData.name] === true;
                variants._seenScreens[modelData.name] = true;
                // If currently locked, the unlock handler will re-attach;
                // otherwise re-attach now.
                if (wasSeen && root.effectiveScrolling && !IdleService.isShellLocked) {
                    surfaceReattach.restart();
                }
            }

            Component.onDestruction: {
                SessionData.clearMonitorScrollPosition(modelData.name);
            }

            onScrollingEnabledChanged: {
                if (scrollingEnabled) {
                    firstScrollUpdate = true;
                    updateWorkspaceData();
                } else {
                    frameAnim.stop();
                }
            }

            onEffectiveScrollingChanged: {
                publishScrollPosition();
            }

            onSourceChanged: {
                invalidate();
                if (!source || source.startsWith("#")) {
                    setWallpaperImmediate("");
                    return;
                }

                root.changePending = true;

                const formattedSource = source.startsWith("file://") ? source : encodeFileUrl(source);

                if (!isInitialized || !root.currentSource) {
                    if (!CompositorService.randrReady) {
                        _deferredSource = formattedSource;
                        return;
                    }
                    setWallpaperImmediate(formattedSource);
                    return;
                }
                if (CompositorService.isNiri && SessionData.isSwitchingMode) {
                    setWallpaperImmediate(formattedSource);
                    return;
                }
                changeWallpaper(formattedSource);
            }

            function setWallpaperImmediate(newSource) {
                root.pendingWallpaper = "";
                root._deferredSource = "";
                root._freezeWaitFrames = 0;
                transitionDelayTimer.stop();
                transitionAnimation.stop();
                root.transitionProgress = 0.0;
                root.effectActive = false;
                root.screenScale = CompositorService.getScreenScale(modelData);
                nextWallpaper.source = "";
                resetScrollState();
                if (!newSource) {
                    root.currentSource = "";
                    root.frozenValid = false;
                    root.changePending = false;
                    root.contentReady = true;
                    currentWallpaper.source = "";
                    return;
                }
                if (root.currentSource === newSource && root.frozenValid) {
                    root.changePending = false;
                    root.contentReady = true;
                    return;
                }
                currentWallpaper.source = newSource;
            }

            function resetScrollState() {
                if (!scrollingEnabled)
                    return;
                firstScrollUpdate = true;
                currentScrollX = 0.0;
                currentScrollY = 0.0;
                scrollAnim.startX = 0.0;
                scrollAnim.startY = 0.0;
                scrollAnim.targetX = 0.0;
                scrollAnim.targetY = 0.0;
            }

            function startTransition() {
                root.useNextForEffect = true;
                root.effectActive = true;
                srcNext.scheduleUpdate();
                transitionDelayTimer.start();
            }

            Timer {
                id: transitionDelayTimer
                interval: 16
                repeat: false
                onTriggered: transitionAnimation.start()
            }

            function changeWallpaper(newPath) {
                const expectedSource = root.source.startsWith("file://") ? root.source : encodeFileUrl(root.source);
                if (newPath !== expectedSource)
                    return;
                if (!newPath || newPath.startsWith("#")) {
                    root.changePending = false;
                    return;
                }
                root.screenScale = CompositorService.getScreenScale(modelData);
                if (root.transitioning || root.effectActive) {
                    root.pendingWallpaper = newPath;
                    return;
                }
                if (newPath === root.currentSource) {
                    if (nextWallpaper.source.toString()) {
                        setWallpaperImmediate(newPath);
                        return;
                    }
                    root.changePending = false;
                    return;
                }
                if (!root.currentSource) {
                    setWallpaperImmediate(newPath);
                    return;
                }

                if (root.effectiveScrolling) {
                    setWallpaperImmediate(newPath);
                    return;
                }

                if (root.transitionType === "random") {
                    root.actualTransitionType = SessionData.includedTransitions.length === 0 ? "none" : SessionData.includedTransitions[Math.floor(Math.random() * SessionData.includedTransitions.length)];
                }

                if (root.actualTransitionType === "none") {
                    setWallpaperImmediate(newPath);
                    return;
                }

                switch (root.actualTransitionType) {
                case "wipe":
                    root.wipeDirection = Math.random() * 4;
                    break;
                case "disc":
                case "pixelate":
                case "portal":
                    root.discCenterX = Math.random();
                    root.discCenterY = Math.random();
                    break;
                case "stripes":
                    root.stripesCount = Math.round(Math.random() * 20 + 4);
                    root.stripesAngle = Math.random() * 360;
                    break;
                }

                nextWallpaper.source = newPath;

                if (nextWallpaper.status === Image.Ready)
                    root.startTransition();
            }

            Loader {
                id: backdropLoader
                anchors.fill: parent
                active: root.showsBackdrop
                asynchronous: true

                sourceComponent: DBackdrop {
                    screenName: modelData.name
                    onInvalidated: root.invalidate()
                }
            }

            readonly property int maxTextureSize: 8192
            property real screenScale: 1
            property int textureWidth: Math.min(Math.round(modelData.width * screenScale), maxTextureSize)
            property int textureHeight: Math.min(Math.round(modelData.height * screenScale), maxTextureSize)

            LockScrollSampler {
                id: lockScrollSampler
                screen: modelData
            }

            QtObject {
                id: imageMetrics
                property real nativeWidth: 0
                property real nativeHeight: 0
                property bool ready: nativeWidth > 0 && nativeHeight > 0

                function capture(w, h) {
                    if (nativeWidth === 0 && w > 0) {
                        nativeWidth = w;
                        nativeHeight = h;
                    }
                }

                function reset() {
                    nativeWidth = 0;
                    nativeHeight = 0;
                }

                readonly property real canvasWidth: {
                    if (!ready || !root.effectiveScrolling)
                        return root.textureWidth;
                    const imageAspect = nativeWidth / nativeHeight;
                    const screenAspect = root.textureWidth / root.textureHeight;
                    if (imageAspect < screenAspect) {
                        return root.textureWidth;
                    } else {
                        return root.textureHeight * imageAspect;
                    }
                }

                readonly property real canvasHeight: {
                    if (!ready || !root.effectiveScrolling)
                        return root.textureHeight;
                    const imageAspect = nativeWidth / nativeHeight;
                    const screenAspect = root.textureWidth / root.textureHeight;
                    if (imageAspect < screenAspect) {
                        return root.textureWidth / imageAspect;
                    } else {
                        return root.textureHeight;
                    }
                }
            }

            Image {
                id: currentWallpaper
                anchors.fill: parent
                visible: !root.effectiveScrolling
                opacity: 1
                asynchronous: true
                retainWhileLoading: true
                smooth: true
                cache: true

                sourceSize: Qt.size(root.textureWidth, root.textureHeight)
                fillMode: Theme.getFillMode(SessionData.getMonitorWallpaperFillMode(modelData.name))

                onStatusChanged: {
                    if (status === Image.Error) {
                        log.warn("failed to load active wallpaper for", modelData.name + ":", source);
                    }
                    if (status === Image.Ready) {
                        imageMetrics.capture(implicitWidth, implicitHeight);
                        root.currentSource = source.toString();
                        root.scheduleFreeze();
                    }
                    if (status === Image.Ready || status === Image.Error) {
                        root.changePending = false;
                        root.contentReady = true;
                    }
                }

                onSourceChanged: {
                    if (source.toString())
                        imageMetrics.reset();
                }
            }

            Image {
                id: nextWallpaper
                anchors.fill: parent
                visible: source !== ""
                opacity: 0
                asynchronous: true
                retainWhileLoading: true
                smooth: true
                cache: true

                sourceSize: Qt.size(root.textureWidth, root.textureHeight)
                fillMode: Theme.getFillMode(SessionData.getMonitorWallpaperFillMode(modelData.name))

                onStatusChanged: {
                    if (status === Image.Error) {
                        root.handleTransitionLoadError(source);
                        return;
                    }
                    if (status !== Image.Ready)
                        return;
                    if (root.actualTransitionType === "none") {
                        currentWallpaper.source = source;
                        nextWallpaper.source = "";
                        root.transitionProgress = 0.0;
                    } else if (!root.transitioning) {
                        root.startTransition();
                    }
                }
            }

            ShaderEffectSource {
                id: srcCurrent
                anchors.fill: parent
                sourceItem: currentWallpaper
                visible: root.frozenValid && !root.effectiveScrolling
                hideSource: false
                live: false
                smooth: true
                mipmap: false
                recursive: false
                textureSize: Qt.size(root.textureWidth, root.textureHeight)
            }

            ShaderEffectSource {
                id: srcNext
                sourceItem: root.effectActive ? nextWallpaper : null
                hideSource: root.effectActive
                live: root.effectActive
                mipmap: false
                recursive: false
                textureSize: Qt.size(root.textureWidth, root.textureHeight)
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

            // Parallax scrolling pipeline — bypasses transition machinery.
            Image {
                id: parallaxImage
                visible: false
                width: imageMetrics.canvasWidth
                height: imageMetrics.canvasHeight
                source: root.effectiveScrolling ? root.currentSource : ""
                asynchronous: true
                smooth: true
                cache: true
                sourceSize: Qt.size(imageMetrics.canvasWidth, imageMetrics.canvasHeight)
                fillMode: Image.Stretch
            }

            ShaderEffectSource {
                id: srcParallax
                sourceItem: root.effectiveScrolling && imageMetrics.ready && parallaxImage.status === Image.Ready ? parallaxImage : null
                hideSource: false
                live: true
                mipmap: false
                recursive: false
                textureSize: Qt.size(imageMetrics.canvasWidth, imageMetrics.canvasHeight)
            }

            // Pre-computed UV parameters for shader
            QtObject {
                id: parallaxUV
                readonly property real imageAspect: imageMetrics.ready ? imageMetrics.canvasWidth / imageMetrics.canvasHeight : 1.0
                readonly property real screenAspect: root.textureWidth / root.textureHeight

                // Scale factor to fit image to screen (preserving aspect, cropping excess)
                readonly property real scale: Math.max(root.textureWidth / imageMetrics.canvasWidth, root.textureHeight / imageMetrics.canvasHeight)
                readonly property real scaledWidth: imageMetrics.canvasWidth * scale
                readonly property real scaledHeight: imageMetrics.canvasHeight * scale

                // UV scale: portion of texture visible on screen
                readonly property real uvScaleX: root.textureWidth / scaledWidth
                readonly property real uvScaleY: root.textureHeight / scaledHeight

                // Scroll range: how much UV space we can scroll through
                // Only allow scrolling in the dimension where image exceeds screen
                readonly property real scrollRangeX: imageAspect > screenAspect + 0.01 ? (1.0 - uvScaleX) : (1.0 - uvScaleX) * 0.5
                readonly property real scrollRangeY: imageAspect < screenAspect - 0.01 ? (1.0 - uvScaleY) : (1.0 - uvScaleY) * 0.5
                readonly property bool scrollsHorizontal: imageAspect > screenAspect + 0.01
                readonly property bool scrollsVertical: imageAspect < screenAspect - 0.01
            }

            Loader {
                id: parallaxLoader
                anchors.fill: parent
                active: root.effectiveScrolling && !root.effectActive && imageMetrics.ready && parallaxImage.status === Image.Ready
                sourceComponent: parallaxScrollComp

                // Rebuild after a rebind orphans the texture; callLater defeats
                // sourceComponent coalescing.
                function rebuild() {
                    if (!active)
                        return;
                    sourceComponent = null;
                    Qt.callLater(() => {
                        sourceComponent = parallaxScrollComp;
                    });
                }
            }

            Component {
                id: parallaxScrollComp
                ShaderEffect {
                    anchors.fill: parent

                    property variant source: srcParallax.sourceItem ? srcParallax : srcDummy

                    property real scrollX: root.currentScrollX
                    property real scrollY: root.currentScrollY
                    property real uvScaleX: parallaxUV.uvScaleX
                    property real uvScaleY: parallaxUV.uvScaleY
                    property real scrollRangeX: parallaxUV.scrollsHorizontal ? parallaxUV.scrollRangeX : 0.0
                    property real scrollRangeY: parallaxUV.scrollsVertical ? parallaxUV.scrollRangeY : 0.0

                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_parallax_scroll.frag.qsb")
                }
            }

            Loader {
                id: effectLoader
                anchors.fill: parent
                active: root.effectActive

                function getTransitionComponent(type) {
                    switch (type) {
                    case "fade":
                        return fadeComp;
                    case "wipe":
                        return wipeComp;
                    case "disc":
                        return discComp;
                    case "stripes":
                        return stripesComp;
                    case "iris bloom":
                        return irisComp;
                    case "pixelate":
                        return pixelateComp;
                    case "portal":
                        return portalComp;
                    default:
                        return null;
                    }
                }

                sourceComponent: getTransitionComponent(root.actualTransitionType)
            }

            Component {
                id: fadeComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    property real scrollX: 50
                    property real scrollY: 50
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_fade.frag.qsb")
                }
            }

            Component {
                id: wipeComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real smoothness: root.edgeSmoothness
                    property real direction: root.wipeDirection
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_wipe.frag.qsb")
                }
            }

            Component {
                id: discComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real smoothness: root.edgeSmoothness
                    property real aspectRatio: root.width / root.height
                    property real centerX: root.discCenterX
                    property real centerY: root.discCenterY
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_disc.frag.qsb")
                }
            }

            Component {
                id: stripesComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real smoothness: root.edgeSmoothness
                    property real aspectRatio: root.width / root.height
                    property real stripeCount: root.stripesCount
                    property real angle: root.stripesAngle
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_stripes.frag.qsb")
                }
            }

            Component {
                id: irisComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real smoothness: root.edgeSmoothness
                    property real centerX: 0.5
                    property real centerY: 0.5
                    property real aspectRatio: root.width / root.height
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_iris_bloom.frag.qsb")
                }
            }

            Component {
                id: pixelateComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real smoothness: root.edgeSmoothness
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    property real centerX: root.discCenterX
                    property real centerY: root.discCenterY
                    property real aspectRatio: root.width / root.height
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_pixelate.frag.qsb")
                }
            }

            Component {
                id: portalComp
                ShaderEffect {
                    anchors.fill: parent
                    property variant source1: srcCurrent
                    property variant source2: root.useNextForEffect ? srcNext : srcDummy
                    property real progress: root.transitionProgress
                    property real smoothness: root.edgeSmoothness
                    property real aspectRatio: root.width / root.height
                    property real centerX: root.discCenterX
                    property real centerY: root.discCenterY
                    property real fillMode: root.shaderFillMode
                    property vector4d fillColor: root.fillColor
                    property real imageWidth1: modelData.width
                    property real imageHeight1: modelData.height
                    property real imageWidth2: modelData.width
                    property real imageHeight2: modelData.height
                    property real screenWidth: modelData.width
                    property real screenHeight: modelData.height
                    fragmentShader: Qt.resolvedUrl("../Shaders/qsb/wp_portal.frag.qsb")
                }
            }

            NumberAnimation {
                id: transitionAnimation
                target: root
                property: "transitionProgress"
                from: 0.0
                to: 1.0
                duration: root.actualTransitionType === "none" ? 0 : 1000
                easing.type: Easing.InOutCubic
                onFinished: {
                    if (!nextWallpaper.source || nextWallpaper.status !== Image.Ready) {
                        root.finishTransition();
                        return;
                    }
                    currentWallpaper.source = nextWallpaper.source;
                    if (root._freezeWaitFrames === 0 && currentWallpaper.status !== Image.Loading)
                        root.finishTransition();
                }
            }

            Loader {
                id: overviewBlurLoader
                anchors.fill: parent
                active: root.overviewBlurActive

                sourceComponent: MultiEffect {
                    anchors.fill: parent
                    source: root.showsBackdrop ? backdropLoader.item : (effectLoader.active ? effectLoader.item : (parallaxLoader.active ? parallaxLoader.item : srcCurrent))
                    blurEnabled: true
                    blur: 0.8
                    blurMax: 75
                    autoPaddingEnabled: false
                }
            }
        }
    }
}
