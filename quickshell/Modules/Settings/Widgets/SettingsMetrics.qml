pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property real sidebarWidth: 336
    readonly property real compactBreakpoint: 700
    readonly property real contentMaxWidth: 920
    readonly property real paneMaxWidth: contentMaxWidth + panePadding * 2
    readonly property real mediaMaxWidth: 720
    readonly property real windowWidth: 1100
    readonly property real windowHeight: 940
    readonly property real windowMinWidth: 500
    readonly property real windowMinHeight: 400
    readonly property real formDialogWidth: 640
    readonly property real pagePaddingH: 40
    readonly property real pagePaddingV: 32
    readonly property real paneMargin: Theme.windowInset
    readonly property real panePadding: Theme.spacingXL
    // Scroll containers clip at their bounds, so pages grow by this and inset their content to let focus rings bleed
    readonly property real focusGutter: Theme.focusRingOffset + Theme.focusRingWidth
    readonly property real paneRadius: Theme.cornerRadiusL
    readonly property real pageHeaderHeight: Theme.fontSizeXXLarge + Theme.spacingXL + Theme.spacingM
    readonly property real rowPaddingH: 20
    readonly property real rowPaddingV: 16
    readonly property real rowContentSpacing: Theme.spacingL
    readonly property real heroPadding: rowPaddingV
    readonly property real heroLeadingSize: Theme.avatarSize
    readonly property real sectionLabelTopGap: Theme.spacingS
    readonly property real sectionLabelBottomGap: Theme.spacingM
    readonly property real navIconSize: Theme.avatarSize
    readonly property real navItemMinHeight: Theme.listItemHeight
    readonly property real sidebarGroupGap: Theme.spacingS
    readonly property real searchBarGap: Theme.spacingM
    readonly property real avatarSize: 64
    readonly property real splitDividerHeight: Theme.iconSize
    readonly property real buttonGroupCompactThreshold: 200
    readonly property real choiceCardPreviewRatio: 10 / 16
    readonly property real positionPickerMaxWidth: 360
    readonly property real wallpaperThumbRatio: 10 / 16
    readonly property int wallpaperThumbCache: 1024
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
    readonly property color paneColor: Theme.floatingWindowNestedSurface
    readonly property color sidebarRowColor: Theme.floatingWindowNestedSurface
    readonly property color rowColor: Theme.foregroundColor(Theme.chipSurface, true)
    readonly property color controlSurface: Theme.chipSurfaceNested
    readonly property color controlColor: Theme.foregroundColor(controlSurface, true)
    readonly property color rowHighlightColor: Theme.withAlpha(Theme.primary, highlightBlend)
    readonly property color selectedRowColor: Theme.selectedContainer
    readonly property int transitionDuration: Theme.expressiveDurations.expressiveFastSpatial
    readonly property int fadeDuration: Theme.expressiveDurations.expressiveEffects
    readonly property int exitDuration: Theme.expressiveDurations.expressiveFastEffects
    readonly property int pageSettleFrames: 2
    readonly property int pageSettleDeadline: 250
    readonly property int pageSpinnerDelay: 500
}
