import QtQuick
import QtQuick.Window
import qs.Services
import "../../Common/WidgetPlacement.js" as Placement

Item {
    id: root

    required property Item sourceItem
    property string renderKey: ""
    property bool ready: false
    property bool busy: false
    property string capturedKey: ""
    property var capture: null
    readonly property size sourceSize: Qt.size(sourceItem.width, sourceItem.height)
    readonly property real sampleScale: LockPlacementService.sampleSize / Math.max(1, sourceItem.width, sourceItem.height)
    readonly property int sampleWidth: Math.max(1, Math.round(sourceItem.width * sampleScale))
    readonly property int sampleHeight: Math.max(1, Math.round(sourceItem.height * sampleScale))
    readonly property bool sourceVisible: sourceItem.visible && (sourceItem.Window.window?.visible ?? false)

    signal sampled(var luminances, int sampleWidth, int sampleHeight)
    signal failed

    onRenderKeyChanged: schedule.restart()
    onReadyChanged: schedule.restart()
    onSourceVisibleChanged: schedule.restart()
    onSourceSizeChanged: schedule.restart()
    Component.onCompleted: schedule.restart()

    function finish() {
        if (capture)
            canvas.unloadImage(capture.url);
        capture = null;
        busy = false;
        if (capturedKey !== renderKey)
            schedule.restart();
    }

    Timer {
        id: schedule
        interval: 0
        onTriggered: {
            if (!root.ready || !root.sourceVisible || root.busy || !canvas.available || root.sourceItem.width <= 0 || root.sourceItem.height <= 0)
                return;
            root.capturedKey = root.renderKey;
            root.busy = true;
            const started = root.sourceItem.grabToImage(result => {
                if (!root.ready || root.capturedKey !== root.renderKey) {
                    root.finish();
                    return;
                }
                root.capture = result;
                canvas.loadImage(result.url);
                if (canvas.isImageLoaded(result.url))
                    canvas.requestPaint();
            }, Qt.size(root.sampleWidth, root.sampleHeight));
            if (!started) {
                root.finish();
                root.failed();
            }
        }
    }

    Canvas {
        id: canvas
        width: root.sampleWidth
        height: root.sampleHeight
        opacity: 0
        onAvailableChanged: schedule.restart()
        onImageLoaded: requestPaint()
        onPaint: {
            if (!root.capture)
                return;
            if (isImageError(root.capture.url)) {
                root.finish();
                root.failed();
                return;
            }
            if (!root.ready || root.capturedKey !== root.renderKey) {
                root.finish();
                return;
            }
            if (!isImageLoaded(root.capture.url))
                return;
            const context = getContext("2d");
            context.clearRect(0, 0, width, height);
            context.drawImage(root.capture.url, 0, 0, width, height);
            const pixels = context.getImageData(0, 0, width, height).data;
            const luminances = [];
            for (let i = 0; i < pixels.length; i += 4)
                luminances.push(Placement.luminance(pixels[i] / 255, pixels[i + 1] / 255, pixels[i + 2] / 255));
            context.clearRect(0, 0, width, height);
            root.finish();
            root.sampled(luminances, width, height);
        }
    }
}
