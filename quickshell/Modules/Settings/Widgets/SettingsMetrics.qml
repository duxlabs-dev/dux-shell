pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property real sidebarWidth: 336
    readonly property real compactBreakpoint: 700
    readonly property real contentMaxWidth: 920
    readonly property real mediaMaxWidth: 720
    readonly property real windowWidth: 1100
    readonly property real windowHeight: 940
    readonly property real windowMinWidth: 500
    readonly property real windowMinHeight: 400
    readonly property real formDialogWidth: 640
    readonly property real pagePaddingH: Theme.spacingXL + Theme.spacingL
    // Comfortable page padding, for sizes that must not follow density
    readonly property real basePagePaddingV: Theme.spacingXL + Theme.spacingS
    readonly property real pagePaddingV: basePagePaddingV + Theme.densityStepM
    readonly property real paneMargin: Theme.windowInset
    readonly property real panePadding: Theme.spacingXL
    // Scroll containers clip at their bounds, so pages grow by this and inset their content to let focus rings bleed
    readonly property real focusGutter: Theme.focusRingOffset + Theme.focusRingWidth
    readonly property real paneRadius: Theme.cornerRadiusL
    // Centers the page title on the sidebar search field
    readonly property real pageHeaderHeight: Theme.fieldHeightLarge + paneMargin * 2
    readonly property real rowPaddingH: Theme.spacingL + Theme.spacingXS + Theme.densityStepS
    readonly property real rowPaddingV: Theme.spacingL + Theme.densityStepS
    readonly property real rowMinHeight: Math.max(Theme.listItemHeight + Theme.densityStepM, Theme.buttonHeightS + Theme.spacingXS)
    readonly property real rowMinHeightTwoLine: Theme.listItemTwoLineHeight + Theme.densityStepM
    readonly property real cardGap: Theme.spacingL + Theme.densityStepS
    readonly property real rowContentSpacing: Theme.spacingL
    readonly property real sliderButtonBleed: (Theme.iconButtonSize - Theme.iconSizeMedium) / 2
    readonly property real resetChipPaddingH: Theme.spacingM
    readonly property real resetChipPaddingV: Theme.spacingXS
    readonly property real heroPadding: rowPaddingV
    readonly property real heroLeadingSize: Theme.avatarSize
    readonly property real sectionLabelTopGap: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepS)
    readonly property real sectionLabelBottomGap: Theme.spacingM
    readonly property real navIconSize: Theme.avatarSize
    readonly property bool navIconBadges: !Theme.classicStyle
    readonly property bool continuousGroups: Theme.classicStyle
    readonly property real groupGap: continuousGroups ? 0 : Theme.groupedListGap
    readonly property real groupInnerRadius: continuousGroups ? 0 : Theme.groupedListInnerRadius
    // Rows share one frame in a continuous group so Layer outline never doubles up between them
    readonly property real groupEdgeWidth: continuousGroups ? 0 : Theme.layerOutlineWidth
    readonly property real groupFrameWidth: continuousGroups ? Theme.layerOutlineWidth : 0
    readonly property color groupDividerColor: Theme.withAlpha(Theme.outline, SettingsData.sectionDividerOpacity)
    readonly property real navItemMinHeight: rowMinHeight
    readonly property real sidebarGroupGap: Theme.spacingM
    readonly property real searchBarGap: Theme.spacingM
    readonly property real avatarSize: 64
    readonly property real splitDividerHeight: Theme.iconSize
    readonly property real buttonGroupCompactThreshold: 200
    readonly property real choiceCardPreviewRatio: 10 / 16
    readonly property real positionPickerMaxWidth: 360
    readonly property real tileMinWidth: 300
    readonly property real tileGap: Theme.spacingS
    readonly property real wallpaperThumbRatio: 10 / 16
    readonly property int wallpaperThumbCache: 1024
    readonly property int wallpaperGridColumns: 5
    readonly property real wallpaperHeroStackWidth: 520
    readonly property real wallpaperHeroSplit: 0.5
    readonly property real disabledOpacity: 0.38
    readonly property real highlightBlend: 0.2
    readonly property real bannerTextMinWidth: 100
    readonly property real fontMenuExtraWidth: 100
    readonly property real swatchTileMinWidth: 96
    readonly property real previewTileMinWidth: 140
    readonly property real emptyStateHeight: 100
    readonly property real noteMaxHeight: 160
    // On light surfaces the rows are the white cards, so the pane stays at the host tone, the sidebar recesses under it and controls step down to chips
    readonly property color sidebarColor: Theme.lightSurfaces ? Theme.foregroundColor(Theme.hostRecessSurface, true) : "transparent"
    readonly property color paneColor: Theme.lightSurfaces ? "transparent" : Theme.floatingWindowNestedSurface
    readonly property color rowColor: Theme.foregroundColor(Theme.hostChipSurface, true)
    readonly property color sidebarRowColor: rowColor
    readonly property color controlSurface: Theme.lightSurfaces ? Theme.chipSurface : Theme.chipSurfaceNested
    readonly property color controlColor: Theme.foregroundColor(controlSurface, true)
    readonly property color rowHighlightColor: Theme.withAlpha(Theme.primary, highlightBlend)
    readonly property color selectedRowColor: Theme.selectedContainer
    readonly property int transitionDuration: Theme.expressiveDurations.expressiveFastSpatial
    readonly property int expandDuration: Theme.expressiveDurations.expressiveDefaultSpatial
    readonly property int fadeDuration: Theme.expressiveDurations.expressiveEffects
    // M3 transitions stay on the legacy emphasized easing: MaterialFadeThrough and MaterialSharedAxis in material-components-android
    readonly property int pageTransitionDuration: Theme.motionMs(450)
    readonly property var pageTransitionCurve: [0.05, 0, 0.133333, 0.06, 0.166666, 0.4, 0.208333, 0.82, 0.25, 1, 1, 1]
    readonly property real pageFadeThreshold: 0.35
    readonly property real pageEnterScale: 0.92
    readonly property real pageSlideDistance: 30
    readonly property int pageCacheLimit: 6
    // A hub's header cards sit in a loader and a column below the page's own column
    readonly property int deferredCardSearchDepth: 3
    readonly property int pageBuildSlice: 4
    // Cards past the first screen handed to the incubator at once; it still builds them one after another
    readonly property int pageIncubationDepth: 3
    readonly property int pageAnticipationDelay: 90
    readonly property int pageTeardownInterval: 50
    readonly property int pageSpinnerDelay: 500
    readonly property real fieldWidthXS: Theme.iconButtonSize * 1.5
    readonly property real fieldWidthS: Theme.iconButtonSize * 2
    readonly property real fieldWidthM: Theme.iconButtonSize * 5
    readonly property real fieldWidthL: Theme.iconButtonSize * 8
    readonly property real fieldWidthXL: Theme.iconButtonSize * 10
}
