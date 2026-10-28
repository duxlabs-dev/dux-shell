import QtQuick
import qs.Common
import qs.Modules.DBar.Widgets
import qs.Modules.SurfaceWidgets
import qs.Services
import "OverflowLayout.js" as OverflowLayout

Item {
    id: topBarContent

    required property var barWindow
    required property var rootWindow
    required property var barConfig

    readonly property var blurBarWindow: barWindow

    property var leftWidgetsModel
    property var centerWidgetsModel
    property var rightWidgetsModel
    property var widgetOwner: null
    property var hoverSections: null
    property real leadingSectionOffset: 0
    property real trailingSectionOffset: 0
    property real sectionCrossOffset: 0
    property real reservedStart: NaN
    property real reservedEnd: NaN
    readonly property bool fitToWidgets: _hasBarWindow && (barWindow.fitToWidgets ?? false)
    readonly property real sectionGap: (_barIsVertical ? vLeftSection : hLeftSection).widgetSpacing
    readonly property real leadingImplicitSize: _barIsVertical ? vLeftSection.implicitHeight : hLeftSection.implicitWidth
    readonly property real centerImplicitSize: _barIsVertical ? vCenterSection.implicitHeight : hCenterSection.implicitWidth
    readonly property real trailingImplicitSize: _barIsVertical ? vRightSection.implicitHeight : hRightSection.implicitWidth
    readonly property real fittedStartMargin: _barIsVertical ? _topMargin : _leftMargin
    readonly property real fittedEndMargin: _barIsVertical ? _bottomMargin : _rightMargin
    readonly property real fittedAvailableSize: fitToWidgets ? Math.max(1, barWindow.fittedAvailableLength - fittedStartMargin - fittedEndMargin) : 0
    readonly property real fittedLeadingReach: leadingImplicitSize > 0 ? leadingImplicitSize + sectionGap : 0
    readonly property real fittedTrailingReach: trailingImplicitSize > 0 ? trailingImplicitSize + sectionGap : 0
    readonly property var fittedCenterSection: _barIsVertical ? vCenterSection : hCenterSection
    property var overflowPlan: ({
            hidden: {
                left: [],
                center: [],
                right: []
            },
            fits: true
        })
    readonly property var overflowSections: _barIsVertical ? [vLeftSection, vCenterSection, vRightSection] : [hLeftSection, hCenterSection, hRightSection]
    readonly property real overflowLength: fitToWidgets ? barWindow.fittedAvailableLength : (_barIsVertical ? height : width)
    readonly property string overflowCenteringMode: SettingsData.centeringMode

    onOverflowLengthChanged: requestOverflowLayout()
    onOverflowSectionsChanged: requestOverflowLayout()
    onOverflowCenteringModeChanged: requestOverflowLayout()
    onReservedStartChanged: requestOverflowLayout()
    onReservedEndChanged: requestOverflowLayout()
    onFittedStartMarginChanged: requestOverflowLayout()
    onFittedEndMarginChanged: requestOverflowLayout()

    function requestOverflowLayout() {
        overflowTimer.restart();
    }

    function updateOverflowLayout() {
        if (overflowLength <= 0)
            return;
        const names = ["left", "center", "right"];
        const sections = {};
        const positions = {};
        for (let index = 0; index < names.length; index++) {
            sections[names[index]] = overflowSections[index].layoutEntries;
            positions[names[index]] = overflowSections[index].overflowPosition;
        }
        const result = OverflowLayout.resolve(sections, {
            length: overflowLength,
            start: fitToWidgets ? fittedStartMargin : 0,
            end: fitToWidgets ? fittedEndMargin : 0,
            reserve: isNaN(reservedStart) ? null : {
                start: reservedStart,
                end: reservedEnd
            },
            spacing: sectionGap,
            triggerSize: overflowSections[0].overflowTriggerSize,
            positions,
            centeringMode: overflowCenteringMode,
            confineCenter: fitToWidgets,
            restoreMargin: Theme.spacingS
        }, overflowPlan.hidden);
        const next = {
            hidden: result.hidden,
            sizes: result.sizes,
            fits: result.fits
        };
        if (JSON.stringify(next) !== JSON.stringify(overflowPlan))
            overflowPlan = next;
    }

    Timer {
        id: overflowTimer
        interval: 0
        repeat: false
        onTriggered: topBarContent.updateOverflowLayout()
    }
    readonly property real fittedCoreStart: {
        if (!fitToWidgets)
            return 0;
        if (centerImplicitSize > 0)
            return fittedCenterSection.contentStart;
        const sides = leadingImplicitSize + trailingImplicitSize + (leadingImplicitSize > 0 && trailingImplicitSize > 0 ? sectionGap : 0);
        return (barWindow.fittedAvailableLength - sides) / 2 + fittedLeadingReach;
    }
    readonly property real fittedCoreEnd: !fitToWidgets ? 0 : centerImplicitSize > 0 ? fittedCoreStart + fittedCenterSection.contentSize : fittedCoreStart - (leadingImplicitSize > 0 && trailingImplicitSize > 0 ? sectionGap : 0)
    readonly property real fittedLeadingPad: fittedCoreStart - fittedLeadingReach - fittedStartMargin
    readonly property var centerBounds: {
        if (!fitToWidgets)
            return null;
        return {
            min: fittedLeadingReach + fittedStartMargin,
            max: barWindow.fittedAvailableLength - fittedTrailingReach - fittedEndMargin
        };
    }
    readonly property real fittedTrailingPad: barWindow.fittedAvailableLength - fittedCoreEnd - fittedTrailingReach - fittedEndMargin
    readonly property var workspaceWidget: SettingsData.barWidgetEntry(barConfig, "workspaceSwitcher")

    function workspaceOption(key) {
        return SettingsData.widgetOption("workspaceSwitcher", workspaceWidget, key);
    }
    property bool _animateFrameInsets: false

    readonly property real innerPadding: barConfig?.innerPadding ?? SettingsData.barInnerPaddingDefault
    readonly property real outlineThickness: (barConfig?.widgetOutlineEnabled ?? false) ? (barConfig?.widgetOutlineThickness ?? 1) : 0
    readonly property real _edgeBaseMargin: Math.max(Theme.spacingXS, innerPadding * 0.8)
    readonly property bool _hasBarWindow: barWindow !== undefined && barWindow !== null
    readonly property bool _usesFrameBarChrome: _hasBarWindow && (barWindow.usesFrameBarChrome ?? false)
    readonly property bool _barIsVertical: _hasBarWindow ? barWindow.isVertical : false
    readonly property string _barScreenName: _hasBarWindow ? (barWindow.screenName || "") : ""
    readonly property bool hasAdjacentTopBarLive: _hasBarWindow && barWindow.hasAdjacentTopBar
    readonly property bool hasAdjacentBottomBarLive: _hasBarWindow && barWindow.hasAdjacentBottomBar
    readonly property bool hasAdjacentLeftBarLive: _hasBarWindow && barWindow.hasAdjacentLeftBar
    readonly property bool hasAdjacentRightBarLive: _hasBarWindow && barWindow.hasAdjacentRightBar

    // Standalone/separate Bar Inset Padding (per-bar, optionally synced): absolute gap at BOTH ends.
    // Stored value < 0 (default -1) means "auto" — fall back to the natural edge margin so the look is unchanged.
    readonly property real _barInsetPaddingRaw: SettingsData.barInsetPaddingSyncAll ? SettingsData.barInsetPaddingShared : (barConfig?.barInsetPadding ?? -1)
    readonly property real _barInsetPaddingAuto: _barIsVertical ? Theme.spacingXS : _edgeBaseMargin
    readonly property real _barInsetPadding: _barInsetPaddingRaw < 0 ? _barInsetPaddingAuto : _barInsetPaddingRaw
    // Hosted bars span their edge fully; frameBarContentGap is the free-end gap measured from the
    // screen edge (auto = frameThickness, aligning widgets with the interior cutout).
    readonly property real _frameInsetResolved: SettingsData.frameBarContentGap
    readonly property real _frameInsetExtra: SettingsData.frameBarContentGapExtra

    // Horizontal bars span the full width and own the corners; the perpendicular vertical bar
    // tucks in below/above. Where they meet, inset the corner widget so it centres in the
    // frameBarSize corner cell, aligning it with the vertical bar's widget column.
    readonly property real _widgetThicknessValue: _hasBarWindow ? barWindow.widgetThickness : 30
    readonly property real _cornerAlignInset: Math.max(_frameInsetExtra, (SettingsData.frameBarSize - _widgetThicknessValue) / 2)

    readonly property real _leftMargin: {
        if (_barIsVertical)
            return _edgeBaseMargin;
        if (_usesFrameBarChrome)
            return hasAdjacentLeftBarLive ? _cornerAlignInset : _frameInsetResolved;
        return Math.max(0, _barInsetPadding);
    }
    readonly property real _rightMargin: {
        if (_barIsVertical)
            return _edgeBaseMargin;
        if (_usesFrameBarChrome)
            return hasAdjacentRightBarLive ? _cornerAlignInset : _frameInsetResolved;
        return Math.max(0, _barInsetPadding);
    }
    readonly property real _topMargin: {
        if (!_barIsVertical)
            return 0;
        if (_usesFrameBarChrome) {
            const inset = ShellLayout.frameContentInset(barWindow.screen, barConfig?.id, "top");
            return inset !== null ? _edgeBaseMargin + inset + _frameInsetExtra : _frameInsetResolved;
        }
        return Math.max(0, _barInsetPadding);
    }
    readonly property real _bottomMargin: {
        if (!_barIsVertical)
            return 0;
        if (_usesFrameBarChrome) {
            const inset = ShellLayout.frameContentInset(barWindow.screen, barConfig?.id, "bottom");
            return inset !== null ? _edgeBaseMargin + inset + _frameInsetExtra : _frameInsetResolved;
        }
        return Math.max(0, _barInsetPadding);
    }

    property alias hLeftSection: hLeftSection
    property alias hCenterSection: hCenterSection
    property alias hRightSection: hRightSection
    property alias vLeftSection: vLeftSection
    property alias vCenterSection: vCenterSection
    property alias vRightSection: vRightSection

    readonly property var _defaultHoverSections: barWindow.isVertical ? [
        {
            section: vLeftSection,
            name: "left"
        },
        {
            section: vCenterSection,
            name: "center"
        },
        {
            section: vRightSection,
            name: "right"
        }
    ] : [
        {
            section: hLeftSection,
            name: "left"
        },
        {
            section: hCenterSection,
            name: "center"
        },
        {
            section: hRightSection,
            name: "right"
        }
    ]

    anchors.fill: parent
    anchors.leftMargin: _leftMargin
    anchors.rightMargin: _rightMargin
    anchors.topMargin: _topMargin
    anchors.bottomMargin: _bottomMargin
    clip: false

    DeferredAction {
        id: enableFrameInsetAnimation
        onTriggered: topBarContent._animateFrameInsets = true
    }

    Component.onCompleted: {
        enableFrameInsetAnimation.schedule();
    }

    Connections {
        target: topBarContent._hasBarWindow ? topBarContent.barWindow.axis : null

        function onEdgeChanged() {
            topBarContent.resetHoverForBarGeometryChange();
        }
    }

    Behavior on anchors.leftMargin {
        enabled: _animateFrameInsets && _usesFrameBarChrome && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on anchors.rightMargin {
        enabled: _animateFrameInsets && _usesFrameBarChrome && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on anchors.topMargin {
        enabled: _animateFrameInsets && _usesFrameBarChrome && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on anchors.bottomMargin {
        enabled: _animateFrameInsets && _usesFrameBarChrome && !SettingsData.reduceMotion
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    property int componentMapRevision: 0

    function updateComponentMap() {
        componentMapRevision++;
    }

    readonly property var sortedToplevels: {
        if (!_hasBarWindow) {
            return [];
        }
        return CompositorService.filterCurrentWorkspace(CompositorService.sortedToplevels, _barScreenName);
    }

    function switchWorkspace(direction) {
        CompositorService.scrollWorkspace(_barScreenName, topBarContent.workspaceOption("workspaceFollowFocus"), topBarContent.workspaceOption("dwlShowAllTags"), direction);
    }

    function switchApp(deltaY) {
        const windows = sortedToplevels.filter(w => !w.skipSwitcher);
        if (windows.length < 2) {
            return;
        }
        let currentIndex = -1;
        for (let i = 0; i < windows.length; i++) {
            if (windows[i].activated) {
                currentIndex = i;
                break;
            }
        }
        let nextIndex;
        if (deltaY < 0) {
            if (currentIndex === -1) {
                nextIndex = 0;
            } else {
                nextIndex = currentIndex + 1;
            }
        } else {
            if (currentIndex === -1) {
                nextIndex = windows.length - 1;
            } else {
                nextIndex = currentIndex - 1;
            }
        }
        const nextWindow = windows[nextIndex];
        if (nextWindow) {
            CompositorService.activateToplevel(nextWindow);
        }
    }

    readonly property int availableWidth: fitToWidgets ? fittedAvailableSize : width
    readonly property int launcherButtonWidth: 40
    readonly property int workspaceSwitcherWidth: 120
    readonly property int focusedAppMaxWidth: 456
    readonly property int estimatedLeftSectionWidth: launcherButtonWidth + workspaceSwitcherWidth + focusedAppMaxWidth + (Theme.spacingXS * 2)
    readonly property int rightSectionWidth: 200
    readonly property int clockWidth: 120
    readonly property int mediaMaxWidth: 280
    readonly property int weatherWidth: 80
    readonly property bool validLayout: availableWidth > 100 && estimatedLeftSectionWidth > 0 && rightSectionWidth > 0
    readonly property int clockLeftEdge: (availableWidth - clockWidth) / 2
    readonly property int clockRightEdge: clockLeftEdge + clockWidth
    readonly property int leftSectionRightEdge: estimatedLeftSectionWidth
    readonly property int mediaLeftEdge: clockLeftEdge - mediaMaxWidth - Theme.spacingS
    readonly property int rightSectionLeftEdge: availableWidth - rightSectionWidth
    readonly property int leftToClockGap: Math.max(0, clockLeftEdge - leftSectionRightEdge)
    readonly property int leftToMediaGap: mediaMaxWidth > 0 ? Math.max(0, mediaLeftEdge - leftSectionRightEdge) : leftToClockGap
    readonly property int mediaToClockGap: mediaMaxWidth > 0 ? Theme.spacingS : 0
    readonly property int clockToRightGap: validLayout ? Math.max(0, rightSectionLeftEdge - clockRightEdge) : 1000
    readonly property bool spacingTight: !_barIsVertical && validLayout && (leftToMediaGap < 150 || clockToRightGap < 100)
    readonly property bool overlapping: !_barIsVertical && validLayout && (leftToMediaGap < 100 || clockToRightGap < 50)

    function getWidgetEnabled(enabled) {
        return enabled !== false;
    }

    function getWidgetSection(parentItem) {
        let current = parentItem;
        while (current) {
            if (current.objectName === "leftSection") {
                return "left";
            }
            if (current.objectName === "centerSection") {
                return "center";
            }
            if (current.objectName === "rightSection") {
                return "right";
            }
            current = current.parent;
        }
        return "left";
    }

    DBarHoverController {
        id: hoverController
        barContent: topBarContent
        barWindow: topBarContent.barWindow
        barConfig: topBarContent.barConfig
        widgetOwner: topBarContent.widgetOwner
        sections: topBarContent.hoverSections || topBarContent._defaultHoverSections
        leftWidgetsModel: topBarContent.leftWidgetsModel
        centerWidgetsModel: topBarContent.centerWidgetsModel
        rightWidgetsModel: topBarContent.rightWidgetsModel
    }

    readonly property string activeHoverTrigger: hoverController.activeHoverTrigger
    readonly property bool hoverPopoutsEnabled: hoverController.hoverPopoutsEnabled

    function queueHoverFromItem(item, point) {
        if (!point)
            return;
        const gp = surfaceContext.screenPoint(item, point.position.x, point.position.y);
        if (!gp)
            return;
        queueHoverPopout(gp.x, gp.y);
    }

    function queueHoverPopout(gx, gy) {
        hoverController.queueHoverPoint(gx, gy);
    }

    function checkHoverPopout(gx, gy) {
        hoverController.checkHoverPopout(gx, gy);
    }

    function findWidgetAtGlobalPoint(gx, gy) {
        return hoverController.findWidgetAtGlobalPoint(gx, gy);
    }

    function scheduleHoverClose(gx, gy) {
        hoverController.scheduleHoverClose(gx, gy);
    }

    function updateHoverBarHovered(hovered) {
        hoverController.updateBarHovered(hovered);
    }

    function invalidateHoverCandidateCache() {
        hoverController.invalidateCandidateCache();
    }

    function resetHoverForBarGeometryChange() {
        hoverController.resetForBarGeometryChange();
    }

    function _dashTriggerSource(section, tabId) {
        return hoverController.dashTriggerSource(section, tabId);
    }

    SurfaceContext {
        id: widgetContext
        host: topBarContent.barWindow
        config: topBarContent.barConfig
        centerSection: topBarContent.barWindow.isVertical ? vCenterSection : hCenterSection
    }
    SurfaceWidgetFactory {
        id: widgetFactory
        surfaceContext: widgetContext
        spacingTight: topBarContent.spacingTight
        overlapping: topBarContent.overlapping
    }
    readonly property var allComponents: widgetFactory.componentMap
    readonly property var componentMap: widgetFactory.componentMap
    readonly property var surfaceContext: widgetContext
    function getWidgetComponent(id) {
        return widgetFactory.getWidgetComponent(id);
    }
    function getWidgetVisible(id) {
        return widgetFactory.getWidgetVisible(id);
    }
    function getBarPosition() {
        return widgetFactory.getBarPosition();
    }
    function openWidgetPopout(spec) {
        return widgetFactory.openWidgetPopout(spec);
    }
    function resolvePopoutFromLoader(loader) {
        return widgetFactory._resolvePopoutFromLoader(loader);
    }
    function cancelQueuedWidgetPopout() {
        widgetFactory.pendingOpen = null;
    }

    Item {
        id: stackContainer
        anchors.fill: parent

        Item {
            id: horizontalStack
            anchors.fill: parent
            visible: !barWindow.axis.isVertical

            LeftSection {
                id: hLeftSection
                objectName: "leftSection"
                edgeIsScreenEdge: !topBarContent.hasAdjacentLeftBarLive
                overrideAxisLayout: true
                forceVerticalLayout: false
                anchors {
                    left: parent.left
                    leftMargin: topBarContent.leadingSectionOffset
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: topBarContent.sectionCrossOffset
                }
                axis: barWindow.axis
                barContent: topBarContent
                sectionAvailablePrimarySize: topBarContent.fitToWidgets ? topBarContent.fittedAvailableSize : Math.max(1, hCenterSection.x > 0 ? hCenterSection.x : parent.width / 3)
            }

            RightSection {
                id: hRightSection
                objectName: "rightSection"
                edgeIsScreenEdge: !topBarContent.hasAdjacentRightBarLive
                overrideAxisLayout: true
                forceVerticalLayout: false
                anchors {
                    right: parent.right
                    rightMargin: topBarContent.trailingSectionOffset
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: topBarContent.sectionCrossOffset
                }
                axis: barWindow.axis
                barContent: topBarContent
                sectionAvailablePrimarySize: topBarContent.fitToWidgets ? topBarContent.fittedAvailableSize : Math.max(1, hCenterSection.x > 0 ? parent.width - (hCenterSection.x + hCenterSection.width) : parent.width / 3)
            }

            CenterSection {
                id: hCenterSection
                objectName: "centerSection"
                overrideAxisLayout: true
                forceVerticalLayout: false
                anchors.centerIn: topBarContent.fitToWidgets ? null : parent
                anchors.verticalCenter: parent.verticalCenter
                x: topBarContent.fitToWidgets ? -(barWindow.lengthPaddingStartPx + topBarContent._leftMargin) : 0
                width: topBarContent.fitToWidgets ? barWindow.fittedAvailableLength : parent.width
                axis: barWindow.axis
                barContent: topBarContent
                sectionAvailablePrimarySize: topBarContent.fitToWidgets ? topBarContent.fittedAvailableSize : Math.max(1, hRightSection.x > 0 ? hRightSection.x - (hLeftSection.x + hLeftSection.width) : parent.width / 3)
            }
        }

        Item {
            id: verticalStack
            anchors.fill: parent
            visible: barWindow.axis.isVertical

            LeftSection {
                id: vLeftSection
                objectName: "leftSection"
                edgeIsScreenEdge: !topBarContent.hasAdjacentTopBarLive
                overrideAxisLayout: true
                forceVerticalLayout: true
                width: parent.width
                anchors {
                    top: parent.top
                    topMargin: topBarContent.leadingSectionOffset
                    horizontalCenter: parent.horizontalCenter
                    horizontalCenterOffset: topBarContent.sectionCrossOffset
                }
                axis: barWindow.axis
                barContent: topBarContent
                sectionAvailablePrimarySize: topBarContent.fitToWidgets ? topBarContent.fittedAvailableSize : Math.max(1, vCenterSection.y > 0 ? vCenterSection.y : parent.height / 3)
            }

            CenterSection {
                id: vCenterSection
                objectName: "centerSection"
                overrideAxisLayout: true
                forceVerticalLayout: true
                width: parent.width
                height: topBarContent.fitToWidgets ? barWindow.fittedAvailableLength : parent.height
                anchors.centerIn: topBarContent.fitToWidgets ? null : parent
                anchors.horizontalCenter: parent.horizontalCenter
                y: topBarContent.fitToWidgets ? -(barWindow.lengthPaddingStartPx + topBarContent._topMargin) : 0
                axis: barWindow.axis
                barContent: topBarContent
                sectionAvailablePrimarySize: topBarContent.fitToWidgets ? topBarContent.fittedAvailableSize : Math.max(1, vRightSection.y > 0 ? vRightSection.y - (vLeftSection.y + vLeftSection.height) : parent.height / 3)
            }

            RightSection {
                id: vRightSection
                objectName: "rightSection"
                edgeIsScreenEdge: !topBarContent.hasAdjacentBottomBarLive
                overrideAxisLayout: true
                forceVerticalLayout: true
                width: parent.width
                height: implicitHeight
                anchors {
                    bottom: parent.bottom
                    bottomMargin: topBarContent.trailingSectionOffset
                    horizontalCenter: parent.horizontalCenter
                    horizontalCenterOffset: topBarContent.sectionCrossOffset
                }
                axis: barWindow.axis
                barContent: topBarContent
                sectionAvailablePrimarySize: topBarContent.fitToWidgets ? topBarContent.fittedAvailableSize : Math.max(1, vCenterSection.y > 0 ? parent.height - (vCenterSection.y + vCenterSection.height) : parent.height / 3)
            }
        }
    }
}
