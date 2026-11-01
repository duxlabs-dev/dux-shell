import QtQuick
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool isPlaying: activePlayer !== null && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool live: visible && enabled && (Window.window?.visible ?? false) && isPlaying
    readonly property bool available: CavaService.cavaAvailable && SettingsData.audioVisualizerEnabled
    readonly property bool showBars: idleIconName === "" || (available && live)

    property real maxBarHeight: Theme.iconSize - 2
    readonly property real minBarHeight: 3
    property color barColor: Theme.primary
    property string idleIconName: ""

    width: 20
    height: Theme.iconSize

    onLiveChanged: {
        if (!live) {
            bars.bandsA = Qt.vector4d(0, 0, 0, 0);
            bars.bandsB = Qt.vector2d(0, 0);
        }
    }

    Loader {
        active: root.live && root.available
        sourceComponent: Component {
            Ref {
                service: CavaService
            }
        }
    }

    Connections {
        target: CavaService
        enabled: root.live && root.available
        function onValuesChanged() {
            const v = CavaService.values;
            if (v.length < 6)
                return;
            const n = i => {
                const x = v[i];
                const level = x <= 0 ? 0 : x >= 100 ? 1 : Math.sqrt(x * 0.01);
                return Math.round(level * 32) / 32;
            };
            const a = Qt.vector4d(n(0), n(1), n(2), n(3));
            const b = Qt.vector2d(n(4), n(5));
            if (a == bars.bandsA && b == bars.bandsB)
                return;
            bars.bandsA = a;
            bars.bandsB = b;
        }
    }

    ShaderEffect {
        id: bars
        anchors.fill: parent
        visible: root.showBars

        property real widthPx: width
        property real heightPx: height
        property real minH: root.minBarHeight
        property real maxH: root.maxBarHeight
        property vector4d bandsA: Qt.vector4d(0, 0, 0, 0)
        property vector2d bandsB: Qt.vector2d(0, 0)
        property vector4d fillColor: Qt.vector4d(root.barColor.r, root.barColor.g, root.barColor.b, root.barColor.a)

        fragmentShader: Qt.resolvedUrl("../../../Shaders/qsb/viz_bars.frag.qsb")
    }

    DIcon {
        anchors.centerIn: parent
        visible: !root.showBars
        name: root.idleIconName
        size: Math.min(parent.width, parent.height)
        color: root.barColor
    }
}
