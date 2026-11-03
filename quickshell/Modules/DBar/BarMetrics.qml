pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.DCommon.Common as DCommon

Singleton {
    readonly property real compactPillThickness: Theme.barHeight - Theme.iconSizeMedium
    readonly property real pressedRadius: Theme.cornerRadiusS
    readonly property real segmentInnerRadius: Theme.cornerRadiusS
    readonly property real segmentPressedInnerRadius: Theme.cornerRadiusXS
    readonly property real segmentGap: Theme.groupedListGap
    readonly property real pillGap: Theme.spacingXS
    readonly property real bareGap: Theme.spacingXXS
    readonly property real iconSlot: Theme.iconSizeSmall + Theme.spacingXXS
    readonly property real indicatorDot: Theme.spacingS - Theme.spacingXXS
    readonly property real badgeSize: Theme.spacingS
    readonly property real badgeInset: Theme.spacingXS
    readonly property real mediaControlSize: Theme.iconSizeMedium
    readonly property real menuRowHeight: DCommon.Style.menuRowHeight
    readonly property real menuPadding: DCommon.Style.menuPadding
    readonly property real menuItemRadius: Theme.cornerRadiusS
    readonly property real popoutRowHeight: Math.max(Theme.listItemHeight + Theme.densityStepM, Theme.buttonHeightS + Theme.spacingXS)
    readonly property real popoutRowTwoLineHeight: Theme.listItemTwoLineHeight + Theme.densityStepM
    readonly property var elevationLevel: Theme.elevationLevel2

    function pillRadius(thickness, style) {
        if (style === "flat")
            return Math.min(Theme.cornerRadiusS, thickness / 2);
        if (thickness < compactPillThickness)
            return Math.min(Theme.cornerRadiusM, thickness / 2);
        return Theme.pillControls ? Theme.fullRadius(thickness, thickness) : Math.min(Theme.cornerRadiusL, thickness / 2);
    }

    function cornerRadius(thickness, style, joined, pressProgress) {
        const resting = joined ? Math.min(segmentInnerRadius, thickness / 2) : pillRadius(thickness, style);
        if (!Theme.shapeMorph)
            return resting;
        const pressed = Math.min(resting, joined || style === "flat" ? segmentPressedInnerRadius : pressedRadius);
        return Math.max(0, resting + (pressed - resting) * Math.max(0, Math.min(1, pressProgress)));
    }

    function widgetStyle(barConfig) {
        return barConfig?.widgetStyle ?? "pills";
    }

    // workspace indicator extents as fractions of the widget thickness: along the bar (compact/active) and across it (slim/activeSlim)
    readonly property var indicatorRatios: ({
            "pills": {
                "compact": 0.7,
                "active": 1.05,
                "slim": 0.5,
                "activeSlim": 0.5
            },
            "dots": {
                "compact": 0.5,
                "active": 0.6,
                "slim": 0.5,
                "activeSlim": 0.6
            },
            "lines": {
                "compact": 0.7,
                "active": 1.6,
                "slim": 0.12,
                "activeSlim": 0.2
            },
            "cards": {
                "compact": 0.75,
                "active": 0.9,
                "slim": 0.5,
                "activeSlim": 0.6
            }
        })

    readonly property real indicatorCompactScale: 0.7
    readonly property real indicatorLabelRatio: 0.65
    readonly property real indicatorLabelScale: 1.3
    readonly property real indicatorLabelMin: Math.round(Theme.fontSizeSmall * 0.75)

    function indicatorRatio(style, key, compact) {
        return (indicatorRatios[style] ?? indicatorRatios.pills)[key] * (compact ? indicatorCompactScale : 1);
    }

    // roundness 0..100 is the corner as a share of the half thickness; below 0 follows the theme
    function indicatorRadius(style, thickness, roundness) {
        if (roundness >= 0)
            return thickness / 2 * Math.min(100, roundness) / 100;
        if (style === "cards")
            return Math.min(Theme.cornerRadiusXS, thickness / 2);
        return -1;
    }

    // islandBandFit is the inverse of compactFaceThickness; both read these.
    readonly property real islandFaceBloomSmall: 2
    readonly property real islandFaceBloomLarge: 4
    readonly property real islandLargeFaceCompact: 40
    readonly property real islandMinFace: 16
    readonly property real islandMinBandFace: 20

    function gothRadius(barConfig) {
        if (barConfig?.gothCornerRadiusOverride ?? false)
            return Math.max(0, barConfig.gothCornerRadiusValue ?? SettingsData.barConfigDefault("gothCornerRadiusValue"));
        return Theme.windowRadius;
    }

    function widgetFill(barConfig) {
        const transparency = SettingsData.barWidgetTransparency(barConfig);
        return Theme.widgetBackgroundHasAlpha ? Theme.blendAlpha(Theme.widgetBaseBackgroundColor, transparency) : Theme.withAlpha(Theme.widgetBaseBackgroundColor, transparency);
    }

    function compactFaceThickness(compact) {
        return compact + (compact < islandLargeFaceCompact ? islandFaceBloomSmall : islandFaceBloomLarge);
    }

    function islandBandFit(bandThickness, gap) {
        const fittedGap = Math.max(1, Math.min(gap, Math.floor((bandThickness - islandMinBandFace) / 2)));
        const face = Math.max(islandMinFace, Math.round(bandThickness) - fittedGap * 2);
        const large = face - islandFaceBloomLarge;
        return {
            "gap": fittedGap,
            "compact": large >= islandLargeFaceCompact ? large : Math.min(islandLargeFaceCompact - 1, face - islandFaceBloomSmall)
        };
    }
}
