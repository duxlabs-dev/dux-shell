import QtQuick
import qs.Common

// Progress over time of one animation; the dashed line is the end position, a spring above it bounces.
Canvas {
    id: root

    property var samples: [1]
    property int mark: -1
    property color lineColor: Theme.primary
    property color guideColor: Theme.outline

    onSamplesChanged: requestPaint()
    onMarkChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const n = samples.length;
        if (n < 2 || width <= 0)
            return;
        const pad = Theme.spacingM;
        const top = Math.max(1.05, ...samples);
        const X = i => pad + i / (n - 1) * (width - pad * 2);
        const Y = v => height - pad - v / top * (height - pad * 2);

        ctx.strokeStyle = guideColor;
        ctx.lineWidth = 1;
        ctx.setLineDash([4, 4]);
        ctx.beginPath();
        ctx.moveTo(pad, Y(1));
        ctx.lineTo(width - pad, Y(1));
        ctx.stroke();
        ctx.setLineDash([]);

        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2.5;
        ctx.beginPath();
        // One point per pixel is enough for the eye and keeps a 3 s spring cheap to draw
        const step = Math.max(1, Math.floor(n / width));
        ctx.moveTo(X(0), Y(samples[0]));
        for (let i = step; i < n; i += step)
            ctx.lineTo(X(i), Y(samples[i]));
        ctx.lineTo(X(n - 1), Y(samples[n - 1]));
        ctx.stroke();

        if (mark < 0)
            return;
        ctx.fillStyle = lineColor;
        ctx.beginPath();
        ctx.arc(X(mark), Y(samples[mark]), 5, 0, Math.PI * 2);
        ctx.fill();
    }
}
