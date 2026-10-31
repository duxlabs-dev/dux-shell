pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Modals.Clipboard
import qs.Modals.DLauncherV2.Components
import qs.Modules.ControlCenter
import qs.Modules.DBar
import qs.Modules.DDash

QtObject {
    id: root

    property string interactionMode: "click"
    property bool hoverExpanded: false
    property bool inputSuspended: false
    property bool expanded: false
    property bool pointerInside: false
    // A right-click face swap resizes the island under the pointer; hover stays off until it leaves.
    property bool hoverHeld: false
    property int slotHoverCount: 0
    readonly property bool slotHovered: slotHoverCount > 0
    property bool keyboardDismissRequested: false
    property string activeActivity: "home"
    property bool mediaAvailable: false
    property bool mediaPreferred: false
    property bool mediaAutoSwitch: false
    property bool launcherCycleEnabled: false
    property bool launcherSessionActive: false
    property bool launcherInputFocused: false
    onLauncherInputFocusedChanged: {
        if (launcherInputFocused)
            hoverExpanded = false;
    }
    property var transientSurfaces: null
    readonly property bool transientSurfacesActive: transientSurfaces?.active ?? false
    onTransientSurfacesActiveChanged: {
        if (!transientSurfacesActive)
            return;
        hoverExpanded = false;
        hoverCloseTimer.stop();
    }
    property string launcherPendingQuery: ""
    property string launcherPendingMode: ""
    property string controlCenterPendingSection: ""
    property bool notificationExpandAllowed: false
    property bool keyboardYielded: false
    property real alongOffset: 0
    property real outerGap: 8
    property var barConfig: null
    property var screen: null
    property string edge: "top"
    // Screen position of the host window origin; item coordinates inside the island are window-relative.
    property real sectionOriginX: 0
    property real sectionOriginY: 0
    readonly property bool isVertical: edge === "left" || edge === "right"
    readonly property bool farEdge: edge === "bottom" || edge === "right"
    property real cornerRadius: 34
    property real pillRadius: cornerRadius
    readonly property real edgeCornerRadius: Math.round(cornerRadius * 0.75)
    property bool freeMode: false
    property bool dotMode: false
    // Hosted in a bar: the sheet is flush with the band, so its near corners stay square.
    property bool embedded: false
    property bool notch: false
    property real dotSize: 48
    property real compactThickness: 38
    property string batteryStyle: "duo"
    property bool mediaClockVisible: true
    property bool mediaLyrics: false
    property bool dashTabs: false
    // Carries tab-bar focus across a face switch.
    property bool dashNavigationFocused: false

    onExpandedChanged: {
        if (!expanded)
            dashNavigationFocused = false;
    }
    property int transientTimeout: 2200
    property int notificationTimeout: 5000
    property string transientReturnActivity: ""
    property string suspendedActivity: ""
    property bool suspendedExpanded: false
    property bool suspendedKeyboardDismissRequested: false
    property int hoverOpenDelay: 150
    property int hoverCloseDelay: 150
    property int mediaReturnDelay: 1800
    readonly property real controlCenterMaxHeight: dashboardAvailableHeight
    property string editingActivity: ""
    property real editRoom: 0
    // The bar host grants the room once its surface has presented a frame at the grown size.
    property bool editRoomGranted: false
    readonly property real controlCenterSheetInset: CcMetrics.islandInset * 2
    readonly property int controlCenterColumnCap: CcMetrics.columnCapFor(dashboardAvailableWidth - controlCenterSheetInset - PopoutMetrics.editOverflow * 2)
    readonly property int controlCenterColumns: Math.min(CcMetrics.gridColumns, controlCenterColumnCap)
    readonly property real controlCenterSheetWidth: CcMetrics.sheetWidthFor(controlCenterColumns)
    readonly property real controlCenterMaxWidth: CcMetrics.sheetWidthFor(editingActivity === "controlcenter" ? controlCenterColumnCap : controlCenterColumns) + controlCenterSheetInset
    readonly property real controlCenterHeight: controlCenterHeightFor(editRoomGranted && editingActivity === "controlcenter")

    property bool homeCompactTight: false
    readonly property bool compactTight: homeCompactTight && !dotMode
    readonly property bool compactDense: compactTight || compactThickness < 40
    readonly property real compactFaceThickness: compactTight ? Math.max(16, Math.min(32, compactThickness - 8)) : BarMetrics.compactFaceThickness(compactThickness)
    readonly property real compactIconSize: Math.max(14, Math.min(32, (compactTight ? compactFaceThickness : compactThickness) - 8))

    property int unreadNotificationCount: 0
    readonly property bool homeNotificationBadge: (root.dotMode || SettingsData.islandHomeGroupEnabled(root.barConfig, "notifications")) && unreadNotificationCount > 0
    readonly property bool homeWeatherEnabled: SettingsData.weatherEnabled && SettingsData.islandHomeGroupEnabled(root.barConfig, "weather")
    readonly property real homeSlotMargin: homeCompactTight ? Theme.spacingS : Theme.spacingM
    property real homeContentLength: 200
    property real mediaContentLength: 360
    property real dashboardAvailableWidth: 1920
    property real dashboardAvailableHeight: 1080
    readonly property int dashboardColumnCap: DashMetrics.columnCapFor(dashboardAvailableWidth - PopoutMetrics.editOverflow * 2, SettingsData.showWeekNumber)
    readonly property real dashboardMaxWidth: Math.min(dashboardAvailableWidth, DashMetrics.widthFor(SettingsData.showWeekNumber, undefined, editingActivity !== "" ? dashboardColumnCap : DashRegistry.widestPanelColumns))
    property var dashboardContentHeights: ({})
    // Plugin tabs have no island face, and the media face needs a player.
    readonly property var dashTabIds: dashTabs ? DashRegistry.navigationIds.filter(id => DashRegistry.isAction(id) || dashActivityFor(id) !== "") : []
    readonly property var dashTabBarModel: dashTabIds.length === 0 ? [] : DashRegistry.tabBarModel.filter((_, index) => dashTabIds.indexOf(DashRegistry.navigationIds[index]) >= 0)
    readonly property real dashChromeHeight: DashMetrics.islandChromeHeight(dashTabIds.length > 1 ? Theme.navigationHeight : 0)
    readonly property real editSurfaceHeight: editRoom <= 0 ? 0 : editingActivity === "controlcenter" ? controlCenterHeightFor(true) : dashboardHeightFor(editingActivity, true)
    readonly property real dashboardHeight: Math.min(dashboardAvailableHeight, Math.max(DashMetrics.tabDefaultHeight + root.dashChromeHeight, ...Object.values(dashboardContentHeights)))
    readonly property int dashboardRowBudget: Math.max(DashMetrics.minimumTabRows, Math.floor((dashboardAvailableHeight - DashMetrics.islandEditChromeHeight + DashMetrics.gridGap) / (DashMetrics.gridRowUnit + DashMetrics.gridGap)))
    readonly property real mediaCompactMaxLength: 360
    property real notificationContentLength: 0
    readonly property real notificationCompactMinLength: isVertical ? compactFaceThickness : (compactDense ? 200 : 240)
    readonly property real notificationCompactMaxLength: mediaCompactMaxLength

    signal sessionStarted(string activityId)

    function setHomeContentLength(length) {
        const next = Math.ceil(length);
        if (!isFinite(next) || next <= 0 || Math.abs(next - homeContentLength) < 2)
            return;
        homeContentLength = next;
    }

    function setNotificationContentLength(length) {
        const next = Math.ceil(length);
        if (!isFinite(next) || next <= 0 || Math.abs(next - notificationContentLength) < 2)
            return;
        notificationContentLength = next;
    }

    function setDashboardContentHeight(activityId, height) {
        const next = Math.ceil(height);
        if (!isFinite(next) || next <= 0 || dashboardContentHeights[activityId] === next)
            return;
        dashboardContentHeights = Object.assign({}, dashboardContentHeights, {
            [activityId]: next
        });
    }

    function dashEntryIdFor(activityId) {
        switch (activityId) {
        case "home":
            return DashRegistry.overviewId;
        case "notificationcenter":
            return "notifications";
        }
        return activityId;
    }

    function dashActivityFor(entryId) {
        switch (entryId) {
        case DashRegistry.overviewId:
            return "home";
        case "notifications":
            return "notificationcenter";
        case "media":
            return mediaAvailable ? "media" : "";
        case "weather":
        case "wellbeing":
        case "wallpaper":
            return entryId;
        }
        return "";
    }

    function dashTabsShownFor(activityId) {
        return dashTabIds.length > 1 && dashTabIds.indexOf(dashEntryIdFor(activityId)) >= 0;
    }

    function requestDashTab(entryId, fromNavigation) {
        dashNavigationFocused = fromNavigation === true;
        if (entryId === "notifications")
            return requestNotificationCenter(false);
        const activityId = dashActivityFor(entryId);
        return activityId !== "" && requestActivity(activityId, true, true);
    }

    function cycleDashTab(direction, fromNavigation) {
        const ids = DashRegistry.visibleTabIds.filter(id => dashActivityFor(id) !== "");
        if (ids.length === 0)
            return false;
        const pos = ids.indexOf(dashEntryIdFor(activeActivity));
        const next = ids[pos < 0 ? (direction > 0 ? 0 : ids.length - 1) : (pos + direction + ids.length) % ids.length];
        return next === dashEntryIdFor(activeActivity) || requestDashTab(next, fromNavigation);
    }

    function dashboardWidthFor(activityId) {
        return Math.min(dashboardAvailableWidth, DashMetrics.widthFor(SettingsData.showWeekNumber, undefined, DashMetrics.panelColumnsFor(dashEntryIdFor(activityId))));
    }

    function dashboardHeightFor(activityId, withEditRoom) {
        const minimum = DashMetrics.panelHeightFor(dashEntryIdFor(activityId));
        const chrome = DashMetrics.islandChromeHeight(dashTabsShownFor(activityId) ? Theme.navigationHeight : 0);
        const height = Math.max(minimum + chrome, dashboardContentHeights[activityId] ?? 0);
        return Math.min(dashboardAvailableHeight, height + (withEditRoom ? root.editRoom : 0));
    }

    function controlCenterHeightFor(withEditRoom) {
        return Math.max(CcMetrics.minHeight + controlCenterSheetInset, Math.min(controlCenterMaxHeight, destinationContentHeight("controlcenter") + (withEditRoom ? root.editRoom : 0)));
    }

    function dashboardTargetFor(activityId) {
        return sheetTarget(dashboardWidthFor(activityId), dashboardHeightFor(activityId, root.editRoomGranted && root.editingActivity === activityId));
    }

    function setMediaContentLength(length) {
        const next = Math.ceil(Math.min(root.mediaCompactMaxLength, length));
        if (!isFinite(next) || next <= 0 || Math.abs(next - mediaContentLength) < 2)
            return;
        mediaContentLength = next;
    }

    property real powerMenuContentWidth: 0

    function setPowerMenuContentWidth(width) {
        const next = Math.ceil(width);
        if (!isFinite(next) || next <= 0 || Math.abs(next - powerMenuContentWidth) < 2)
            return;
        powerMenuContentWidth = next;
    }

    readonly property var destinations: ["launcher", "controlcenter", "wallpaper", "weather", "wellbeing", "notificationcenter", "clipboard", "powermenu"]
    readonly property var blankClickOwners: ["launcher", "controlcenter", "wallpaper", "notificationcenter", "clipboard", "powermenu"]
    readonly property var destinationDefaults: ({
            "launcher": {
                "contentLength": 160,
                "contentHeight": 0
            },
            "controlcenter": {
                "contentLength": 180,
                "contentHeight": 420
            },
            "wallpaper": {
                "contentLength": 150,
                "contentHeight": 0
            },
            "weather": {
                "contentLength": 130,
                "contentHeight": 0
            },
            "wellbeing": {
                "contentLength": 130,
                "contentHeight": 0
            },
            "notificationcenter": {
                "contentLength": 170,
                "contentHeight": 320
            },
            "clipboard": {
                "contentLength": 150,
                "contentHeight": 0
            },
            "powermenu": {
                "contentLength": 150,
                "contentHeight": 0
            }
        })
    property var destinationState: root.freshDestinationState()
    property int destinationRevision: 0
    property int requestedRevision: 0

    function freshDestinationState() {
        const state = {};
        for (const id of destinations) {
            state[id] = {
                "requested": false,
                "ready": false,
                "pending": false,
                "pendingKeyboardFocus": false,
                "contentLength": destinationDefaults[id].contentLength,
                "contentHeight": destinationDefaults[id].contentHeight
            };
        }
        return state;
    }

    function destinationEntry(activityId) {
        destinationRevision;
        return destinationState[activityId] ?? null;
    }

    function isDestination(activityId) {
        return destinations.indexOf(activityId) !== -1;
    }

    function visualsRequested(activityId) {
        requestedRevision;
        return destinationState[activityId]?.requested ?? false;
    }

    function visualsReady(activityId) {
        return destinationEntry(activityId)?.ready ?? false;
    }

    function destinationContentLength(activityId) {
        return destinationEntry(activityId)?.contentLength ?? 0;
    }

    function destinationContentHeight(activityId) {
        return destinationEntry(activityId)?.contentHeight ?? 0;
    }

    function setDestinationContentLength(activityId, length) {
        if (isSystemActivity(activityId)) {
            setSystemStateContentLength(length);
            return;
        }
        const entry = destinationState[activityId];
        const next = Math.ceil(length);
        if (!entry || !isFinite(next) || next <= 0 || Math.abs(next - entry.contentLength) < 2)
            return;
        entry.contentLength = next;
        destinationRevision++;
    }

    function setEditing(activityId, editing, room = 0) {
        if (editing) {
            editRoomGranted = false;
            editingActivity = activityId;
            editRoom = room;
            // Option sheets open child popups; a hover peek would collapse under them
            hoverExpanded = false;
            hoverCloseTimer.stop();
        } else if (editingActivity === activityId) {
            editRoomGranted = false;
            editRoom = 0;
            editingActivity = "";
        }
    }

    function setDestinationContentHeight(activityId, height) {
        const entry = destinationState[activityId];
        const next = Math.round(height);
        if (!entry || !isFinite(next) || Math.abs(next - entry.contentHeight) < 1)
            return;
        entry.contentHeight = next;
        destinationRevision++;
    }

    function setVisualsReady(activityId, ready) {
        const entry = destinationState[activityId];
        if (!entry || entry.ready === ready)
            return;
        entry.ready = ready;
        destinationRevision++;
    }

    function markVisualsReady(activityId) {
        const entry = destinationState[activityId];
        if (!entry)
            return;
        const pending = entry.pending;
        entry.ready = true;
        entry.pending = false;
        destinationRevision++;
        if (!pending)
            return;
        requestActivity(activityId, true, entry.pendingKeyboardFocus);
    }

    function clearPendingRequests(exceptId) {
        let changed = false;
        for (const id of destinations) {
            const entry = destinationState[id];
            if (id === exceptId || !entry.pending)
                continue;
            entry.pending = false;
            changed = true;
        }
        if (changed)
            destinationRevision++;
    }

    // The launcher stays loaded once built, so reopening never waits on a rebuild.
    function keepsVisuals(activityId) {
        return activityId === "launcher" && !SettingsData.dankLauncherV2UnloadOnClose && destinationState[activityId].ready;
    }

    function releaseIdleVisuals() {
        for (const id of destinations) {
            if (expanded && activeActivity === id)
                continue;
            const entry = destinationState[id];
            if (root.keepsVisuals(id) || (!entry.requested && !entry.ready))
                continue;
            visualsReleaseTimer.restart();
            return;
        }
        visualsReleaseTimer.stop();
    }

    function dropIdleVisuals() {
        for (const id of destinations) {
            if (expanded && activeActivity === id)
                continue;
            if (destinationState[id].pending || root.keepsVisuals(id))
                continue;
            dropVisuals(id);
        }
    }

    function dropVisuals(activityId) {
        const entry = destinationState[activityId];
        entry.requested = false;
        entry.ready = false;
        entry.pending = false;
        entry.contentHeight = destinationDefaults[activityId].contentHeight;
        destinationRevision++;
        requestedRevision++;
        switch (activityId) {
        case "launcher":
            launcherSessionActive = false;
            launcherInputFocused = false;
            launcherPendingQuery = "";
            launcherPendingMode = "";
            return;
        case "controlcenter":
            controlCenterPendingSection = "";
            return;
        case "wallpaper":
        case "clipboard":
            keyboardYielded = false;
            return;
        }
    }

    readonly property real destinationCompactEndPad: root.isVertical ? Theme.spacingS : Math.max(root.compactFaceThickness / 2, Theme.spacingM) + Theme.spacingS

    function destinationCompactLength(activityId) {
        return Math.ceil(Math.max(root.compactFaceThickness, destinationContentLength(activityId) + root.destinationCompactEndPad * 2));
    }

    function homeGroups(side) {
        const layout = SettingsData.getIslandHomeLayout(root.barConfig);
        const clock = layout.findIndex(g => g.id === "clock");
        const groups = side === "left" ? layout.slice(0, clock) : layout.slice(clock + 1);
        return groups.filter(g => g.enabled).map(g => g.id);
    }

    readonly property var homeLeftGroups: homeGroups("left")
    readonly property var homeRightGroups: homeGroups("right")
    property string homeStatusContent: "battery"
    property string homeClockDisplay: "both"
    property string homeVolumeDisplay: "both"
    property string homeBrightnessDisplay: "both"

    readonly property real homeCompactLength: Math.ceil(homeSlotMargin * 2 + Math.max(homeContentLength, 1))
    readonly property real mediaCompactLength: Math.ceil(Math.max(1, mediaContentLength))

    // Corners touching the attached screen edge stay tighter than the ones facing the desktop.
    function sheetRadii() {
        if (root.freeMode)
            return [root.cornerRadius, root.cornerRadius, root.cornerRadius, root.cornerRadius];
        return root.edgeRadii(root.embedded || root.notch ? 0 : root.edgeCornerRadius, root.cornerRadius);
    }

    // [topLeft, topRight, bottomLeft, bottomRight] with `near` on the corners touching the edge.
    function edgeRadii(near, far) {
        switch (root.edge) {
        case "bottom":
            return [far, far, near, near];
        case "left":
            return [near, far, near, far];
        case "right":
            return [far, near, far, near];
        }
        return [near, near, far, far];
    }

    function pillTarget(alongSize, crossSize) {
        const radius = Math.min(crossSize / 2, root.pillRadius);
        const radii = root.edgeRadii(root.notch ? 0 : radius, radius);
        return {
            "width": root.isVertical ? crossSize : alongSize,
            "height": root.isVertical ? alongSize : crossSize,
            "offsetAlong": root.alongOffset,
            "offsetCross": root.outerGap,
            "topLeftRadius": radii[0],
            "topRightRadius": radii[1],
            "bottomLeftRadius": radii[2],
            "bottomRightRadius": radii[3]
        };
    }

    function sheetTarget(width, height) {
        const radii = root.sheetRadii();
        return {
            "sheet": true,
            "width": width,
            "height": height,
            "offsetAlong": root.alongOffset,
            "offsetCross": root.outerGap,
            "topLeftRadius": radii[0],
            "topRightRadius": radii[1],
            "bottomLeftRadius": radii[2],
            "bottomRightRadius": radii[3]
        };
    }

    readonly property var dotCompactTarget: ({
            "width": root.dotSize,
            "height": root.dotSize,
            "offsetAlong": root.alongOffset,
            "offsetCross": root.outerGap,
            "topLeftRadius": root.dotSize / 2,
            "topRightRadius": root.dotSize / 2,
            "bottomLeftRadius": root.dotSize / 2,
            "bottomRightRadius": root.dotSize / 2
        })
    readonly property var systemLevelActivities: ["volume", "brightness", "mic"]
    readonly property var systemStateActivities: ["capslock", "powerprofile", "idleinhibitor", "charging"]
    readonly property var systemActivities: systemLevelActivities.concat(systemStateActivities)
    readonly property var dotTransientActivities: ["notification"].concat(systemActivities)
    function isSystemActivity(activityId) {
        return root.systemActivities.indexOf(activityId) !== -1;
    }
    // Transients keep their island pill so the dot can still show a notification or a level.
    function usesDotFace(activityId) {
        return root.dotMode && root.dotTransientActivities.indexOf(activityId) === -1;
    }
    readonly property var homeCompactTarget: pillTarget(homeCompactLength, compactFaceThickness)
    readonly property var mediaCompactTarget: pillTarget(mediaCompactLength, compactFaceThickness)
    readonly property var homeExpandedTarget: dashboardTargetFor("home")
    readonly property var mediaExpandedTarget: dashboardTargetFor("media")
    readonly property real launcherMaxHeight: Math.min(dashboardAvailableHeight, LauncherMetrics.sizeHeight(SettingsData.dankLauncherV2Size, LauncherMetrics.islandEdgeInset, false))
    readonly property real launcherContentHeight: destinationContentHeight("launcher")
    readonly property var launcherExpandedTarget: sheetTarget(Math.min(dashboardAvailableWidth, LauncherMetrics.sizeWidth(SettingsData.dankLauncherV2Size)), launcherContentHeight > 0 ? Math.min(launcherMaxHeight, launcherContentHeight) : launcherMaxHeight)
    readonly property var controlCenterExpandedTarget: sheetTarget(controlCenterSheetWidth + controlCenterSheetInset, controlCenterHeight)
    readonly property var systemCompactTarget: pillTarget(root.isVertical ? 240 : (SettingsData.osdAlwaysShowValue ? 330 : 282), compactFaceThickness)
    property real systemStateContentLength: 0
    readonly property var systemStateCompactTarget: pillTarget(Math.ceil(Math.max(compactFaceThickness, systemStateContentLength + destinationCompactEndPad * 2)), compactFaceThickness)
    readonly property var systemExpandedTarget: sheetTarget(460, 176)
    readonly property var notificationCompactTarget: pillTarget(Math.ceil(Math.max(notificationCompactMinLength, Math.min(notificationCompactMaxLength, notificationContentLength))), compactFaceThickness)
    readonly property var notificationExpandedTarget: sheetTarget(520, 220)
    readonly property var notificationCenterExpandedTarget: dashboardTargetFor("notificationcenter")
    readonly property var clipboardExpandedTarget: sheetTarget(Math.min(dashboardAvailableWidth, ClipboardConstants.sizeWidth(SettingsData.clipboardSize)), Math.min(dashboardAvailableHeight, ClipboardConstants.sizeHeight(SettingsData.clipboardSize)))
    readonly property var powerMenuExpandedTarget: sheetTarget(Math.max(1, Math.min(dashboardAvailableWidth, powerMenuContentWidth)), Math.max(1, Math.min(dashboardAvailableHeight, destinationContentHeight("powermenu"))))

    readonly property bool systemActivityActive: isSystemActivity(activeActivity)
    readonly property bool notificationActive: activeActivity === "notification"
    readonly property bool outsideClickCollapses: expanded && !notificationActive
    readonly property bool notificationHeldForSystem: root.systemActivityActive && root.transientReturnActivity === "notification"
    readonly property bool transientActive: systemActivityActive || notificationActive
    readonly property bool timeoutSuspended: pointerInside || (expanded && !notificationActive)
    readonly property bool activityOwnsBlankClicks: blankClickOwners.indexOf(activeActivity) !== -1
    readonly property bool hoverExpandEnabled: root.interactionMode === "hybrid" && !root.systemActivityActive
    function compactTargetFor(activityId) {
        if (root.usesDotFace(activityId))
            return dotCompactTarget;
        switch (activityId) {
        case "notification":
            return notificationCompactTarget;
        case "media":
            return mediaCompactTarget;
        case "home":
            return homeCompactTarget;
        }
        if (systemLevelActivities.indexOf(activityId) !== -1)
            return systemCompactTarget;
        if (systemStateActivities.indexOf(activityId) !== -1)
            return systemStateCompactTarget;
        return isDestination(activityId) ? pillTarget(destinationCompactLength(activityId), compactFaceThickness) : homeCompactTarget;
    }

    readonly property var compactTarget: compactTargetFor(activeActivity)
    function expandedTargetFor(activityId) {
        switch (activityId) {
        case "home":
            return homeExpandedTarget;
        case "notification":
            return notificationExpandedTarget;
        case "launcher":
            return launcherExpandedTarget;
        case "controlcenter":
            return controlCenterExpandedTarget;
        case "notificationcenter":
            return notificationCenterExpandedTarget;
        case "clipboard":
            return clipboardExpandedTarget;
        case "powermenu":
            return powerMenuExpandedTarget;
        case "media":
            return mediaExpandedTarget;
        }
        return isSystemActivity(activityId) ? systemExpandedTarget : dashboardTargetFor(activityId);
    }

    readonly property var expandedTarget: expandedTargetFor(activeActivity)
    readonly property var targetDescriptor: expanded ? expandedTarget : compactTarget

    function syncNotificationTimeout(restart) {
        if (!notificationActive || timeoutSuspended || notificationTimeout <= 0) {
            notificationTimer.stop();
            return;
        }
        if (restart === true || !notificationTimer.running)
            notificationTimer.restart();
    }

    onNotificationTimeoutChanged: syncNotificationTimeout(true)

    function syncTransientTimeout(restart) {
        if (!systemActivityActive || timeoutSuspended) {
            transientTimer.stop();
            return;
        }
        if (restart === true || !transientTimer.running)
            transientTimer.restart();
    }

    function updateMediaAvailability(available) {
        if (available) {
            // A return inside the delay is a blip (track change, player switch), not a new start.
            const blip = !mediaAvailable && mediaReturnTimer.running;
            const started = !mediaAvailable && !blip;
            mediaReturnTimer.stop();
            mediaAvailable = true;
            if (started && mediaAutoSwitch)
                autoSwitchToMedia();
            else if (blip && mediaPreferred && !expanded && activeActivity === "home")
                activeActivity = "media";
            return;
        }

        if (!mediaAvailable)
            return;
        mediaAvailable = false;
        mediaReturnTimer.restart();
    }

    // Set directly: requestActivity would drop a destination open still waiting for its visuals.
    function autoSwitchToMedia() {
        if (activeActivity === "home" && !expanded && !(pointerInside && hoverExpandEnabled))
            activeActivity = "media";
        else if (systemActivityActive && transientReturnActivity === "home")
            transientReturnActivity = "media";
        else if ((notificationActive || notificationHeldForSystem) && suspendedActivity === "home" && !suspendedExpanded)
            suspendedActivity = "media";
        else
            return;
        mediaPreferred = true;
    }

    onInputSuspendedChanged: {
        if (!inputSuspended)
            return;
        hoverExpanded = false;
        hoverOpenTimer.stop();
        hoverCloseTimer.stop();
        keyboardDismissRequested = false;
        expanded = false;
        keyboardYielded = false;
        launcherSessionActive = false;
        clearPendingRequests("");
        if (!transientActive)
            activeActivity = idleActivity();
    }

    // The face a closed sheet lands on: media only when the user picked the media face.
    function idleActivity() {
        return mediaAvailable && mediaPreferred ? "media" : "home";
    }

    // A dot draws the same face for home and media, so a toggle would only change what the next click opens.
    readonly property bool mediaFaceToggleAvailable: !dotMode && !expanded && mediaAvailable && (activeActivity === "home" || activeActivity === "media")

    function toggleMediaFace() {
        if (!mediaFaceToggleAvailable)
            return false;
        hoverHeld = true;
        hoverOpenTimer.stop();
        return requestActivity(activeActivity === "media" ? "home" : "media", false, false);
    }

    function requestHoverExpand() {
        if (inputSuspended || hoverHeld || !hoverExpandEnabled || activeActivity === "powermenu")
            return false;
        if (notificationActive) {
            hoverExpanded = true;
            keyboardDismissRequested = false;
            expanded = true;
            hoverCloseTimer.stop();
            notificationTimer.stop();
            return true;
        }
        if (!requestExpand(false))
            return false;
        hoverExpanded = true;
        return true;
    }

    function requestHoverCollapse() {
        if (!hoverExpanded)
            return false;
        if (notificationActive) {
            hoverExpanded = false;
            expanded = false;
            keyboardDismissRequested = false;
            syncNotificationTimeout(true);
            return true;
        }
        return requestCollapse();
    }

    // A press inside a hover-opened sheet takes the keyboard; a notification keeps its click-to-center path.
    function promoteHoverToActive() {
        if (!hoverExpanded || !expanded || notificationActive)
            return false;
        hoverExpanded = false;
        hoverCloseTimer.stop();
        keyboardDismissRequested = true;
        return true;
    }

    function requestExpand(requestKeyboardFocus) {
        if (inputSuspended)
            return false;
        if (systemActivityActive) {
            syncTransientTimeout(true);
            return false;
        }
        if (isDestination(activeActivity))
            return requestActivity(activeActivity, true, requestKeyboardFocus);
        if (notificationActive && !notificationExpandAllowed)
            return requestNotificationCenter(false);
        hoverExpanded = false;
        clearPendingRequests("");
        hoverCloseTimer.stop();
        transientTimer.stop();
        notificationTimer.stop();
        keyboardDismissRequested = requestKeyboardFocus === true;
        expanded = true;
        return true;
    }

    function requestCollapse() {
        hoverExpanded = false;
        hoverOpenTimer.stop();
        transientTimer.stop();
        notificationTimer.stop();
        keyboardDismissRequested = false;
        keyboardYielded = false;
        expanded = false;
        launcherSessionActive = false;
        clearPendingRequests("");
        if (notificationActive) {
            resumeAfterNotification(false);
            return true;
        }
        if (systemActivityActive) {
            finishTransient();
            return true;
        }
        activeActivity = idleActivity();
        return true;
    }

    function resolvedReturnActivity(activityId) {
        switch (activityId) {
        case "notification":
        case "home":
            return activityId;
        case "media":
            return mediaAvailable ? "media" : "home";
        }
        if (isDestination(activityId))
            return activityId;
        return idleActivity();
    }

    function requestActivity(activityId, shouldExpand, requestKeyboardFocus) {
        const destination = isDestination(activityId);
        if (activityId !== "home" && activityId !== "media" && !destination)
            return false;
        if (inputSuspended && shouldExpand === true)
            return false;
        if (activityId === "media" && !mediaAvailable)
            return false;
        if (activityId === "weather" && !SettingsData.weatherEnabled)
            return false;
        if (activityId === "wellbeing" && !SettingsData.wellbeingEnabled)
            return false;

        if (activityId !== "launcher")
            launcherSessionActive = false;
        clearPendingRequests(activityId);

        if (activeActivity === activityId && expanded && shouldExpand === true) {
            if (requestKeyboardFocus === true) {
                keyboardDismissRequested = true;
                hoverExpanded = false;
            }
            return true;
        }

        if (destination && shouldExpand === true && !visualsReady(activityId)) {
            const entry = destinationState[activityId];
            entry.pending = true;
            entry.pendingKeyboardFocus = requestKeyboardFocus === true;
            entry.requested = true;
            destinationRevision++;
            requestedRevision++;
            return true;
        }

        if (requestKeyboardFocus === true)
            hoverExpanded = false;
        hoverOpenTimer.stop();
        hoverCloseTimer.stop();
        transientTimer.stop();
        consumeTransientNotification();
        keyboardDismissRequested = shouldExpand === true && requestKeyboardFocus === true;
        expanded = shouldExpand === true;
        activeActivity = activityId;
        if ((activityId === "media" || activityId === "home") && shouldExpand !== true)
            mediaPreferred = activityId === "media";
        launcherSessionActive = activityId === "launcher" && expanded;
        if (destination && expanded)
            sessionStarted(activityId);
        return true;
    }

    function requestLauncher(query, mode, shouldToggle) {
        const open = activeActivity === "launcher" && expanded;
        if (shouldToggle === true && open)
            return requestCollapse();
        launcherPendingQuery = query || "";
        launcherPendingMode = mode || "";
        const handled = requestActivity("launcher", true, true);
        // An open launcher applies a new query or mode in place.
        if (handled && open && (launcherPendingQuery || launcherPendingMode))
            sessionStarted("launcher");
        // Only a launcher that is still loading reads these later.
        if (!destinationState.launcher.pending) {
            launcherPendingQuery = "";
            launcherPendingMode = "";
        }
        return handled;
    }

    function requestControlCenter(section, shouldToggle) {
        if (shouldToggle === true && activeActivity === "controlcenter" && expanded)
            return requestCollapse();
        controlCenterPendingSection = section || "";
        return requestActivity("controlcenter", true, true);
    }

    function requestWallpaper(shouldToggle) {
        if (shouldToggle === true && activeActivity === "wallpaper" && expanded)
            return requestCollapse();
        return requestActivity("wallpaper", true, true);
    }

    function requestWeather(shouldToggle) {
        if (shouldToggle === true && activeActivity === "weather" && expanded)
            return requestCollapse();
        return requestActivity("weather", true, true);
    }

    function requestNotificationCenter(shouldToggle) {
        if (shouldToggle === true && activeActivity === "notificationcenter" && expanded)
            return requestCollapse();
        root.consumeTransientNotification();
        return requestActivity("notificationcenter", true, true);
    }

    function requestClipboard(shouldToggle) {
        if (shouldToggle === true && activeActivity === "clipboard" && expanded)
            return requestCollapse();
        return requestActivity("clipboard", true, true);
    }

    function requestPowerMenu(shouldToggle) {
        if (shouldToggle === true && activeActivity === "powermenu" && expanded)
            return requestCollapse();
        return requestActivity("powermenu", true, true);
    }

    function cycleActivity(direction, shouldExpand) {
        const activities = ["home"];
        if (mediaAvailable)
            activities.push("media");
        if (launcherCycleEnabled)
            activities.push("launcher");
        activities.push("controlcenter");
        activities.push("wallpaper");
        if (SettingsData.weatherEnabled)
            activities.push("weather");
        activities.push("notificationcenter");
        const currentIndex = Math.max(0, activities.indexOf(activeActivity));
        const step = direction < 0 ? -1 : 1;
        const nextIndex = (currentIndex + step + activities.length) % activities.length;
        const next = activities[nextIndex];
        if (!requestActivity(next, shouldExpand, shouldExpand))
            return false;
        if (next === "home" || next === "media")
            mediaPreferred = next === "media";
        return true;
    }

    function finishTransient() {
        if (!systemActivityActive)
            return;

        transientTimer.stop();
        const returnActivity = resolvedReturnActivity(transientReturnActivity);
        transientReturnActivity = "";
        if (returnActivity === "notification") {
            hoverExpanded = false;
            keyboardDismissRequested = false;
            expanded = notificationExpandAllowed;
            activeActivity = "notification";
            syncNotificationTimeout(true);
            return;
        }
        activeActivity = returnActivity;
    }

    function setSystemStateContentLength(length) {
        const next = Math.ceil(length);
        if (!isFinite(next) || next <= 0 || Math.abs(next - systemStateContentLength) < 2)
            return;
        systemStateContentLength = next;
    }

    function requestSystemActivity(activityId) {
        if (!isSystemActivity(activityId))
            return false;

        launcherSessionActive = false;
        clearPendingRequests("");

        if (expanded && !notificationActive) {
            if (activeActivity !== activityId)
                return false;
            transientTimer.stop();
            return true;
        }

        if (notificationActive) {
            notificationTimer.stop();
            hoverExpanded = false;
            hoverOpenTimer.stop();
            hoverCloseTimer.stop();
            keyboardDismissRequested = false;
            expanded = false;
        }

        if (!systemActivityActive)
            transientReturnActivity = activeActivity;
        activeActivity = activityId;
        syncTransientTimeout(true);
        return true;
    }

    function canRequestNotification(critical) {
        return notificationActive || !expanded || critical === true;
    }

    function consumeTransientNotification() {
        if (transientReturnActivity === "notification")
            transientReturnActivity = "";
        if (!notificationActive)
            return;
        notificationTimer.stop();
        suspendedActivity = "";
        suspendedExpanded = false;
        suspendedKeyboardDismissRequested = false;
    }

    function requestNotification(critical) {
        if (!canRequestNotification(critical))
            return false;

        if (notificationActive)
            return refreshNotification();

        clearPendingRequests("");
        transientTimer.stop();
        suspendedActivity = activeActivity;
        suspendedExpanded = expanded;
        suspendedKeyboardDismissRequested = keyboardDismissRequested;
        launcherSessionActive = false;
        keyboardDismissRequested = false;
        expanded = notificationExpandAllowed;
        activeActivity = "notification";
        syncNotificationTimeout(true);
        return true;
    }

    function refreshNotification() {
        if (!notificationActive)
            return false;
        syncNotificationTimeout(true);
        return true;
    }

    function resumeAfterNotification(restoreExpanded) {
        if (!notificationActive)
            return;

        notificationTimer.stop();
        const nextExpanded = restoreExpanded === true && suspendedExpanded;
        const suspendedFace = suspendedActivity === "home" || suspendedActivity === "media";
        const nextActivity = !suspendedActivity || (suspendedFace && !nextExpanded) ? idleActivity() : suspendedActivity === "media" && !mediaAvailable ? "home" : suspendedActivity;
        const nextKeyboardDismissRequested = nextExpanded && suspendedKeyboardDismissRequested;
        suspendedActivity = "";
        suspendedExpanded = false;
        suspendedKeyboardDismissRequested = false;
        expanded = nextExpanded;
        keyboardDismissRequested = nextKeyboardDismissRequested;
        activeActivity = nextActivity;
        launcherSessionActive = nextActivity === "launcher" && nextExpanded;
        if (nextExpanded && isDestination(nextActivity))
            sessionStarted(nextActivity);
        if (systemActivityActive && !expanded)
            transientTimer.restart();
    }

    function completeNotification() {
        if (transientReturnActivity === "notification")
            transientReturnActivity = "";
        if (!notificationActive)
            return false;
        resumeAfterNotification(true);
        return true;
    }

    function requestToggle(requestKeyboardFocus) {
        if (notificationActive && hoverExpanded && expanded)
            return requestNotificationCenter(false);
        if (expanded)
            return requestCollapse();
        return requestExpand(requestKeyboardFocus);
    }

    function slotHoverEntered() {
        slotHoverCount++;
    }

    function slotHoverExited() {
        slotHoverCount = Math.max(0, slotHoverCount - 1);
    }

    onSlotHoveredChanged: {
        if (slotHovered) {
            hoverOpenTimer.stop();
            return;
        }
        if (pointerInside && hoverExpandEnabled && !expanded)
            hoverOpenTimer.restart();
    }

    function updatePointerInside(inside) {
        pointerInside = inside === true;
        syncNotificationTimeout(!pointerInside);
        syncTransientTimeout(!pointerInside);
        if (!pointerInside) {
            hoverHeld = false;
            slotHoverCount = 0;
            hoverOpenTimer.stop();
            if (hoverExpanded && expanded)
                hoverCloseTimer.restart();
            return;
        }
        hoverCloseTimer.stop();
        if (hoverExpandEnabled && !expanded && !slotHovered)
            hoverOpenTimer.restart();
    }

    property Timer hoverOpenTimer: Timer {
        interval: root.hoverOpenDelay
        onTriggered: {
            if (!root.pointerInside || !root.hoverExpandEnabled || root.inputSuspended || root.slotHovered)
                return;
            root.requestHoverExpand();
        }
    }

    property Timer hoverCloseTimer: Timer {
        interval: root.hoverCloseDelay
        onTriggered: {
            if (!root.pointerInside && root.hoverExpanded)
                root.requestHoverCollapse();
        }
    }

    property Timer mediaReturnTimer: Timer {
        interval: root.mediaReturnDelay
        onTriggered: {
            if (root.mediaAvailable)
                return;
            root.mediaPreferred = false;
            if (root.activeActivity !== "media")
                return;
            root.keyboardDismissRequested = false;
            root.expanded = false;
            root.activeActivity = "home";
        }
    }

    property Timer transientTimer: Timer {
        interval: root.transientTimeout
        onTriggered: {
            if (!root.transientActive || root.expanded)
                return;
            root.finishTransient();
        }
    }

    property Timer notificationTimer: Timer {
        interval: root.notificationTimeout
        onTriggered: root.completeNotification()
    }

    property Timer visualsReleaseTimer: Timer {
        interval: 260
        onTriggered: root.dropIdleVisuals()
    }
}
