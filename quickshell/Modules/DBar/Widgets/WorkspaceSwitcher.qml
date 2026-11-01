import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.WindowManager
import qs.Common
import qs.Modules.DBar
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import "../../../DCommon/Common/WheelInput.js" as WheelInput

BasePill {
    id: root

    // sized from its label and centered on the glyph box, since a digit's line box is off-center
    component CountBadge: Rectangle {
        property alias text: badgeLabel.text
        property alias textColor: badgeLabel.color

        height: Math.max(badgeLabel.font.pixelSize, Math.ceil(badgeMetrics.tightBoundingRect.height) + Theme.spacingXXS * 2)
        width: Math.max(height, Math.ceil(badgeMetrics.tightBoundingRect.width) + Theme.spacingXXS * 2)
        radius: height / 2
        color: Theme.primary

        StyledTextMetrics {
            id: badgeMetrics
            font: badgeLabel.font
            text: badgeLabel.text
        }

        StyledText {
            id: badgeLabel
            x: Math.round((parent.width - badgeMetrics.tightBoundingRect.width) / 2 - badgeMetrics.tightBoundingRect.x)
            y: Math.round((parent.height - badgeMetrics.tightBoundingRect.height) / 2 - baselineOffset - badgeMetrics.tightBoundingRect.y)
            font.pixelSize: BarMetrics.indicatorLabelMin
            font.weight: Theme.fontWeightMedium
            color: Theme.onPrimary
        }
    }

    enableBackgroundHover: false

    property bool isVertical: axis?.isVertical ?? false
    property var widgetData: null
    property string screenName: ""
    property var hyprlandOverviewLoader: null
    property var surfaceContext: null
    readonly property string indicatorStyle: root.opt("workspaceIndicatorStyle")
    readonly property bool linesStyle: indicatorStyle === "lines"
    readonly property bool cardsStyle: indicatorStyle === "cards"
    readonly property bool dotsStyle: indicatorStyle === "dots"
    readonly property real roundness: root.opt("workspaceIndicatorRoundness")
    readonly property bool compactIndicators: root.opt("workspaceIndicatorCompact")
    readonly property bool segmented: !linesStyle && !cardsStyle && !dotsStyle && surfaceContext?.kind !== "dock" && BarMetrics.widgetStyle(barConfig) === "segments" && !noBackground
    readonly property real compactRatio: BarMetrics.indicatorRatio(indicatorStyle, "compact", compactIndicators)
    readonly property real slimRatio: BarMetrics.indicatorRatio(indicatorStyle, "slim", compactIndicators)
    readonly property real activeSlimRatio: BarMetrics.indicatorRatio(indicatorStyle, "activeSlim", compactIndicators)
    readonly property real activeRatio: BarMetrics.indicatorRatio(indicatorStyle, "active", compactIndicators)
    readonly property real compactScale: compactIndicators ? BarMetrics.indicatorCompactScale : 1
    readonly property real activeIconRatio: 1.6 * compactScale
    readonly property real iconRatio: 1.2 * compactScale
    readonly property real overviewTintAlpha: 0.18
    readonly property real dragOpacity: 0.8
    readonly property real hoverFadeAlpha: 0.7
    readonly property real inactiveLabelAlpha: 0.85
    readonly property real unfocusedAppAlpha: 0.7
    readonly property real hoveredAppAlpha: 0.85
    readonly property real cardWindowRatio: 0.45
    readonly property real labelSize: Math.min(Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText), Math.floor(widgetThickness * BarMetrics.indicatorLabelRatio))

    WorkspaceSwitcherModel {
        id: workspaces

        screenName: root.screenName
        screen: root.parentScreen
        followFocus: root.opt("workspaceFollowFocus")
        occupiedOnly: root.opt("showOccupiedWorkspacesOnly")
        showAllTags: root.opt("dwlShowAllTags")
        showPadding: root.opt("showWorkspacePadding")
        paddingCount: root.opt("workspacePaddingCount")
        showSpecial: root.opt("showSpecialWorkspaces")
        reverseScrolling: root.opt("reverseScrolling")
    }

    readonly property bool useAqueous: workspaces.useAqueous
    readonly property bool useExtWorkspace: workspaces.useExtWorkspace
    readonly property bool useNativeWorkspaces: workspaces.useNativeWorkspaces
    readonly property string effectiveScreenName: workspaces.effectiveScreenName
    readonly property bool workspacesHiddenByOverview: workspaces.hiddenByOverview
    readonly property var currentWorkspace: workspaces.currentWorkspace
    readonly property var workspaceList: workspaces.workspaceList

    function opt(key) {
        return SettingsData.widgetOption("workspaceSwitcher", widgetData, key);
    }

    property int _desktopEntriesUpdateTrigger: 0

    readonly property bool isFocusedMonitor: {
        const focused = BarWidgetService.getFocusedScreenName();
        return focused === "" || root.screenName === "" || focused === root.screenName;
    }
    readonly property bool useUnfocusedAppearance: !isFocusedMonitor && root.opt("workspaceUnfocusedMonitorSeparateAppearance") && BarWidgetService.focusedScreenDetectionSupported

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            _desktopEntriesUpdateTrigger++;
        }
    }

    function getWorkspaceIcons(ws) {
        _desktopEntriesUpdateTrigger;
        if (!root.opt("showWorkspaceApps") || !ws || !root.useNativeWorkspaces || ws.placeholder || !IconThemeService.ready) {
            return [];
        }

        const byApp = {};
        const isActiveWs = CompositorService.workspaceAppsActive(ws, root.currentWorkspace);

        CompositorService.windowsOnWorkspace(ws).forEach((w, i) => {
            const keyBase = (w.app_id || w.appId || w.class || w.windowClass || "unknown");
            const moddedId = Paths.moddedAppId(keyBase);
            const groupThisWs = root.opt("groupWorkspaceApps") && (!isActiveWs || root.opt("groupActiveWorkspaceApps"));
            const key = groupThisWs ? moddedId : (w.aqueousKey || `${moddedId}_${i}`);

            if (!byApp[key]) {
                const isQuickshell = Paths.isDmsAppId(keyBase);
                const isSteamApp = Paths.isSteamApp(moddedId);
                const desktopEntry = DesktopEntries.heuristicLookup(moddedId);
                const icon = Paths.getAppIcon(moddedId, desktopEntry);
                const appName = Paths.getAppName(moddedId, desktopEntry);
                byApp[key] = {
                    "type": "icon",
                    "icon": icon,
                    "isQuickshell": isQuickshell,
                    "isSteamApp": isSteamApp,
                    "active": !!(w.activated || w.is_focused),
                    "count": 1,
                    "windowId": w.address || w.id,
                    "windowSession": useAqueous ? w.aqueousSession : "",
                    "fallbackText": appName || ""
                };
            } else {
                byApp[key].count++;
                if (w.activated || w.is_focused) {
                    byApp[key].active = true;
                }
            }
        });

        return Object.values(byApp);
    }

    function recordOf(entry) {
        return workspaces.recordOf(entry);
    }

    // the pill pads icons by spacingXS on each side and must fit the widget thickness
    readonly property real appIconSize: Math.max(0, Math.min(Theme.barIconSize(barThickness, -6 + root.opt("workspaceAppIconSizeOffset"), root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale), widgetThickness - Theme.spacingXS * 2))

    function getRealWorkspaces() {
        return workspaces.realWorkspaces;
    }

    function switchToWorkspaceByModelData(entry) {
        workspaces.switchTo(entry);
    }

    function toggleHyprlandOverview() {
        const overview = root.hyprlandOverviewLoader?.item;
        if (!overview)
            return;
        overview.overviewOpen = !overview.overviewOpen;
    }

    function findClosestWorkspaceIndex(localX, localY) {
        if (workspaceRepeater.count === 0)
            return -1;

        let closestIdx = -1;
        let closestDist = Infinity;

        for (let i = 0; i < workspaceRepeater.count; i++) {
            const item = workspaceRepeater.itemAt(i);
            if (!item || item.isPlaceholder)
                continue;
            const center = item.mapToItem(root, item.width / 2, item.height / 2);
            const dist = isVertical ? Math.abs(localY - center.y) : Math.abs(localX - center.x);
            if (dist < closestDist) {
                closestDist = dist;
                closestIdx = i;
            }
        }
        return closestIdx;
    }

    function switchWorkspace(direction) {
        workspaces.step(direction);
    }

    function getWorkspaceIndexFallback(modelData, index) {
        if (root.useExtWorkspace)
            return index + 1;
        if (!root.useNativeWorkspaces)
            return modelData - 1;
        return modelData?.idx ?? modelData?.name ?? "";
    }

    function getWorkspaceIndex(modelData, index) {
        if (modelData?.placeholder === true)
            return index + 1;

        let workspaceName = "";
        if (root.opt("showWorkspaceName")) {
            workspaceName = modelData?.name ?? "";

            if (workspaceName && workspaceName !== "") {
                if (root.isVertical) {
                    workspaceName = workspaceName.charAt(0);
                }
            } else {
                workspaceName = "";
            }
        }

        if (workspaceName) {
            if (root.opt("showWorkspaceIndex")) {
                const indexLabel = getWorkspaceIndexFallback(modelData, index);
                return indexLabel ? `${indexLabel}: ${workspaceName}` : workspaceName;
            }
            return workspaceName;
        }

        return getWorkspaceIndexFallback(modelData, index);
    }

    readonly property bool shouldShow: workspaces.available

    width: shouldShow ? (isVertical ? barThickness : visualWidth) : 0
    height: shouldShow ? (isVertical ? visualHeight : barThickness) : 0
    visible: shouldShow

    content: Component {
        Item {
            implicitWidth: workspaceRow.implicitWidth
            implicitHeight: workspaceRow.implicitHeight
        }
    }

    onRightClicked: {
        CompositorService.workspaceSecondaryAction(null, root.effectiveScreenName);
        root.toggleHyprlandOverview();
    }

    onPressedAt: (rootX, rootY) => {
        const idx = root.findClosestWorkspaceIndex(rootX, rootY);
        if (idx >= 0)
            root.switchToWorkspaceByModelData(root.workspaceList[idx]);
    }

    onWheel: wheel => {
        if (WheelInput.isHorizontal(wheel))
            return;
        wheel.accepted = true;
        workspaces.handleWheel(wheel);
    }

    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property bool suppressShiftAnimation: false

    onWorkspaceListChanged: {
        if (dragSourceIndex >= 0) {
            dragSourceIndex = -1;
            dragTargetIndex = -1;
            suppressShiftAnimation = false;
        }
    }

    BarSegment {
        id: workspaceRow

        anchors.centerIn: root.visualContent
        spacing: root.segmented ? BarMetrics.segmentGap : Theme.spacingS
        vertical: root.isVertical

        // mango reports active_tags=0 while the overview is open; surface it as a pill
        Item {
            id: overviewPill
            visible: CompositorService.workspacesHiddenByOverview(root.effectiveScreenName)
            width: root.isVertical ? root.widgetThickness : overviewBg.width
            height: root.isVertical ? overviewBg.height : root.widgetThickness

            Rectangle {
                id: overviewBg
                anchors.centerIn: parent
                width: root.isVertical ? Math.min(root.widgetThickness, Math.max(root.widgetThickness * root.compactRatio, overviewContent.implicitWidth + Theme.spacingS)) : (overviewContent.implicitWidth + Theme.spacingS * 2)
                height: root.isVertical ? Math.max(root.widgetThickness * root.slimRatio, overviewContent.implicitHeight + Theme.spacingXS) : Math.min(root.widgetThickness, Math.max(root.widgetThickness * root.slimRatio, overviewContent.implicitHeight + Theme.spacingXS))
                radius: BarMetrics.pillRadius(Math.min(width, height), BarMetrics.widgetStyle(root.barConfig))
                color: Theme.withAlpha(Theme.primary, root.overviewTintAlpha)

                Row {
                    id: overviewContent
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "grid_view"
                        size: root.labelSize + 2
                        color: Theme.primary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.isVertical
                        text: I18n.tr("Overview", "noun, niri compositor overview mode label")
                        color: Theme.primary
                        font.pixelSize: root.labelSize
                        font.weight: Theme.fontWeightMedium
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: CompositorService.toggleOverview(root.effectiveScreenName)
            }
        }

        Repeater {
            id: workspaceRepeater
            model: ScriptModel {
                values: root.workspaceList
            }

            Item {
                id: delegateRoot

                property bool isDropTarget: root.dragTargetIndex === index

                z: dragHandler.dragging ? 1000 : 1

                property real shiftOffset: {
                    if (root.dragSourceIndex < 0 || index === root.dragSourceIndex)
                        return 0;
                    const dragIdx = root.dragSourceIndex;
                    const dropIdx = root.dragTargetIndex;
                    if (dropIdx < 0)
                        return 0;
                    const shiftAmount = delegateRoot.width + workspaceRow.spacing;
                    if (dragIdx < dropIdx && index > dragIdx && index <= dropIdx)
                        return -shiftAmount;
                    if (dragIdx > dropIdx && index >= dropIdx && index < dragIdx)
                        return shiftAmount;
                    return 0;
                }

                readonly property var shiftSpringParams: Theme.springPreset("fast", 150)

                SpringMotion {
                    id: shiftXSpring
                    enabled: !root.suppressShiftAnimation
                    positionEpsilon: 0.05
                    velocityEpsilon: 0.05
                    stiffness: delegateRoot.shiftSpringParams.stiffness
                    damping: delegateRoot.shiftSpringParams.damping
                    value: delegateRoot.shiftOffset

                    Component.onCompleted: snapTo(delegateRoot.shiftOffset)
                }

                SpringMotion {
                    id: shiftYSpring
                    enabled: !root.suppressShiftAnimation
                    positionEpsilon: 0.05
                    velocityEpsilon: 0.05
                    stiffness: delegateRoot.shiftSpringParams.stiffness
                    damping: delegateRoot.shiftSpringParams.damping
                    value: delegateRoot.shiftOffset

                    Component.onCompleted: snapTo(delegateRoot.shiftOffset)
                }

                onShiftOffsetChanged: {
                    shiftXSpring.retarget(shiftOffset);
                    shiftYSpring.retarget(shiftOffset);
                }

                transform: Translate {
                    x: root.isVertical ? 0 : shiftXSpring.value
                    y: root.isVertical ? shiftYSpring.value : 0
                }

                readonly property var record: root.recordOf(modelData)
                property bool isActive: {
                    if (root.useExtWorkspace || !root.useNativeWorkspaces)
                        return modelData === root.currentWorkspace;
                    return CompositorService.isCurrentWorkspace(record, root.currentWorkspace);
                }
                property bool isOccupied: root.useNativeWorkspaces && CompositorService.workspaceOccupied(record)
                property bool isPlaceholder: !!(record && record.placeholder)
                property bool isHovered: pillHover.hovered

                property bool loadedIsUrgent: false
                property bool isUrgent: root.useNativeWorkspaces ? CompositorService.workspaceUrgent(record, loadedIsUrgent) : (modelData?.urgent ?? false)
                readonly property var loadedIconData: {
                    if (isPlaceholder)
                        return null;
                    const name = record?.name;
                    if (!name)
                        return null;
                    const custom = SettingsData.getWorkspaceNameIcon(name);
                    if (custom || record.special !== true)
                        return custom;
                    return {
                        "type": "icon",
                        "value": "inbox"
                    };
                }
                readonly property bool loadedHasIcon: loadedIconData !== null
                property var loadedIcons: []

                readonly property int stableIconCount: {
                    if (!root.opt("showWorkspaceApps") || isPlaceholder)
                        return 0;

                    if (root.useAqueous)
                        return loadedIcons.length;

                    if (!root.useNativeWorkspaces)
                        return 0;

                    const wins = CompositorService.windowsOnWorkspace(delegateRoot.record);
                    const seen = {};
                    let groupedCount = 0;

                    for (let i = 0; i < wins.length; i++) {
                        const w = wins[i];
                        const appKey = w.app_id || w.appId || w.class || w.windowClass || "unknown";
                        if (!seen[appKey]) {
                            seen[appKey] = true;
                            groupedCount++;
                        }
                    }

                    return (root.opt("groupWorkspaceApps") && (!isActive || root.opt("groupActiveWorkspaceApps"))) ? groupedCount : wins.length;
                }

                readonly property real lineThickness: Math.max(Theme.spacingXXS, root.widgetThickness * (isActive ? root.activeSlimRatio : root.slimRatio))
                // a label scales the whole shape with the bar font, up to the widget thickness, so every style keeps its proportions
                readonly property bool labeled: !root.linesStyle && !root.opt("showWorkspaceApps") && (root.opt("showWorkspaceIndex") || root.opt("showWorkspaceName") || loadedHasIcon)
                readonly property real slimBase: widgetThickness * (isActive ? root.activeSlimRatio : root.slimRatio)
                readonly property real labelScale: labeled ? Math.min(root.widgetThickness / slimBase, Math.max(BarMetrics.indicatorLabelScale, Math.max(root.labelSize, BarMetrics.indicatorLabelMin) / BarMetrics.indicatorLabelRatio / slimBase)) : 1
                readonly property real crossBase: root.opt("showWorkspaceApps") ? Math.max(widgetThickness * root.compactRatio, root.appIconSize + Theme.spacingXS * 2) : slimBase * labelScale
                readonly property real primaryBase: root.dotsStyle ? crossBase : labelScale * (isActive ? Math.max(root.widgetThickness * root.activeRatio, root.appIconSize * root.activeIconRatio) : Math.max(root.widgetThickness * root.compactRatio, root.appIconSize * root.iconRatio))
                readonly property real baseWidth: root.isVertical ? (root.linesStyle ? lineThickness : crossBase) : primaryBase
                readonly property real baseHeight: root.isVertical ? primaryBase : (root.linesStyle ? lineThickness : crossBase)
                readonly property bool hasWorkspaceName: root.opt("showWorkspaceName") && record?.name && record.name !== ""
                readonly property real contentImplicitWidth: appIconsLoader.item?.contentWidth ?? 0
                readonly property real contentImplicitHeight: appIconsLoader.item?.contentHeight ?? 0

                // lines can't hold content, so it sits beside the line as an M3 tab underline facing the screen
                readonly property bool underline: root.linesStyle && contentImplicitWidth > 0 && contentImplicitHeight > 0
                readonly property bool lineAfterContent: root.axis?.edge !== "bottom" && root.axis?.edge !== "right"
                readonly property real underlineContentShift: underline ? (lineThickness + Theme.spacingXXS) / 2 * (lineAfterContent ? -1 : 1) : 0
                readonly property real underlineLineShift: underline ? ((root.isVertical ? contentImplicitWidth : contentImplicitHeight) + Theme.spacingXXS) / 2 * (lineAfterContent ? 1 : -1) : 0

                readonly property real iconsExtraWidth: {
                    if (!root.isVertical && root.opt("showWorkspaceApps") && stableIconCount > 0) {
                        const numIcons = Math.min(stableIconCount, root.opt("maxWorkspaceIcons"));
                        return numIcons * root.appIconSize + (numIcons > 0 ? (numIcons - 1) * Theme.spacingXS : 0) + (isActive ? Theme.spacingXS : 0);
                    }
                    return 0;
                }
                readonly property real iconsExtraHeight: {
                    if (root.isVertical && root.opt("showWorkspaceApps") && stableIconCount > 0) {
                        const numIcons = Math.min(stableIconCount, root.opt("maxWorkspaceIcons"));
                        return numIcons * root.appIconSize + (numIcons > 0 ? (numIcons - 1) * Theme.spacingXS : 0) + (isActive ? Theme.spacingXS : 0);
                    }
                    return 0;
                }

                readonly property real visualWidth: {
                    if (contentImplicitWidth <= 0 || (underline && root.isVertical))
                        return baseWidth + iconsExtraWidth;
                    if (root.isVertical)
                        return Math.min(root.widgetThickness, Math.max(baseWidth, contentImplicitWidth + Theme.spacingXS));
                    return Math.max(baseWidth + iconsExtraWidth, contentImplicitWidth + Theme.spacingL);
                }
                // the row reserves icon height for each label, so a horizontal label must not set the thickness
                readonly property real visualHeight: {
                    if (labeled && !root.isVertical)
                        return baseHeight;
                    if (contentImplicitHeight <= 0 || (underline && !root.isVertical))
                        return baseHeight + iconsExtraHeight;
                    const padding = root.isVertical && !labeled ? Theme.spacingS : Theme.spacingXS;
                    return Math.max(baseHeight + iconsExtraHeight, contentImplicitHeight + padding);
                }

                function colorFromMode(mode, fallbackColor, customColor, customFallbackColor) {
                    switch (mode) {
                    case "primary":
                    case "pri":
                        return Theme.primary;
                    case "primaryContainer":
                        return Theme.primaryContainer;
                    case "secondary":
                    case "sec":
                        return Theme.secondary;
                    case "secondaryContainer":
                        return Theme.secondaryContainer;
                    case "tertiary":
                    case "ter":
                        return Theme.tertiary;
                    case "tertiaryContainer":
                        return Theme.tertiaryContainer;
                    case "surfaceText":
                        return Theme.surfaceText;
                    case "s":
                        return Theme.surface;
                    case "sc":
                        return Theme.surfaceContainer;
                    case "sch":
                        return Theme.surfaceContainerHigh;
                    case "schh":
                        return Theme.surfaceContainerHighest;
                    case "error":
                    case "err":
                        return Theme.error;
                    case "custom":
                        return Theme.safeColor(customColor, customFallbackColor);
                    default:
                        return fallbackColor;
                    }
                }

                function effectiveColorMode(focusedMode, unfocusedMode) {
                    return root.useUnfocusedAppearance ? unfocusedMode : focusedMode;
                }

                function effectiveCustomColor(focusedCustom, unfocusedCustom) {
                    return root.useUnfocusedAppearance ? unfocusedCustom : focusedCustom;
                }

                readonly property string unfocusedColorMode: effectiveColorMode(root.opt("workspaceUnfocusedColorMode"), root.opt("workspaceUnfocusedMonitorUnfocusedColorMode"))
                readonly property color unfocusedColor: colorFromMode(unfocusedColorMode, Theme.surfaceTextAlpha, effectiveCustomColor(root.opt("workspaceUnfocusedCustomColor"), root.opt("workspaceUnfocusedMonitorUnfocusedCustomColor")), Theme.surfaceTextAlpha)

                readonly property string activeColorMode: effectiveColorMode(root.opt("workspaceColorMode"), root.opt("workspaceUnfocusedMonitorColorMode"))
                readonly property color activeColor: {
                    if (activeColorMode === "none")
                        return unfocusedColor;
                    return colorFromMode(activeColorMode, Theme.primary, effectiveCustomColor(root.opt("workspaceFocusedCustomColor"), root.opt("workspaceUnfocusedMonitorFocusedCustomColor")), Theme.primary);
                }

                readonly property string occupiedColorMode: effectiveColorMode(root.opt("workspaceOccupiedColorMode"), root.opt("workspaceUnfocusedMonitorOccupiedColorMode"))
                readonly property color occupiedColor: {
                    if (occupiedColorMode === "none")
                        return unfocusedColor;
                    return colorFromMode(occupiedColorMode, unfocusedColor, effectiveCustomColor(root.opt("workspaceOccupiedCustomColor"), root.opt("workspaceUnfocusedMonitorOccupiedCustomColor")), Theme.secondary);
                }

                readonly property string urgentColorMode: effectiveColorMode(root.opt("workspaceUrgentColorMode"), root.opt("workspaceUnfocusedMonitorUrgentColorMode"))
                readonly property color urgentColor: colorFromMode(urgentColorMode, Theme.error, effectiveCustomColor(root.opt("workspaceUrgentCustomColor"), root.opt("workspaceUnfocusedMonitorUrgentCustomColor")), Theme.error)

                readonly property color focusedBorderColor: colorFromMode(effectiveColorMode(root.opt("workspaceFocusedBorderColor"), root.opt("workspaceUnfocusedMonitorBorderColor")), Theme.primary, effectiveCustomColor(root.opt("workspaceFocusedBorderCustomColor"), root.opt("workspaceUnfocusedMonitorBorderCustomColor")), Theme.primary)

                readonly property bool focusedBorderEnabledForMonitor: root.useUnfocusedAppearance ? root.opt("workspaceUnfocusedMonitorBorderEnabled") : root.opt("workspaceFocusedBorderEnabled")
                readonly property int focusedBorderThicknessForMonitor: root.useUnfocusedAppearance ? root.opt("workspaceUnfocusedMonitorBorderThickness") : root.opt("workspaceFocusedBorderThickness")

                function getContrastingIconColor(bgColor) {
                    return Theme.isLightColor(bgColor, 0.4) ? Qt.rgba(0.15, 0.15, 0.15, 1) : Qt.rgba(0.8, 0.8, 0.8, 1);
                }

                readonly property color quickshellIconActiveColor: root.linesStyle ? activeColor : getContrastingIconColor(activeColor)
                readonly property color quickshellIconInactiveColor: getContrastingIconColor(unfocusedColor)

                function inkFromMode(mode, fill, fallbackInk) {
                    switch (mode) {
                    case "primary":
                    case "pri":
                        return Theme.onPrimary;
                    case "primaryContainer":
                        return Theme.onPrimaryContainer;
                    case "secondaryContainer":
                        return Theme.onSecondaryContainer;
                    case "tertiaryContainer":
                        return Theme.onTertiaryContainer;
                    case "error":
                    case "err":
                        return Theme.onError;
                    case "s":
                    case "sc":
                    case "sch":
                    case "schh":
                        return Theme.onSurface;
                    case "secondary":
                    case "sec":
                    case "tertiary":
                    case "ter":
                    case "surfaceText":
                    case "custom":
                    case "none":
                        return getContrastingIconColor(fill);
                    default:
                        return fallbackInk;
                    }
                }

                readonly property color activeInk: inkFromMode(activeColorMode, activeColor, Theme.onPrimary)
                readonly property color filledInk: {
                    if (isActive)
                        return activeInk;
                    if (isUrgent)
                        return inkFromMode(urgentColorMode, urgentColor, Theme.onError);
                    const idleInk = Theme.withAlpha(Theme.surfaceText, root.inactiveLabelAlpha);
                    if (isOccupied && !isHovered && occupiedColorMode !== "none")
                        return inkFromMode(occupiedColorMode, occupiedColor, idleInk);
                    return inkFromMode(unfocusedColorMode, unfocusedColor, idleInk);
                }
                readonly property color contentInk: {
                    // lines and inactive cards draw no fill, so their label sits on the bar
                    if (root.linesStyle || (root.cardsStyle && !isActive))
                        return isActive ? activeColor : isUrgent ? urgentColor : isPlaceholder ? Theme.surfaceTextAlpha : Theme.surfaceTextMedium;
                    if (isPlaceholder && !isActive && !isUrgent)
                        return Theme.surfaceTextAlpha;
                    return filledInk;
                }

                // a translucent fill gains a state layer on hover, an opaque one fades
                readonly property color hoverColor: Theme.withAlpha(unfocusedColor, unfocusedColor.a < 1 ? Math.min(1, unfocusedColor.a + Theme.stateLayerFocus) : root.hoverFadeAlpha)
                readonly property color requestedColor: isActive ? activeColor : isUrgent ? urgentColor : isPlaceholder ? Theme.surfaceTextLight : isHovered ? hoverColor : isOccupied ? occupiedColor : unfocusedColor

                property bool colorAnimationReady: false

                readonly property color displayColor: pillColor.value

                DColorAnimation {
                    id: pillColor
                    to: delegateRoot.requestedColor
                    animated: delegateRoot.colorAnimationReady
                }

                Item {
                    id: dragHandler
                    anchors.fill: parent
                    property bool dragging: false
                    property point dragStartPos: Qt.point(0, 0)
                    property real dragAxisOffset: 0
                    readonly property var rootWorkspaceList: root.workspaceList

                    onRootWorkspaceListChanged: {
                        if (!dragging)
                            return;
                        dragging = false;
                        dragAxisOffset = 0;
                        mouseArea.mousePressed = false;
                    }
                }

                HoverHandler {
                    id: pillHover
                    enabled: !isPlaceholder
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: !isPlaceholder
                    cursorShape: isPlaceholder ? Qt.ArrowCursor : (dragHandler.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor)
                    enabled: !isPlaceholder
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    property bool mousePressed: false

                    onPressed: mouse => {
                        if (mouse.button === Qt.LeftButton && CompositorService.workspaceReorderSupported && root.opt("workspaceDragReorder") && !isPlaceholder) {
                            mousePressed = true;
                            dragHandler.dragStartPos = Qt.point(mouse.x, mouse.y);
                        }
                    }

                    onPositionChanged: mouse => {
                        if (!mousePressed || !CompositorService.workspaceReorderSupported || !root.opt("workspaceDragReorder") || isPlaceholder)
                            return;

                        if (!dragHandler.dragging) {
                            const distance = root.isVertical ? Math.abs(mouse.y - dragHandler.dragStartPos.y) : Math.abs(mouse.x - dragHandler.dragStartPos.x);
                            if (distance > 5) {
                                dragHandler.dragging = true;
                                root.dragSourceIndex = index;
                                root.dragTargetIndex = index;
                            }
                        }

                        if (!dragHandler.dragging)
                            return;

                        const rawAxisOffset = root.isVertical ? (mouse.y - dragHandler.dragStartPos.y) : (mouse.x - dragHandler.dragStartPos.x);

                        const itemSize = (root.isVertical ? delegateRoot.height : delegateRoot.width) + workspaceRow.spacing;
                        const maxOffsetPositive = (root.workspaceList.length - 1 - index) * itemSize;
                        const maxOffsetNegative = -index * itemSize;
                        const axisOffset = Math.max(maxOffsetNegative, Math.min(maxOffsetPositive, rawAxisOffset));
                        dragHandler.dragAxisOffset = axisOffset;

                        const slotOffset = Math.round(axisOffset / itemSize);
                        const newTargetIndex = Math.max(0, Math.min(root.workspaceList.length - 1, index + slotOffset));

                        if (newTargetIndex !== root.dragTargetIndex) {
                            root.dragTargetIndex = newTargetIndex;
                        }
                    }

                    onReleased: mouse => {
                        const wasDragging = dragHandler.dragging;
                        const didReorder = wasDragging && root.dragTargetIndex >= 0 && root.dragTargetIndex !== root.dragSourceIndex;

                        if (didReorder) {
                            const sourceWs = root.recordOf(root.workspaceList[root.dragSourceIndex]);
                            const targetWs = root.recordOf(root.workspaceList[root.dragTargetIndex]);

                            if (sourceWs && targetWs && sourceWs.id !== undefined && targetWs.idx !== undefined) {
                                root.suppressShiftAnimation = true;
                                CompositorService.moveWorkspace(sourceWs, targetWs);
                                Qt.callLater(() => root.suppressShiftAnimation = false);
                            }
                        }

                        mousePressed = false;
                        dragHandler.dragging = false;
                        dragHandler.dragAxisOffset = 0;
                        root.dragSourceIndex = -1;
                        root.dragTargetIndex = -1;

                        if (wasDragging || isPlaceholder)
                            return;

                        if (mouse.button === Qt.LeftButton) {
                            if (delegateRoot.focusWindowAt(mouse.x, mouse.y))
                                return;
                            root.switchToWorkspaceByModelData(modelData);
                        } else if (mouse.button === Qt.RightButton) {
                            CompositorService.workspaceSecondaryAction(record, root.effectiveScreenName);
                            root.toggleHyprlandOverview();
                        }
                    }
                }

                Timer {
                    id: dataUpdateTimer
                    interval: 50
                    onTriggered: delegateRoot.loadData()
                }

                function loadData() {
                    if (isPlaceholder) {
                        delegateRoot.loadedIcons = [];
                        delegateRoot.loadedIsUrgent = false;
                        return;
                    }

                    delegateRoot.loadedIsUrgent = CompositorService.loadWorkspaceUrgent(delegateRoot.record);
                    delegateRoot.loadedIcons = root.opt("showWorkspaceApps") ? root.getWorkspaceIcons(delegateRoot.record) : [];
                }

                function updateAllData() {
                    dataUpdateTimer.restart();
                }

                function windowIdAt(x, y) {
                    const layout = appIconsLoader.item?.iconsLayout;
                    if (!layout)
                        return null;
                    const point = layout.mapFromItem(mouseArea, x, y);
                    const icon = layout.childAt(point.x, point.y);
                    if (root.useAqueous)
                        return icon?.windowId ? {
                            id: icon.windowId,
                            session: icon.windowSession
                        } : null;
                    return icon?.windowId ?? null;
                }

                function focusWindowAt(x, y) {
                    const winId = delegateRoot.windowIdAt(x, y);
                    if (!winId)
                        return false;
                    return CompositorService.focusWindow(winId);
                }

                width: root.isVertical ? root.widgetThickness : visualWidth
                height: root.isVertical ? visualHeight : root.widgetThickness

                readonly property real outlineWidth: dragHandler.dragging || isUrgent || isDropTarget ? Theme.outlineWidthFocused : 0
                readonly property color outlineColor: dragHandler.dragging ? Theme.primary : (isUrgent ? urgentColor : (isDropTarget ? Theme.primary : Theme.withAlpha(Theme.primary, 0)))

                Behavior on width {
                    enabled: !SettingsData.reduceMotion
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                    }
                }

                Behavior on height {
                    enabled: !SettingsData.reduceMotion
                    NumberAnimation {
                        duration: Theme.expressiveDurations.expressiveFastSpatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                    }
                }

                Rectangle {
                    id: focusedBorderRing
                    x: root.isVertical ? (root.widgetThickness - width) / 2 + delegateRoot.underlineLineShift : (parent.width - width) / 2
                    y: root.isVertical ? (parent.height - height) / 2 : (root.widgetThickness - height) / 2 + delegateRoot.underlineLineShift
                    width: {
                        const borderWidth = (delegateRoot.focusedBorderEnabledForMonitor && isActive && !isPlaceholder) ? delegateRoot.focusedBorderThicknessForMonitor : 0;
                        return delegateRoot.visualWidth + borderWidth * 2;
                    }
                    height: {
                        const borderWidth = (delegateRoot.focusedBorderEnabledForMonitor && isActive && !isPlaceholder) ? delegateRoot.focusedBorderThicknessForMonitor : 0;
                        return delegateRoot.visualHeight + borderWidth * 2;
                    }
                    topLeftRadius: visualContent.topLeftRadius + border.width
                    topRightRadius: visualContent.topRightRadius + border.width
                    bottomLeftRadius: visualContent.bottomLeftRadius + border.width
                    bottomRightRadius: visualContent.bottomRightRadius + border.width
                    color: "transparent"
                    border.width: (delegateRoot.focusedBorderEnabledForMonitor && isActive && !isPlaceholder) ? delegateRoot.focusedBorderThicknessForMonitor : 0
                    border.color: (delegateRoot.focusedBorderEnabledForMonitor && isActive && !isPlaceholder) ? focusedBorderColor : Theme.withAlpha(focusedBorderColor, 0)

                    Behavior on width {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on height {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on border.width {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on border.color {
                        enabled: !SettingsData.reduceMotion
                        ColorAnimation {
                            duration: Theme.expressiveDurations.expressiveEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                BarPillSurface {
                    id: visualContent
                    width: delegateRoot.visualWidth
                    height: delegateRoot.visualHeight
                    x: root.isVertical ? (root.widgetThickness - width) / 2 + delegateRoot.underlineLineShift : (parent.width - width) / 2
                    y: root.isVertical ? (parent.height - height) / 2 : (root.widgetThickness - height) / 2 + delegateRoot.underlineLineShift
                    thickness: Math.min(width, height)
                    style: BarMetrics.widgetStyle(root.barConfig)
                    vertical: root.isVertical
                    joinedStart: root.segmented && index > 0 && !isActive
                    joinedEnd: root.segmented && index < workspaceRepeater.count - 1 && !isActive
                    pressed: mouseArea.pressed
                    color: root.cardsStyle && !isActive ? "transparent" : delegateRoot.displayColor
                    radiusOverride: BarMetrics.indicatorRadius(root.indicatorStyle, thickness, root.roundness)
                    opacity: dragHandler.dragging ? root.dragOpacity : 1.0

                    border.width: root.cardsStyle && !isActive ? Math.max(Theme.outlineWidth, delegateRoot.outlineWidth) : delegateRoot.outlineWidth
                    border.color: delegateRoot.outlineWidth > 0 ? delegateRoot.outlineColor : delegateRoot.displayColor

                    // an empty frame is an empty desktop; a window block marks it occupied
                    Rectangle {
                        anchors.centerIn: parent
                        visible: root.cardsStyle && isOccupied && !isActive && !appIconsLoader.active
                        width: Math.round(parent.width * root.cardWindowRatio)
                        height: Math.round(parent.height * root.cardWindowRatio)
                        radius: Math.min(Theme.cornerRadiusXXS, height / 2)
                        color: delegateRoot.displayColor
                    }

                    transform: Translate {
                        x: root.isVertical ? 0 : (dragHandler.dragging ? dragHandler.dragAxisOffset : 0)
                        y: root.isVertical ? (dragHandler.dragging ? dragHandler.dragAxisOffset : 0) : 0
                    }

                    Behavior on opacity {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }

                    Behavior on width {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on height {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on border.width {
                        enabled: !SettingsData.reduceMotion
                        NumberAnimation {
                            duration: Theme.expressiveDurations.expressiveFastSpatial
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveFastSpatial
                        }
                    }

                    Behavior on border.color {
                        enabled: !SettingsData.reduceMotion
                        ColorAnimation {
                            duration: Theme.expressiveDurations.expressiveEffects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.expressiveCurves.expressiveEffects
                        }
                    }
                }

                Loader {
                    id: appIconsLoader
                    anchors.fill: parent
                    active: root.opt("showWorkspaceApps") || root.opt("showWorkspaceIndex") || root.opt("showWorkspaceName") || loadedHasIcon
                    opacity: visualContent.opacity
                    transform: Translate {
                        x: root.isVertical ? 0 : (dragHandler.dragging ? dragHandler.dragAxisOffset : 0)
                        y: root.isVertical ? (dragHandler.dragging ? dragHandler.dragAxisOffset : 0) : 0
                    }
                    sourceComponent: Item {
                        id: contentRoot
                        readonly property real contentWidth: contentRow.item?.implicitWidth ?? 0
                        readonly property real contentHeight: contentRow.item?.implicitHeight ?? 0
                        property alias iconsLayout: contentRow.item

                        Loader {
                            id: contentRow
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: root.isVertical ? delegateRoot.underlineContentShift : 0
                            anchors.verticalCenterOffset: root.isVertical ? 0 : delegateRoot.underlineContentShift
                            sourceComponent: root.isVertical ? columnLayout : rowLayout
                        }

                        Component {
                            id: rowLayout
                            Row {
                                spacing: Theme.spacingXS
                                visible: loadedIcons.length > 0 || root.opt("showWorkspaceIndex") || root.opt("showWorkspaceName") || loadedHasIcon

                                Item {
                                    visible: loadedHasIcon && loadedIconData?.type === "icon"
                                    width: wsIcon.width
                                    height: root.appIconSize

                                    DIcon {
                                        id: wsIcon
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: loadedIconData?.value ?? ""
                                        size: root.labelSize
                                        color: contentInk
                                        weight: (isActive && !isPlaceholder) ? 500 : 400
                                    }
                                }

                                Item {
                                    visible: loadedHasIcon && loadedIconData?.type === "text"
                                    // reserve the active weight so activating a workspace doesn't shift the bar
                                    width: Math.max(wsText.implicitWidth, Math.ceil(wsTextMetrics.advanceWidth))
                                    height: root.appIconSize

                                    StyledTextMetrics {
                                        id: wsTextMetrics
                                        text: wsText.text
                                        font.pixelSize: root.labelSize
                                        font.weight: Theme.fontWeightMedium
                                    }

                                    StyledText {
                                        id: wsText
                                        anchors.centerIn: parent
                                        text: loadedIconData?.value ?? ""
                                        color: contentInk
                                        font.pixelSize: root.labelSize
                                        font.weight: (isActive && !isPlaceholder) ? Theme.fontWeightMedium : Theme.fontWeight
                                    }
                                }

                                Item {
                                    visible: ((root.opt("showWorkspaceIndex") || root.opt("showWorkspaceName")) && !loadedHasIcon) || (loadedHasIcon && root.opt("showWorkspaceName") && hasWorkspaceName)
                                    width: Math.max(wsIndexText.implicitWidth, Math.ceil(wsIndexTextMetrics.advanceWidth))
                                    height: root.appIconSize

                                    StyledTextMetrics {
                                        id: wsIndexTextMetrics
                                        text: wsIndexText.text
                                        font.pixelSize: root.labelSize
                                        font.weight: Theme.fontWeightMedium
                                    }

                                    StyledText {
                                        id: wsIndexText
                                        anchors.centerIn: parent
                                        text: loadedHasIcon ? (record?.name ?? "") : root.getWorkspaceIndex(record, index)
                                        color: contentInk
                                        font.pixelSize: root.labelSize
                                        font.weight: (isActive && !isPlaceholder) ? Theme.fontWeightMedium : Theme.fontWeight
                                    }
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: loadedIcons.slice(0, root.opt("maxWorkspaceIcons"))
                                        comparisonMode: ObjectComparison.Structure
                                    }
                                    delegate: Item {
                                        width: root.appIconSize
                                        height: root.appIconSize
                                        readonly property var windowId: modelData.windowId
                                        readonly property string windowSession: modelData.windowSession || ""
                                        readonly property bool appHighlightActive: root.opt("workspaceActiveAppHighlightEnabled") && modelData.active
                                        readonly property color appBorderColor: appHighlightActive ? focusedBorderColor : Theme.primarySelected
                                        readonly property color appGlyphColor: appHighlightActive ? focusedBorderColor : Theme.primary
                                        readonly property real appOpacity: modelData.active || root.opt("workspaceUnfocusedAppsFullOpacity") ? 1.0 : rowAppHover.hovered ? root.hoveredAppAlpha : root.unfocusedAppAlpha

                                        IconImage {
                                            id: rowAppIcon
                                            anchors.fill: parent
                                            source: modelData.icon || ""
                                            opacity: appOpacity
                                            visible: !modelData.isQuickshell && !modelData.isSteamApp && status === Image.Ready
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !modelData.isQuickshell && !modelData.isSteamApp && rowAppIcon.status !== Image.Ready
                                            color: Theme.chipSurface
                                            radius: Math.min(Theme.cornerRadiusS, width / 2, height / 2)
                                            border.width: Theme.outlineWidth
                                            border.color: appBorderColor
                                            opacity: appOpacity

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: (modelData.fallbackText || "?").charAt(0).toUpperCase()
                                                font.pixelSize: parent.width * 0.45
                                                color: appGlyphColor
                                                font.weight: Theme.fontWeightMedium
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !modelData.isQuickshell && modelData.isSteamApp && rowSteamIcon.status !== Image.Ready
                                            color: Theme.chipSurface
                                            radius: Math.min(Theme.cornerRadiusS, width / 2, height / 2)
                                            border.width: Theme.outlineWidth
                                            border.color: appBorderColor
                                            opacity: appOpacity

                                            DIcon {
                                                anchors.centerIn: parent
                                                size: parent.width * 0.7
                                                name: "sports_esports"
                                                color: appGlyphColor
                                            }
                                        }

                                        IconImage {
                                            anchors.fill: parent
                                            source: modelData.icon
                                            opacity: appOpacity
                                            visible: modelData.isQuickshell
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                saturation: 0
                                                colorization: 1
                                                colorizationColor: appHighlightActive ? focusedBorderColor : (isActive ? quickshellIconActiveColor : quickshellIconInactiveColor)
                                            }
                                        }

                                        IconImage {
                                            id: rowSteamIcon
                                            anchors.fill: parent
                                            source: modelData.icon
                                            opacity: appOpacity
                                            visible: modelData.isSteamApp && modelData.icon
                                        }

                                        DIcon {
                                            anchors.centerIn: parent
                                            size: root.appIconSize
                                            name: "sports_esports"
                                            color: appHighlightActive ? focusedBorderColor : Theme.widgetTextColor
                                            opacity: appOpacity
                                            visible: modelData.isSteamApp && !modelData.icon
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: (rowAppIcon.visible || rowSteamIcon.visible || modelData.isQuickshell) && appHighlightActive
                                            color: "transparent"
                                            radius: Math.min(Theme.cornerRadiusS, width / 2, height / 2)
                                            border.width: Theme.outlineWidth
                                            border.color: focusedBorderColor
                                            z: 1
                                        }

                                        HoverHandler {
                                            id: rowAppHover
                                        }

                                        CountBadge {
                                            visible: modelData.count > 1 && !isActive
                                            text: modelData.count
                                            color: activeColor
                                            textColor: activeInk
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: -Theme.spacingXXS
                                            anchors.bottomMargin: -Theme.spacingXXS
                                            z: 2
                                        }
                                    }
                                }
                            }
                        }

                        Component {
                            id: columnLayout
                            Column {
                                spacing: Theme.spacingXS
                                visible: loadedIcons.length > 0 || root.opt("showWorkspaceIndex") || root.opt("showWorkspaceName") || loadedHasIcon

                                DIcon {
                                    visible: loadedHasIcon && loadedIconData?.type === "icon"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: loadedIconData?.value ?? ""
                                    size: root.labelSize
                                    color: contentInk
                                    weight: (isActive && !isPlaceholder) ? 500 : 400
                                }

                                StyledText {
                                    visible: loadedHasIcon && loadedIconData?.type === "text"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: loadedIconData?.value ?? ""
                                    color: contentInk
                                    font.pixelSize: root.labelSize
                                    font.weight: (isActive && !isPlaceholder) ? Theme.fontWeightMedium : Theme.fontWeight
                                }

                                StyledText {
                                    visible: (root.opt("showWorkspaceIndex") || root.opt("showWorkspaceName")) && !loadedHasIcon
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.getWorkspaceIndex(record, index)
                                    color: contentInk
                                    font.pixelSize: root.labelSize
                                    font.weight: (isActive && !isPlaceholder) ? Theme.fontWeightMedium : Theme.fontWeight
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: loadedIcons.slice(0, root.opt("maxWorkspaceIcons"))
                                        comparisonMode: ObjectComparison.Structure
                                    }
                                    delegate: Item {
                                        width: root.appIconSize
                                        height: root.appIconSize
                                        readonly property var windowId: modelData.windowId
                                        readonly property string windowSession: modelData.windowSession || ""
                                        readonly property bool appHighlightActive: root.opt("workspaceActiveAppHighlightEnabled") && modelData.active
                                        readonly property color appBorderColor: appHighlightActive ? focusedBorderColor : Theme.primarySelected
                                        readonly property color appGlyphColor: appHighlightActive ? focusedBorderColor : Theme.primary
                                        readonly property real appOpacity: modelData.active || root.opt("workspaceUnfocusedAppsFullOpacity") ? 1.0 : colAppHover.hovered ? root.hoveredAppAlpha : root.unfocusedAppAlpha

                                        IconImage {
                                            id: colAppIcon
                                            anchors.fill: parent
                                            source: modelData.icon || ""
                                            opacity: appOpacity
                                            visible: !modelData.isQuickshell && !modelData.isSteamApp && status === Image.Ready
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !modelData.isQuickshell && !modelData.isSteamApp && colAppIcon.status !== Image.Ready
                                            color: Theme.chipSurface
                                            radius: Math.min(Theme.cornerRadiusS, width / 2, height / 2)
                                            border.width: Theme.outlineWidth
                                            border.color: appBorderColor
                                            opacity: appOpacity

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: (modelData.fallbackText || "?").charAt(0).toUpperCase()
                                                font.pixelSize: parent.width * 0.45
                                                color: appGlyphColor
                                                font.weight: Theme.fontWeightMedium
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: !modelData.isQuickshell && modelData.isSteamApp && colSteamIcon.status !== Image.Ready
                                            color: Theme.chipSurface
                                            radius: Math.min(Theme.cornerRadiusS, width / 2, height / 2)
                                            border.width: Theme.outlineWidth
                                            border.color: appBorderColor
                                            opacity: appOpacity

                                            DIcon {
                                                anchors.centerIn: parent
                                                size: parent.width * 0.7
                                                name: "sports_esports"
                                                color: appGlyphColor
                                            }
                                        }

                                        IconImage {
                                            anchors.fill: parent
                                            source: modelData.icon
                                            opacity: appOpacity
                                            visible: modelData.isQuickshell
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                saturation: 0
                                                colorization: 1
                                                colorizationColor: appHighlightActive ? focusedBorderColor : (isActive ? quickshellIconActiveColor : quickshellIconInactiveColor)
                                            }
                                        }

                                        IconImage {
                                            id: colSteamIcon
                                            anchors.fill: parent
                                            source: modelData.icon
                                            opacity: appOpacity
                                            visible: modelData.isSteamApp && modelData.icon
                                        }

                                        DIcon {
                                            anchors.centerIn: parent
                                            size: root.appIconSize
                                            name: "sports_esports"
                                            color: appHighlightActive ? focusedBorderColor : Theme.widgetTextColor
                                            opacity: appOpacity
                                            visible: modelData.isSteamApp && !modelData.icon
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: (colAppIcon.visible || colSteamIcon.visible || modelData.isQuickshell) && appHighlightActive
                                            color: "transparent"
                                            radius: Math.min(Theme.cornerRadiusS, width / 2, height / 2)
                                            border.width: Theme.outlineWidth
                                            border.color: focusedBorderColor
                                            z: 1
                                        }

                                        HoverHandler {
                                            id: colAppHover
                                        }

                                        CountBadge {
                                            visible: modelData.count > 1 && !isActive
                                            text: modelData.count
                                            color: activeColor
                                            textColor: activeInk
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.rightMargin: -Theme.spacingXXS
                                            anchors.bottomMargin: -Theme.spacingXXS
                                            z: 2
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Component.onCompleted: {
                    updateAllData();
                    delegateRoot.colorAnimationReady = true;
                }

                Connections {
                    target: CompositorService
                    function onSortedToplevelsChanged() {
                        delegateRoot.updateAllData();
                    }
                    function onWorkspaceStateChanged() {
                        delegateRoot.updateAllData();
                    }
                }
                readonly property var rootCurrentWorkspace: root.currentWorkspace
                // isActive flips at once, so the icons that size the pill must follow in the same frame
                onRootCurrentWorkspaceChanged: {
                    dataUpdateTimer.stop();
                    loadData();
                }
                readonly property bool iconIndexReady: IconThemeService.ready
                onIconIndexReadyChanged: updateAllData()
                Connections {
                    target: SettingsData
                    function onBarConfigsChanged() {
                        delegateRoot.updateAllData();
                    }
                    function onWorkspaceNameIconsChanged() {
                        delegateRoot.updateAllData();
                    }
                    function onAppIdSubstitutionsChanged() {
                        delegateRoot.updateAllData();
                    }
                }
                property var _extWindowsetsTrigger: root.useExtWorkspace ? WindowManager.windowsets : null
                on_ExtWindowsetsTriggerChanged: {
                    if (root.useExtWorkspace)
                        delegateRoot.updateAllData();
                }
            }
        }
    }
}
