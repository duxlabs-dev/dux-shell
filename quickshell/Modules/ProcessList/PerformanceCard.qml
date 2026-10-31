import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Rectangle {
    id: card

    property bool compact: false
    property string title: ""
    property string icon: ""
    property string value: ""
    property string subtitle: ""
    property color accentColor: Theme.primary
    property var history: []
    property var history2: null
    property real maxValue: 100
    property bool showSecondary: false
    property string extraInfo: ""
    property color extraInfoColor: Theme.surfaceVariantText

    implicitHeight: cardContent.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadiusL
    property bool floatingWindow: (typeof root !== "undefined" && typeof root.isFloatingWindowSurface === "boolean") ? root.isFloatingWindowSurface : Theme.isFloatingWindow(card)
    color: Theme.foregroundColor(Theme.cardSurface, floatingWindow)
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium

    Connections {
        target: DgopService
        enabled: card.visible
        function onStatsUpdated() {
            graphCanvas.requestPaint();
        }
    }

    onAccentColorChanged: graphCanvas.requestPaint()

    Canvas {
        id: graphCanvas
        anchors.fill: parent
        anchors.topMargin: card.compact ? Theme.iconButtonSize : 0
        renderStrategy: Canvas.Cooperative

        property var hist: card.history
        property var hist2: card.history2

        onHistChanged: requestPaint()
        onHist2Changed: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);

            if (!hist || hist.length < 2)
                return;

            ctx.beginPath();
            ctx.roundedRect(0, -anchors.topMargin, card.width, card.height, card.radius, card.radius);
            ctx.clip();

            let max = card.maxValue;
            if (max <= 0) {
                max = 1;
                for (let k = 0; k < hist.length; k++)
                    max = Math.max(max, hist[k]);
                if (hist2) {
                    for (let l = 0; l < hist2.length; l++)
                        max = Math.max(max, hist2[l]);
                }
                max *= 1.1;
            }

            const c = card.accentColor;
            const grad = ctx.createLinearGradient(0, 0, 0, height);
            grad.addColorStop(0, Theme.withAlpha(c, 0.25));
            grad.addColorStop(1, Theme.withAlpha(c, 0.02));

            ctx.fillStyle = grad;
            ctx.beginPath();
            ctx.moveTo(0, height);
            for (let i = 0; i < hist.length; i++) {
                const x = (width / (DgopService.historySize - 1)) * i;
                const y = height - (hist[i] / max) * height * 0.8;
                ctx.lineTo(x, y);
            }
            ctx.lineTo((width / (DgopService.historySize - 1)) * (hist.length - 1), height);
            ctx.closePath();
            ctx.fill();

            ctx.strokeStyle = Theme.withAlpha(c, 0.8);
            ctx.lineWidth = 2;
            ctx.beginPath();
            for (let j = 0; j < hist.length; j++) {
                const px = (width / (DgopService.historySize - 1)) * j;
                const py = height - (hist[j] / max) * height * 0.8;
                j === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
            }
            ctx.stroke();

            if (hist2 && hist2.length >= 2 && card.showSecondary) {
                ctx.strokeStyle = Theme.withAlpha(c, 0.4);
                ctx.lineWidth = 1.5;
                ctx.setLineDash([4, 4]);
                ctx.beginPath();
                for (let m = 0; m < hist2.length; m++) {
                    const sx = (width / (DgopService.historySize - 1)) * m;
                    const sy = height - (hist2[m] / max) * height * 0.8;
                    m === 0 ? ctx.moveTo(sx, sy) : ctx.lineTo(sx, sy);
                }
                ctx.stroke();
                ctx.setLineDash([]);
            }
        }
    }

    ColumnLayout {
        id: cardContent
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingXS

        RowLayout {
            id: cardHeader
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DIcon {
                name: card.icon
                size: Theme.iconSize
                color: card.accentColor
            }

            StyledText {
                id: titleLabel
                text: card.title
                font.pixelSize: card.compact ? Theme.fontSizeSmall : Theme.fontSizeLarge
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: card.extraInfo
                font.pixelSize: Theme.fontSizeSmall
                color: card.extraInfoColor
                visible: card.extraInfo.length > 0
            }
        }

        Item {
            Layout.fillHeight: true
            visible: !card.compact
        }

        NumericText {
            Layout.maximumWidth: card.width - Theme.spacingM * 2
            elide: Text.ElideRight
            text: card.value
            font.pixelSize: Theme.fontSizeXLarge
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            visible: !card.compact
            text: card.subtitle
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
