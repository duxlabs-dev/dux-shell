pragma Singleton

import QtQuick
import Quickshell
import qs.Common
import qs.Modules.ControlCenter

Singleton {
    id: root

    readonly property int defaultGridColumns: 6
    readonly property int minimumGridColumns: 3
    readonly property int maximumGridColumns: 8
    readonly property real preferredColumnWidth: 128
    readonly property real minimumPopoutWidth: 700
    readonly property real popoutWidth: widthFor(false)
    readonly property real weekColumnWidth: 28
    readonly property real popoutWidthWide: popoutWidth + weekColumnWidth + Theme.spacingS
    readonly property real contentPadding: Theme.spacingM + Theme.densityStepXS
    readonly property real contentGap: Theme.spacingM + Theme.densityStepXS
    readonly property real editHeaderHeight: Theme.minimumTouchTargetSize
    readonly property real islandHandleHeight: Theme.spacingXL
    readonly property real islandHandleChromeHeight: islandHandleHeight + contentPadding
    readonly property real islandEditHeaderInset: PopoutMetrics.panelChromeInset + contentPadding
    readonly property real islandEditBottomInset: PopoutMetrics.panelChromeInset + PopoutMetrics.editOverflow
    // Card pills overhang their card by half their height and must stay inside the pages clip.
    readonly property real islandPillOverhang: PopoutMetrics.chromeButtonSize / 2
    readonly property real islandEditChromeHeight: islandEditHeaderInset + editHeaderHeight + contentPadding + islandPillOverhang + islandEditBottomInset
    readonly property real spinnerSize: Theme.iconButtonSize
    readonly property real triggerWidth: CcMetrics.triggerWidth
    readonly property int transitionDuration: CcMetrics.transitionDuration
    readonly property int fadeDuration: CcMetrics.fadeDuration
    readonly property int focusFlashHold: 900
    readonly property int openReadyDeadline: 250
    readonly property int overlayZ: CcMetrics.overlayZ
    readonly property bool animationsEnabled: CcMetrics.animationsEnabled

    function islandChromeHeight(tabBarHeight) {
        return tabBarHeight > 0 ? contentPadding * 2 + tabBarHeight + contentGap : islandHandleChromeHeight;
    }

    function widthFor(weekNumbers, screenWidth, columns = gridColumns) {
        // The floor is sized at comfortable spacing, so it carries the density offsets.
        const floorWidth = minimumPopoutWidth + (gridGap - Theme.spacingS) * (columns - 1) + (contentPadding - Theme.spacingM) * 2;
        const panelWidth = Math.max(floorWidth, preferredColumnWidth * columns + gridGap * (columns - 1) + contentPadding * 2);
        const extra = weekNumbers ? weekColumnWidth + Theme.spacingS : 0;
        if (!Number.isFinite(screenWidth) || screenWidth <= 0)
            return panelWidth + extra;
        const available = Math.max(0, screenWidth - Theme.spacingL * 2);
        return Math.min(available, panelWidth + extra);
    }

    function contentWidthFor(weekNumbers, columns = gridColumns) {
        return widthFor(weekNumbers, undefined, columns) - contentPadding * 2;
    }

    readonly property string overviewId: "overview"
    readonly property int maximumGridRows: 8
    readonly property int maximumCardRows: 64
    readonly property int minimumTabRows: 4
    readonly property int defaultTabRows: 5
    property var panelPreview: null

    function clampColumns(value) {
        return Math.max(minimumGridColumns, Math.min(maximumGridColumns, Math.round(Number(value) || defaultGridColumns)));
    }

    function clampRows(value) {
        return Math.max(minimumTabRows, Math.min(maximumGridRows, Math.round(Number(value) || minimumTabRows)));
    }

    function storedPanelColumns(id) {
        const value = Number(SettingsData.dashOptions?.[id]?.panelColumns);
        return Number.isFinite(value) && value > 0 ? clampColumns(value) : 0;
    }

    function storedPanelRows(id) {
        const value = Number(SettingsData.dashOptions?.[id]?.panelRows);
        return Number.isFinite(value) && value > 0 ? clampRows(value) : 0;
    }

    function panelColumnsFor(id) {
        if (panelPreview?.id === id)
            return panelPreview.columns;
        return storedPanelColumns(id) || defaultGridColumns;
    }

    function panelFloorRowsFor(id) {
        if (panelPreview?.id === id)
            return panelPreview.rows;
        return storedPanelRows(id) || defaultRowsFor(id);
    }

    function defaultRowsForTab(tab) {
        return tab?.sizeToContent === true ? minimumTabRows : defaultTabRows;
    }

    function defaultRowsFor(id) {
        return defaultRowsForTab(DashRegistry.entry(id)?.tab);
    }

    function panelRowsFor(id, contentHeight = 0) {
        return Math.max(panelFloorRowsFor(id), rowsForHeight(contentHeight));
    }

    function defaultPanelRows(id, contentRows) {
        return Math.max(defaultRowsFor(id), contentRows);
    }

    function panelRowsToStore(id, rows, contentRows) {
        if (rows < defaultRowsFor(id) || rows > defaultPanelRows(id, contentRows))
            return rows;
        return defaultRowsFor(id);
    }

    function panelHeightFor(id, contentHeight = 0) {
        return heightForRows(panelRowsFor(id, contentHeight));
    }

    function rowsForHeight(height) {
        return Math.max(minimumTabRows, Math.ceil((height + gridGap) / (gridRowUnit + gridGap)));
    }

    function columnCapFor(screenWidth, weekNumbers) {
        if (!Number.isFinite(screenWidth) || screenWidth <= 0)
            return maximumGridColumns;
        const extra = weekNumbers ? weekColumnWidth + Theme.spacingS : 0;
        const available = screenWidth - Theme.spacingL * 2 - extra - contentPadding * 2;
        return Math.max(minimumGridColumns, Math.min(maximumGridColumns, Math.floor((available + gridGap) / (preferredColumnWidth + gridGap))));
    }

    function rowCapFor(availableHeight) {
        return Math.max(minimumTabRows, Math.floor((availableHeight + gridGap) / (gridRowUnit + gridGap)));
    }

    function heightForRows(rows) {
        return rows * gridRowUnit + (rows - 1) * gridGap;
    }

    readonly property int gridColumns: panelColumnsFor(overviewId)
    // Cells ignore density so saved layouts and art sizes hold; only the gaps step.
    readonly property real gridRowUnit: 96
    readonly property real gridGap: CcMetrics.gridGap
    readonly property real tabMinHeight: heightForRows(minimumTabRows)
    readonly property real tabDefaultHeight: heightForRows(defaultTabRows)
    readonly property real cardRadius: Theme.cornerRadius
    readonly property real surfaceRadius: Theme.cornerRadiusXL
    readonly property real mutedAlpha: 0.72
    readonly property color cardColor: Theme.foregroundColor(Theme.cardSurface, false)
    readonly property color chipColor: Theme.foregroundColor(Theme.chipSurface, false)
    readonly property real optionSheetWidth: 440

    readonly property real avatarSize: Theme.buttonHeightM
    readonly property real avatarSizeHero: 72

    readonly property real tileTrendRatio: 0.45
    readonly property real tileTrendFillAlpha: 0.1
    readonly property real tileValueSizeCompact: Math.round((Theme.fontSizeXXLarge + Theme.fontSizeXLarge) / 2)
    readonly property real gaugeSize: Theme.buttonHeightXS
    readonly property real gaugeSizeHero: CcMetrics.baseIconBoxSize
    readonly property real gaugeStroke: 3
    readonly property real gaugeGap: Theme.spacingXXS
    readonly property real batteryMeterThickness: 28
    readonly property real batteryMeterThicknessHero: 40
    readonly property real batteryMeterThicknessCompact: 20

    readonly property real weatherCompactIconRatio: 0.4
    readonly property real weatherTempSize: Theme.fontSizeXXLarge
    readonly property real weatherChipSize: CcMetrics.baseIconBoxSize

    readonly property real meterBarThickness: Theme.spacingM
    readonly property real overviewPlayWidth: 64
    readonly property int meterDuration: fadeDuration
    readonly property real cpuWarnPercent: 60
    readonly property real cpuCriticalPercent: 80
    readonly property real tempWarnDegrees: 69
    readonly property real tempCriticalDegrees: 85
    readonly property real memoryWarnPercent: 75
    readonly property real memoryCriticalPercent: 90
    readonly property real diskWarnPercent: 85
    readonly property real diskCriticalPercent: 95

    readonly property real overviewArtFrame: gridRowUnit
    readonly property real overviewArtHero: gridRowUnit * 1.5 + Theme.spacingL
    readonly property real overviewSeekHeight: Theme.sliderTrackHeightS
    readonly property real overviewSeekExpressiveHeight: 20
    readonly property real overviewSeekLineWidth: 3
    readonly property real overviewSeekAmplitude: 1.4
    readonly property real overviewSeekWavelength: 18
    readonly property real overviewSeekHandleSize: 12
    readonly property real overviewSeekHandleDragWidth: 4
    readonly property real overviewSeekHandleDragHeight: 20
    readonly property real overviewSeekHandleGap: 5
    readonly property real overviewSideButtonSize: Theme.iconButtonSize
    readonly property real overviewPlaySize: Theme.iconButtonSize
    readonly property real overviewTransportWidth: overviewPlayWidth + (overviewSideButtonSize + Theme.spacingXS) * 2
    readonly property int overviewPositionPollInterval: 300

    readonly property real monthNavSize: Theme.buttonHeightXS
    readonly property real monthNavIconSize: Theme.iconSizeSmall
    readonly property real eventRowMinHeight: 48
    readonly property real eventAccentWidth: 3
    readonly property real eventActionSize: Theme.buttonHeightXS
    readonly property real eventActionIconSize: Theme.iconSizeSmall
    readonly property real taskInputHeight: Theme.buttonHeightS
    readonly property real sheetWidth: 400

    readonly property real mediaCardMargin: Theme.spacingL
    readonly property real mediaArtSize: 150
    readonly property real mediaArtSizeDash: 336
    readonly property real mediaArtSizeMaterial: 200
    readonly property real mediaInnerRadius: Math.max(Theme.cornerRadiusXS, surfaceRadius - mediaCardMargin - Theme.layerOutlineWidth)
    readonly property real mediaArtSoftRadiusRatio: 0.3
    readonly property real mediaArtPlaceholderIcon: Theme.buttonHeightM
    readonly property real mediaArtColumnRatio: 0.5
    readonly property real mediaArtLyricsScale: 0.88
    readonly property int mediaArtRotationDuration: 30000
    readonly property real mediaSeekbarHeight: 22
    readonly property real mediaSeekbarHandleSize: 16
    readonly property real mediaSeekbarHandleDragWidth: 5
    readonly property real mediaSeekbarHandleDragHeight: 28
    readonly property real mediaSeekbarHandleGap: 7
    readonly property real mediaSeekbarExpressiveHeight: 30
    readonly property real mediaSeekbarExpressiveLineWidth: 4
    readonly property real mediaSeekbarExpressiveAmplitude: 1.8
    readonly property real mediaSeekbarExpressiveWavelength: 22
    readonly property real mediaTransportMaxHeight: 70
    // Material's shared axis transition: 30dp of travel, with the outgoing side gone by 35% of it.
    readonly property real mediaSheetSlideDistance: 30
    readonly property real mediaSheetFadeThreshold: 0.35
    readonly property real mediaSheetSettleProgress: 0.002
    readonly property var mediaTitleFontAxes: ({
            "wght": 700,
            "wdth": 25,
            "ROND": 100,
            "GRAD": 100
        })
    readonly property real mediaPlayWidthRatio: 2
    readonly property real mediaTransportPressScale: 1.2
    readonly property real mediaDeviceNameWidthRatio: 0.42
    readonly property real accentSelectedAlpha: 0.2
    readonly property real groupIdleAlpha: 0.1
    readonly property int mediaPositionPollInterval: 1000
    readonly property int mediaVolumeEchoTimeout: 1500
    readonly property int mediaTransitionGraceInterval: 3000
    readonly property int mediaPlayerLossGraceInterval: 1500
    readonly property real mediaTextScrollSpeed: 40
    readonly property int mediaTextScrollStep: 30
    readonly property int mediaLyricsRequestTimeout: 16000
    readonly property int mediaLyricsLoadingDelay: 300
    readonly property real mediaLyricsPositionTolerance: 0.05
    readonly property real mediaLyricsWholeSecondSlack: 0.005
    readonly property int mediaLyricsPositionProbeInterval: 5000
    readonly property real mediaLyricsPositionProbeDrift: 1.5
    readonly property real mediaLyricsPositionProbeThreshold: 1
    readonly property int mediaLyricsPositionSettleInterval: 1000
    readonly property real mediaLyricsTrackStartSlack: 5
    readonly property int mediaLyricsRestartHold: 1500
    readonly property real lyricsLineInactiveScale: 0.8
    readonly property real lyricsLineInactiveAlpha: 0.4
    readonly property real lyricsRestAlpha: 0.35
    // The sweep's soft edge as a share of the cue it crosses, and its floor in pixels.
    readonly property real lyricsSweepFeather: 0.1
    readonly property real lyricsSweepFeatherMin: 6
    readonly property int lyricsLineFadeDuration: lyricsTrackMoveDuration
    readonly property int lyricsLineScaleDuration: lyricsTrackMoveDuration
    readonly property int lyricsLineLinger: 500
    // Seconds before a line starts that the track moves it into the centre.
    readonly property real lyricsLineLeadIn: 0.25
    // A clock that steps back less than this right after the centre advanced keeps the new row.
    readonly property real lyricsFollowBackstepSlack: 1.5
    readonly property int lyricsTrackMoveDuration: 500
    // A critically damped spring settles in about ten time constants, so a long scroll lands with the line move.
    readonly property real lyricsScrollRate: 10000 / lyricsTrackMoveDuration
    readonly property real lyricsScrollStiffness: lyricsScrollRate * lyricsScrollRate
    readonly property real lyricsScrollDamping: 2 * lyricsScrollRate
    // Below half a pixel the rounded position no longer moves, so the spring stops there.
    readonly property real lyricsScrollSettleDistance: 0.5
    readonly property real lyricsScrollSettleSpeed: 10
    readonly property int lyricsTrackPushStep: 20
    readonly property int lyricsTrackMaxPush: 5
    readonly property var lyricsTrackCurve: [0.25, 0.7, 0.2, 1, 1, 1]
    readonly property real lyricsBreakGap: 5
    readonly property real lyricsBreakIndicatorScale: 1.2
    readonly property real lyricsEdgeFadeRatio: 0.2
    readonly property real lyricsEdgeFadeMax: Theme.spacingXL * 2
    readonly property real lyricsLeadHeightDivisor: 12
    readonly property real lyricsLeadWidthDivisor: 11
    readonly property int wheelNotch: 120

    readonly property int dailyVisibleCount: 7
    readonly property int hourlyVisibleCount: 5
    readonly property int hourlyVisibleCountDense: 10
    readonly property int chartHourlyCount: 8
    readonly property real forecastMinHeight: Theme.listItemTwoLineHeight * 3
    readonly property real chartDotRadius: 3
    readonly property int wallpaperColumnsMin: 3
    readonly property int wallpaperColumnsMax: 6
    readonly property int wallpaperRowsMin: 2
    readonly property int wallpaperRowsMax: 5
    readonly property real carouselItemRatio: 0.56
    readonly property real carouselAspect: 0.85
    readonly property real carouselOverlap: 0.52
    readonly property real carouselSideScale: 0.76
    readonly property real carouselSideAlpha: 0.45
    readonly property real carouselAngle: 32
    readonly property real carouselBackdropAlpha: 0.16
    readonly property real wallpaperThumbRadius: Theme.cornerRadiusM
    readonly property int wallpaperThumbCache: 256
    readonly property real wallpaperControlSize: Theme.buttonHeightXS
    readonly property real wallpaperControlIconSize: Theme.iconSizeMedium
    readonly property real wallpaperFilenameHeight: Theme.iconSizeMedium
    readonly property real wallpaperFooterHeight: wallpaperControlSize + wallpaperFilenameHeight
    readonly property real wallpaperSearchWidth: 190
    readonly property real wallpaperSmallButtonSize: 28
    readonly property real wallpaperOverlayBottomMargin: wallpaperFooterHeight + Theme.spacingXS
    readonly property real pageJumpWidth: CcMetrics.menuMinWidth
    readonly property int searchDebounce: 60
}
