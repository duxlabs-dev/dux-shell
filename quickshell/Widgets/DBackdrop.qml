import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Common

Item {
    id: root

    property string screenName: ""
    property real blur: 0
    property int blurMax: Theme.wallpaperBlurMax
    readonly property string source: SessionData.getMonitorWallpaper(screenName)
    readonly property bool isColorWallpaper: source.startsWith("#")
    readonly property var composition: SessionData.getMonitorMaterialWallpaper(screenName)
    readonly property var palette: Theme.wallpaperPalette()
    readonly property real pixelRatio: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio
    readonly property string renderKey: JSON.stringify([source, composition, palette, width, height, pixelRatio, blur, blurMax])
    readonly property bool ready: isColorWallpaper || frozenValid
    readonly property bool liveReady: liveActive && (wallpaper.item?.ready ?? false)
    property bool liveActive: false
    property bool frozenValid: false
    property bool snapshotEnabled: true
    property bool capturePending: false
    property string capturedKey: ""

    signal invalidated

    anchors.fill: parent
    onRenderKeyChanged: refresh()
    onReadyChanged: invalidated()
    onLiveReadyChanged: capture()

    function capture() {
        if (!liveReady || capturePending || !frozen.item)
            return;
        capturedKey = renderKey;
        capturePending = true;
        frozen.item.scheduleUpdate();
        invalidated();
    }

    function refresh() {
        frozenValid = false;
        liveActive = !isColorWallpaper;
        capture();
        invalidated();
    }

    Connections {
        target: root.QsWindow.window
        function onResourcesLost() {
            root.snapshotEnabled = false;
            root.refresh();
            root.snapshotEnabled = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.isColorWallpaper ? root.source : root.palette.surface
    }

    Loader {
        id: frozen
        anchors.fill: parent
        active: !root.isColorWallpaper && root.snapshotEnabled
        visible: root.liveActive || root.frozenValid
        onLoaded: root.capture()
        onActiveChanged: {
            if (!active)
                root.capturePending = false;
        }
        sourceComponent: ShaderEffectSource {
            sourceItem: liveContainer
            live: false
            hideSource: true
            smooth: true
            onScheduledUpdateCompleted: {
                root.capturePending = false;
                if (root.capturedKey !== root.renderKey || !root.liveReady) {
                    root.capture();
                    return;
                }
                root.frozenValid = true;
                root.liveActive = false;
                root.invalidated();
            }
        }
    }

    Item {
        id: liveContainer
        anchors.fill: parent
        visible: root.liveActive
        layer.enabled: root.liveActive && root.blur > 0
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: root.blur
            blurMax: root.blurMax
        }

        Loader {
            id: wallpaper
            anchors.fill: parent
            active: root.liveActive
            sourceComponent: MaterialWallpaper {
                composition: root.composition
                palette: root.palette
                onInvalidated: root.invalidated()
            }
        }
    }
}
