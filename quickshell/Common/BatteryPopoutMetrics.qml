pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property bool compact: Theme.densityLevel < 0
    readonly property bool dense: Theme.densityLevel < -1
    readonly property real spaciousStep: Math.max(0, Theme.densityLevel) * Theme.spacingXL

    readonly property real pad: PopoutMetrics.contentPadding
    readonly property real gap: dense ? Theme.spacingXS : Theme.spacingS + Theme.spacingXXS + Theme.densityStepXS
    readonly property real tile: Theme.spacingM + Theme.densityStepS
    readonly property real button: Theme.densityLevel > 0 ? Theme.minimumTouchTargetSize : dense ? Theme.buttonHeightXS : Theme.iconButtonSize
    readonly property real powerButton: Theme.buttonHeightM + Theme.densityStepM
    readonly property real row: dense ? Theme.buttonHeightS : Theme.buttonHeightM - Theme.spacingXS + Theme.densityStepS
    readonly property real chip: Theme.densityLevel > 0 ? Theme.buttonHeightXS + Theme.spacingXS : dense ? Theme.buttonHeightXXS : Theme.buttonHeightXS
    readonly property real deviceRing: Theme.buttonHeightM + Theme.spacingL + Theme.densityStepM
    readonly property real compactRing: Theme.buttonHeightXS + Theme.spacingM
    readonly property real compactGlyph: Theme.iconSizeSmall + Theme.spacingXXS
    readonly property real gridGlyph: Theme.iconSize - Theme.spacingXXS
    readonly property real boltCircle: Theme.iconSizeSmall + Theme.spacingS
    readonly property real numberLift: Theme.spacingM + Theme.spacingXXS
    readonly property real compactIconSize: Theme.iconSizeSmall + Theme.spacingXS

    readonly property real heroSmall: Theme.buttonHeightM + (dense ? 0 : Theme.spacingL)
    readonly property real heroRing: 184 + spaciousStep
    readonly property real heroRingBeside: heroRing - Theme.iconButtonSize
    readonly property real cardFill: compact ? heroSmall : 136 + Theme.densityLevel * Theme.spacingXL
    readonly property real smallNumberSize: dense ? Theme.fontSizeXXLarge : Theme.fontSizeDisplay

    readonly property real gaugeStroke: Theme.spacingXS
    readonly property real barStroke: 6
    readonly property real heroStroke: Theme.spacingS
    readonly property real badge: Theme.minimumTouchTargetSize
    readonly property real badgeCut: 1.5
    readonly property real wavelength: 40
    readonly property real waveAmp: 3
    readonly property real waveAmpThin: 2
    readonly property real trackGap: 5
    readonly property real ringGap: Theme.spacingS
    readonly property real hatchPeriod: 10
    readonly property real statsGap: 40
    readonly property int gridMaxColumns: 4
    // The cookie shapes draw into a texture this many times their size, which keeps their edges smooth.
    readonly property int shapeSupersampling: 4

    readonly property real barFillMix: 0.45
    readonly property real selectedShare: 3.5
    readonly property real pressedShare: 1.2
    readonly property real sliderThumbRatio: 1.3
    readonly property real sliderPressScale: 0.85
    readonly property real circlePressScale: 0.9
    readonly property real popScale: 0.7
    readonly property real popRotation: -40
    readonly property real pastLimitShade: 0.28
    readonly property real trackTintAmount: 0.26
    readonly property real ringBadgeTrack: 0.3

    // The wave only shows while charging and away from both ends, where it would read as noise.
    function waveOn(wavy, charging, level) {
        return wavy && charging && !Theme.reduceMotion && level > 10 && level < 95;
    }

    // A spanning last cell ends its row.
    function cornerRadii(index, count, columns, outerTop, outerBottom) {
        const inner = Theme.groupedListInnerRadius;
        const row = Math.floor(index / columns);
        const atStart = index % columns === 0;
        const atEnd = index % columns === columns - 1 || index === count - 1;
        const top = row === 0 ? outerTop : inner;
        const bottom = row === Math.floor((count - 1) / columns) ? outerBottom : inner;
        const left = I18n.isRtl ? atEnd : atStart;
        const right = I18n.isRtl ? atStart : atEnd;
        return {
            topLeft: left ? top : inner,
            topRight: right ? top : inner,
            bottomLeft: left ? bottom : inner,
            bottomRight: right ? bottom : inner
        };
    }
}
