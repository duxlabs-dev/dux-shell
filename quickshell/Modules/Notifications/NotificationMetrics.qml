pragma Singleton

import QtQuick
import Quickshell
import qs.Common

Singleton {
    readonly property bool compact: SettingsData.notificationCompactMode
    readonly property real cardPadding: compact ? Theme.notificationCardPaddingCompact : Theme.notificationCardPadding
    readonly property real appIconSize: compact ? Theme.buttonHeightXXS : Theme.avatarSize
    readonly property real appIconRadius: Theme.cornerRadiusM
    readonly property var shortcutDashPattern: [2, 2]
    readonly property real shortcutTileWidth: Theme.buttonHeightM + Theme.spacingM
    readonly property real iconSpacing: compact ? Theme.spacingS : Theme.spacingM
    readonly property real thumbnailSize: compact ? Theme.buttonHeightXS : Theme.buttonHeightM
    readonly property real imageMaxHeight: Theme.listItemHeight * 4
    readonly property real imageDecodeSize: popupWidth * 2
    readonly property real actionHeight: compact ? Theme.buttonHeightXS : Theme.buttonHeightS
    readonly property real actionPadding: Theme.spacingS
    readonly property real controlSize: compact ? Theme.buttonHeightXXS : Theme.buttonHeightXS
    readonly property real railHeight: Theme.spacingXS
    readonly property real railStopSize: railHeight
    readonly property real contentSpacing: compact ? Theme.spacingXXS : Theme.notificationContentSpacing
    readonly property real popupRadius: Theme.windowRadius
    readonly property real menuRadius: Theme.cornerRadiusM
    readonly property real popupWidth: 400
    readonly property real popupMinWidth: 320
    readonly property real popupScreenRatio: 0.23
    readonly property real menuWidth: 280
    readonly property real emptyHeight: 200
    readonly property real centerMinHeight: 300
    readonly property real centerMaxHeight: 600
    readonly property real modalWidth: 500
    readonly property real modalHeight: 700
    readonly property real screenHeightRatio: 0.8
    readonly property real modalScreenRatio: 0.85
    readonly property real unreadDotSize: Theme.spacingXS + Theme.spacingXXS
    readonly property real swipeThreshold: 0.35
    readonly property real swipeFadeStart: 0.75
    readonly property real swipeContentFadeEnd: 0.6
    readonly property real swipeDetachDistance: 72
    readonly property real swipeAttachDistance: 56
    readonly property var swipePull: [0.04, 0.12, 0.5, 0.12, 0.04]
    readonly property var swipeRoundness: [0.5, 0.7, 0.9, 1, 0.9, 0.7, 0.5]
    readonly property real swipePullRoundnessMax: 0.8
    readonly property var swipeDetachSpring: swipeSpring(800, 0.95)
    readonly property var swipeSnapSpring: swipeSpring(550, 0.6)
    readonly property var swipeAttachSpring: swipeSpring(850, 0.95)
    readonly property real swipeWheelEngageDistance: 12
    readonly property int swipeWheelSettleMs: 500
    readonly property int swipeFlingProjectionMs: 200
    readonly property int expandedLimit: 10
    readonly property int collapsedLines: compact ? 1 : 2
    readonly property real summarySize: SettingsData.notificationSummaryFontSize || Theme.fontSizeMedium
    readonly property real bodySize: SettingsData.notificationBodyFontSize || Theme.fontSizeSmall
    readonly property real lineHeight: 1.2
    readonly property real estimatedCardHeight: cardPadding * 2 + controlSize + contentSpacing * 3 + summarySize * lineHeight + bodySize * lineHeight * collapsedLines + actionHeight
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.notificationAnimationBaseDuration > 0
    readonly property var heightCurve: Theme.expressiveCurves.standard
    readonly property var enterCurve: Theme.expressiveCurves.emphasizedDecel
    readonly property var exitCurve: Theme.expressiveCurves.standardAccel
    readonly property var stackSpring: Theme.springPreset("default", Theme.notificationStackShiftDuration)
    readonly property var expandCurve: Theme.expressiveCurves.expressiveDefaultSpatial
    readonly property var dismissCurve: Theme.expressiveCurves.expressiveFastSpatial

    function swipeSpring(stiffness, dampingRatio) {
        return {
            "stiffness": stiffness,
            "damping": 2 * dampingRatio * Math.sqrt(stiffness)
        };
    }
}
