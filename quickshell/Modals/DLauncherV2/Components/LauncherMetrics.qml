pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    // Dense floor: the 36px row preview needs the room
    readonly property real rowHeight: Math.max(Theme.listItemHeight + Theme.densityStepM, Theme.buttonHeightS + Theme.spacingXS)
    readonly property real rowPadding: Theme.spacingL + Theme.densityStepS
    // Never below the hairline gap, so rows never touch
    readonly property real rowGap: Theme.groupedListGap + Math.max(0, Theme.densityStepXS)
    readonly property real tileSize: Theme.launcherTileSize
    readonly property real tileGap: Theme.spacingXS
    readonly property real tileLabelHeight: Theme.spacingXL
    readonly property real tileLabelBlockHeight: tileLabelMetrics.lineSpacing * 2
    readonly property real tileImageRatio: Theme.launcherImageRatio
    readonly property real tileMinHeight: tileGap + Theme.spacingXS * 2 + gridIconSize + Theme.spacingS + tileLabelBlockHeight
    // Grid cells follow the list pitch so every density fits the same whole rows
    readonly property real gridDensityScale: (rowHeight + rowGap) / (Theme.listItemHeight + Theme.groupedListGap)
    readonly property real pillHeight: Theme.fieldHeightLarge
    readonly property real sectionHeight: Math.max(Theme.buttonHeightXXS, Theme.buttonHeightXS + Theme.densityStepS)
    readonly property real resultsGap: Theme.spacingXS
    readonly property real sectionBand: sectionHeight + resultsGap
    readonly property real headerButtonSize: Math.min(Theme.buttonHeightXS, sectionHeight)
    readonly property real headerInset: (headerButtonSize - Theme.iconSizeSmall) / 2
    readonly property real iconSize: Theme.avatarSize + Theme.densityStepS
    readonly property real gridIconSize: Theme.iconSizeLarge + Theme.spacingL
    readonly property real previewWidth: Theme.listItemHeight
    readonly property real previewHeight: Theme.avatarSize
    readonly property real footerHeight: Math.max(Theme.buttonHeightXXS, Theme.buttonHeightXS + Theme.densityStepS)
    readonly property real chromeHeight: Theme.spacingM + pillHeight + resultsGap
    readonly property real modeChipHeight: Theme.buttonHeightXS - Theme.spacingXS * 2
    readonly property int maxVisibleRows: Theme.launcherMaxVisibleRows
    // Reserved so the bottom fade never lands on a row
    readonly property real fadeLength: Theme.spacingXL
    readonly property real maxResultsHeight: maxVisibleRows * (rowHeight + rowGap) + sectionBand + fadeLength
    readonly property real minSearchWidth: Theme.fieldDefaultWidth
    readonly property int selectionDuration: Theme.shorterDuration
    readonly property real screenMargin: Theme.launcherScreenMargin
    readonly property real spotlightWidth: Theme.launcherWidthWide
    readonly property real spotlightTopFraction: 0.33
    readonly property real spotlightInset: Theme.spacingM
    // The footerless island sheet adds ResultsList's spacingS below its spacingM margin.
    readonly property real islandEdgeInset: Theme.spacingS

    FontMetrics {
        id: tileLabelMetrics
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Theme.fontWeightMedium
        font.family: Theme.fontFamily
    }

    function sizeWidth(size) {
        switch (size) {
        case "micro":
            return Theme.launcherWidthMicro;
        case "medium":
            return Theme.launcherWidthWide;
        case "large":
            return Theme.launcherWidthLarge;
        default:
            return Theme.launcherWidthDefault;
        }
    }

    function sizeRows(size) {
        switch (size) {
        case "micro":
            return 6;
        case "medium":
            return 10;
        case "large":
            return 13;
        default:
            return 8;
        }
    }

    function footerShown(size) {
        return size !== "micro" && SettingsData.dankLauncherV2ShowFooter;
    }

    // edgeInset: the painted border lifts the footer, which would otherwise eat into the rows.
    // Footerless results keep a spacingM bottom margin.
    function sizeHeight(size, edgeInset = 0, footer = true) {
        return chromeHeight + (footer ? footerHeight : Theme.spacingM) + edgeInset + sectionBand + sizeRows(size) * (rowHeight + rowGap) + fadeLength;
    }

    function spotlightRadius(width) {
        return Theme.fullRadius(width, pillHeight);
    }

    function spotlightBottomRadius(width, contentHeight) {
        const pill = spotlightRadius(width);
        const t = Math.max(0, Math.min(1, (contentHeight - pillHeight) / Theme.windowRadius));
        return pill + (Theme.windowRadius - pill) * t;
    }

    function spotlightY(screenHeight, insetTop, insetBottom) {
        const usable = Math.max(pillHeight, screenHeight - insetTop - insetBottom);
        const preferred = insetTop + Math.max(0, usable * spotlightTopFraction - pillHeight / 2);
        const maxY = Math.max(insetTop, screenHeight - insetBottom - pillHeight);
        return Math.max(insetTop, Math.min(preferred, maxY));
    }
}
