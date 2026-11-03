import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.Common
import qs.Services

Item {
    id: root

    property MprisPlayer activePlayer
    property real radius: Theme.cornerRadius
    property real artOpacity: 0.7
    property real surfaceTint: 0.3
    property real stableHeight: 0
    property string artUrl: TrackArtService.resolvedArtUrl

    readonly property bool pinned: root.stableHeight > 0
    readonly property real anchorHeight: root.pinned ? root.stableHeight : root.height
    readonly property real blurExtent: Math.max(root.width, root.anchorHeight) * 1.1
    readonly property int blurDecodeSize: Math.min(384, Math.max(128, Math.ceil(root.blurExtent / 128) * 128))

    signal artReady

    readonly property string curArt: artUrl
    property bool _showA: true
    readonly property bool transitioning: layerA.revealing || layerB.revealing
    readonly property bool onScreen: visible && (Window.window?.visible ?? false)

    visible: layerA.ready || layerB.ready

    onCurArtChanged: syncArt()
    onOnScreenChanged: {
        if (onScreen)
            return;
        layerA.finishReveal();
        layerB.finishReveal();
    }
    Component.onCompleted: syncArt()

    function syncArt() {
        if (curArt === "") {
            layerA.art = "";
            layerB.art = "";
            return;
        }
        const front = _showA ? layerA : layerB;
        const back = _showA ? layerB : layerA;
        if (front.art == curArt)
            return;
        front.finishReveal();
        if (back.art == curArt) {
            if (back.ready)
                promote(back);
            return;
        }
        back.art = curArt;
    }

    function promote(layer) {
        const front = _showA ? layerA : layerB;
        const back = _showA ? layerB : layerA;
        if (layer !== back || layer.art != curArt)
            return;
        const animate = onScreen && !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None;
        _showA = (layer === layerA);
        if (animate)
            layer.reveal();
        else
            layer.finishReveal();
        root.artReady();
    }

    Item {
        anchors.fill: parent
        opacity: root.artOpacity
        layer.enabled: root.onScreen

        BgBlurLayer {
            id: layerA
            front: root._showA
        }

        BgBlurLayer {
            id: layerB
            front: !root._showA
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.cardSurface
        opacity: root.surfaceTint
    }

    component BgBlurLayer: ClippingRectangle {
        id: layer
        property alias art: layerImg.source
        readonly property bool ready: layerImg.status === Image.Ready && layerImg.source != ""
        readonly property bool revealing: fadeIn.running
        property bool front: false

        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        antialiasing: true
        z: front ? 1 : 0
        visible: front || root.transitioning

        function reveal() {
            fadeIn.restart();
        }

        function finishReveal() {
            fadeIn.stop();
            opacity = 1;
        }

        Timer {
            id: promoteDeferred
            interval: 0
            onTriggered: root.promote(layer)
        }

        NumberAnimation {
            id: fadeIn
            target: layer
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.expressiveDurations.expressiveEffects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
        }

        Image {
            id: layerImg
            width: root.blurExtent
            height: width
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.blurDecodeSize, root.blurDecodeSize)
            asynchronous: true
            cache: true
            visible: false
            onStatusChanged: {
                if (status === Image.Ready && source != "")
                    promoteDeferred.restart();
            }
        }

        MultiEffect {
            x: (parent.width - width) / 2
            y: root.pinned ? 0 : (parent.height - height) / 2
            width: layerImg.width
            height: layerImg.height
            source: layerImg
            blurEnabled: root.onScreen
            blurMax: 64
            blur: 0.8
            saturation: -0.2
            brightness: -0.25
        }
    }
}
