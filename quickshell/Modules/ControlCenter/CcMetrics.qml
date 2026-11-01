pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Services

Singleton {
    readonly property real sheetWidthDefault: sheetWidthFor(defaultColumns)
    readonly property int defaultColumns: 8
    readonly property int minimumColumns: 6
    readonly property real sheetPadding: PopoutMetrics.contentPadding
    readonly property real columnWidth: tileHeight
    readonly property real gridStep: 0.5
    property int columnPreview: 0
    readonly property int gridColumns: columnPreview > 0 ? columnPreview : clampColumns(SettingsData.controlCenterColumns)

    function clampColumns(value) {
        const columns = Math.round(Number(value));
        if (!Number.isFinite(columns) || columns <= 0)
            return defaultColumns;
        return Math.max(minimumColumns, columns);
    }

    function columnCapFor(availableWidth) {
        return Math.max(1, Math.floor((availableWidth - sheetPadding * 2 + gridGap) / (columnWidth + gridGap)));
    }

    function rowCapFor(availableHeight, cellHeight = gridRowUnit) {
        return Math.max(1, Math.floor((availableHeight + gridGap) / (cellHeight + gridGap)));
    }

    function sheetWidthFor(columns) {
        return sheetPadding * 2 + columns * columnWidth + (columns - 1) * gridGap;
    }

    function pillRadius(width, height) {
        if (Theme.pillControls)
            return Theme.fullRadius(width, height);
        return Math.min(Theme.cornerRadiusL, width / 2, height / 2);
    }
    readonly property real maxHeightInset: 100
    // Short-grid floors scale with the row unit, or compact would pad small layouts back out.
    readonly property int minimumRows: 4
    readonly property real minHeight: sheetPadding * 2 + gridRowUnit * minimumRows
    readonly property real islandInset: Theme.spacingXS
    readonly property real fallbackScreenHeight: 1080
    readonly property real triggerWidth: 80

    // Density-free bases for Dash.
    readonly property real baseTileHeight: Theme.minimumTouchTargetSize + Theme.spacingS * 2
    readonly property real baseIconBoxSize: Theme.minimumTouchTargetSize * iconScale

    readonly property bool dense: Theme.densityLevel < -1
    readonly property real touchTarget: Math.max(Theme.buttonHeightXS + Theme.spacingXS, Theme.minimumTouchTargetSize + Theme.densityStepM)
    readonly property real tileHeight: baseTileHeight + Theme.densityStepM
    // Dense floors the touch target, so one-row tiles give up padding instead.
    readonly property real tilePadding: (tileHeight - touchTarget) / 2
    readonly property real tallTilePadding: dense ? Theme.spacingS : Theme.spacingM
    readonly property real gridRowUnit: tileHeight
    readonly property real expandedTileMinWidth: columnWidth * 3 + gridGap * 2
    readonly property real sliderRowHeight: touchTarget
    readonly property real stripTrackHeight: Theme.buttonHeightXS + Theme.densityStepS
    readonly property real stripHandleHeight: stripTrackHeight + Theme.sliderHandleGap * 2
    readonly property real gridGap: Math.max(Theme.spacingXS + Theme.spacingXXS, Theme.spacingS + Theme.densityStepXS)
    // Keeps a half-row tile's icon box at buttonHeightXS at every density.
    readonly property real smallTilePadding: (touchTarget - Theme.buttonHeightXS) / 2
    readonly property real iconScale: SettingsData.controlCenterIconScale
    readonly property real tileIconSize: (dense ? Theme.iconSizeMedium : Theme.iconSizeLarge) * iconScale
    readonly property real iconBoxSize: touchTarget * iconScale
    readonly property real tileActiveRadius: Theme.scaledRadius(24, tileHeight / 2)
    readonly property real tallTileRadius: Theme.cornerRadiusXL
    readonly property real iconBoxActiveRadius: Theme.cornerRadiusL
    readonly property real iconBoxIconSize: (dense ? Theme.iconSizeMedium : Theme.iconSize) * iconScale
    readonly property real tallMeterThickness: 28
    readonly property real pillMeterThickness: Math.round(18 * iconScale)
    readonly property real tileTextGap: Theme.spacingM
    // Compact and below shrink rows, so labels drop a font step to fit.
    readonly property bool denseTileText: Theme.densityLevel < 0
    readonly property real smallRowHeight: Math.min(iconBoxSize, tileHeight)
    readonly property real trashSwallowScale: 0.6
    // Joined to the sheet, whose own padding separates the buttons from the grid.
    readonly property real editActionsHeight: Theme.iconButtonSize + sheetPadding
    // Room around the popout surface for the edit chrome and action strip.
    readonly property real editOverflow: Math.max(PopoutMetrics.editOverflow * 2, editActionsHeight)
    // The island clips its faces, so its actions sit inside the sheet.
    readonly property real islandEditRoom: editActionsHeight + Theme.spacingS
    readonly property real runningAppsIconSize: Theme.iconSize * iconScale
    // The resize corner counts a small tile as this many rows and snaps to the nearer of this and a full row.
    readonly property real smallRowFraction: 0.5
    readonly property real shapeButtonSize: Theme.iconSize
    readonly property real editChromeButtonSize: Theme.iconSize
    // Mirrors DGridEditChrome.contentInset so the options menu anchor keeps the chrome's bounds while the chrome is unloaded.
    readonly property real editChromeInset: Math.max(Theme.minimumTouchTargetSize, editChromeButtonSize) / 2

    readonly property real detailDialogPadding: Theme.spacingS
    readonly property real detailHeaderHeight: Theme.iconButtonSize
    readonly property real detailTitleSize: Theme.fontSizeLarge
    readonly property real detailMinContentHeight: Theme.listItemTwoLineHeight * 3
    readonly property real headerActionSize: Theme.buttonHeightXS
    readonly property real headerActionIconSize: Theme.iconSizeMedium
    readonly property real headerEdgeInset: rowPaddingH - (headerActionSize - headerActionIconSize) / 2
    readonly property real pageHeaderHeight: Theme.fontSizeXXLarge + Math.max(Theme.spacingM, Theme.spacingM * 2 + Theme.densityStepM)
    readonly property real pageTitleSize: Theme.fontSizeXXLarge
    readonly property real detailHeightList: 350
    readonly property real detailHeightBrightness: 400
    readonly property real detailHeightDefault: 250
    readonly property int transitionDuration: Theme.expressiveDurations.expressiveFastSpatial
    readonly property int fadeDuration: Theme.expressiveDurations.expressiveEffects

    readonly property real rowPaddingH: Theme.spacingL
    readonly property real rowPaddingV: (rowHeight - Theme.buttonHeightXS) / 2
    readonly property real rowHeight: Math.max(Theme.buttonHeightXS + Theme.spacingM, Theme.listItemHeight + Theme.densityStepM)
    readonly property real detailContentGap: Theme.spacingS
    readonly property real sectionLabelTopGap: Theme.spacingS
    readonly property real sectionLabelBottomGap: Theme.spacingXS
    readonly property color rowColor: Theme.foregroundColor(Theme.cardSurface)
    readonly property int maxPins: 3
    readonly property real statusDotSize: 8
    readonly property real spinnerStroke: 2
    readonly property real emptyStateIconSize: Theme.iconSizeLarge
    readonly property real emptyStateMinHeight: 100

    readonly property real menuMinWidth: 180
    readonly property real dialogWidth: 320
    readonly property real libraryPanelWidth: 400
    readonly property real libraryPanelHeight: 400
    readonly property real widgetSheetHeightRatio: 0.85
    readonly property real previewSize: 76
    readonly property real configMenuWidth: 260
    readonly property real vpnPopoutListHeight: 200
    readonly property real headerDropdownWidth: 120
    readonly property real rowDropdownWidth: 160
    readonly property real headerPopupWidth: 200
    readonly property real brightnessLowMax: 33
    readonly property int wifiSignalBucket: 25
    readonly property real diskWarnPercent: 75
    readonly property real diskCriticalPercent: 90
    readonly property int dndRefreshInterval: 1000
    readonly property int wifiSignalStrong: 50
    readonly property real brightnessMediumMax: 66
    readonly property real brightnessExponentMin: 1.0
    readonly property real brightnessExponentMax: 2.5
    readonly property real brightnessExponentStep: 0.1
    readonly property int overlayZ: 10000
    readonly property real popupEnterScale: 0.92
    readonly property color dialogColor: Theme.foregroundColor(Theme.hostSurface)
    readonly property bool hideCoveredContent: BlurService.enabled && Theme.connectedSurfaceBlurEnabled && dialogColor.a < 1

    readonly property color tileActiveColor: Theme.ccTileActiveBg
    readonly property color tileActiveContent: Theme.ccTileActiveText
    readonly property color tileInactiveColor: Theme.ccPillInactiveBg
    readonly property color iconBoxInactiveColor: Theme.ccIconBoxInactiveBg
    readonly property color tileInactiveContent: Theme.surfaceText
    readonly property color tileInactiveSubtitle: Theme.surfaceVariantText
    readonly property color tileInactiveIcon: Theme.primary
    readonly property color bareActiveIcon: Theme.primary
    readonly property real quickBarePadding: Theme.spacingL
    readonly property real quickBareWidth: iconBoxIconSize + quickBarePadding
    readonly property real quickTileGap: Theme.spacingXS

    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None

    // The 1.6 detail heights: a detail never shows less than it did there, whatever the grid leaves free.
    function detailHeightFloor(section, pluginHeight) {
        if (section.startsWith("plugin_"))
            return pluginHeight > 0 ? pluginHeight : detailHeightDefault;
        if (section.startsWith("brightnessSlider_"))
            return detailHeightBrightness;
        switch (section) {
        case "wifi":
        case "network":
        case "bluetooth":
        case "builtin_vpn":
        case "builtin_tailscale":
            return detailHeightList;
        default:
            return detailHeightDefault;
        }
    }
}
