import QtQuick

Flow {
    property bool vertical: false

    flow: vertical ? Flow.TopToBottom : Flow.LeftToRight
    spacing: BarMetrics.segmentGap
}
