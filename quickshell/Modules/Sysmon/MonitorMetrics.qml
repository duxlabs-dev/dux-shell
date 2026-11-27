pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter
import qs.Modules.DDash

Singleton {
    readonly property real tileTrendRatio: 0.45
    readonly property real tileTrendFillAlpha: 0.1
    readonly property real tileValueSizeCompact: DashMetrics.tileValueSizeCompact
    readonly property int meterDuration: Theme.expressiveDurations.expressiveSlowEffects
    readonly property bool animationsEnabled: CcMetrics.animationsEnabled

    readonly property real wideThreshold: DashMetrics.gridRowUnit * 2
    readonly property real tileMinWidth: 132
    readonly property real tileMinHeight: 124
    readonly property real tileSoloMinWidth: 96
    readonly property real tileSoloMinHeight: 92
    readonly property real processesWidth: 260
    readonly property real processRowHeight: Theme.buttonHeightXS + Theme.spacingXS
    readonly property real headerHeight: Theme.buttonHeightXS
    readonly property real listRowMinHeight: Theme.listItemTwoLineHeight
    readonly property real barThickness: 12
    readonly property real barThicknessExtra: 6
    readonly property real chartMinHeight: 56
    readonly property real chartMinWidth: 132
    readonly property real ringSizeSmall: 76
    readonly property real ringStrokeSmall: 7
    readonly property real ringSizeWide: 84
    readonly property real ringStrokeWide: 8
    readonly property real ringSizeBig: 150
    readonly property real ringStrokeBig: 12
    readonly property real meterThickness: 8
    readonly property real meterThicknessBig: 12
    readonly property real listVisualWidth: 72
    readonly property real listVisualHeight: Theme.buttonHeightXXS
    readonly property real barNameWidth: Theme.buttonHeightXS * 2
    readonly property real barWidth: 10
    readonly property real cardBarThickness: 6
    readonly property real markerSize: 14
    readonly property real bracketDepth: 6
    readonly property real bracketStroke: 1.5
    readonly property real bracketOpacity: 0.7
    readonly property real secondaryFillOpacity: 0.7
    readonly property real scaleFloor: 0.35
    // Bars stand upright once their box is this much taller than wide.
    readonly property real verticalBarsRatio: 1.15

    // Widest text each value kind formats to, full and short, so value columns keep their width as numbers change.
    readonly property var valueSamples: ({
            "pct": "100%",
            "temp": "100°",
            "clock": "0.0 GHz",
            "power": "000 W",
            "rate": "1000.0 MB/s"
        })
    readonly property var shortValueSamples: ({
            "pct": "100%",
            "temp": "100°",
            "clock": "0.0",
            "power": "000 W",
            "rate": "999M"
        })

    // Widest sizes and compact rate the bar widget formats, for the width it reserves.
    readonly property var sizeSamples: ({
            "bytes": "1000.0 MiB",
            "mount": "1000.0G",
            "drive": "1000 GB",
            "compactRate": "888 MB/s"
        })

    // Tile extras only pick how many fit, so they plan on two digits; a rare third one runs into the tile's padding.
    readonly property var extraValueSamples: ({
            "pct": "99%",
            "temp": "99°"
        })

    // The longest sample among the rows' value kinds, so every value column in a widget lines up.
    function widestReserve(rows, short) {
        let best = reserveFor("pct", short);
        for (const r of rows ?? []) {
            for (const v of r.values ?? []) {
                const s = reserveFor(v.kind, short);
                if (s.length > best.length)
                    best = s;
            }
        }
        return best;
    }

    function reserveFor(kind, short, extra) {
        return (extra && short ? extraValueSamples[kind] : undefined) ?? (short ? shortValueSamples : valueSamples)[kind] ?? "";
    }

    function levelColor(level, accent) {
        return level >= 2 ? Theme.error : level === 1 ? Theme.warning : accent;
    }

    readonly property var linePalette: [Theme.primary, Theme.tertiary, Theme.warning, Theme.info, Theme.error, Theme.secondary, Theme.blend(Theme.primary, Theme.error, 0.5), Theme.blend(Theme.tertiary, Theme.info, 0.5)]
}
