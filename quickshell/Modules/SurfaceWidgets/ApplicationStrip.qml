import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Dock
import qs.Widgets
import "../../Common/settings/DockConfig.js" as DockConfig
import "ApplicationModel.js" as ApplicationModel

Item {
    id: root

    required property var surfaceContext
    required property var options
    property bool renderItems: true
    property var mixedStrip: null
    property int mixedDropIndex: -1
    onDraggedIndexChanged: {
        if (draggedIndex >= 0)
            return;
        mixedDropIndex = -1;
        mixedStrip?.cancelDrag();
        modelUpdate.schedule();
    }
    function updateMixedDrag(item, x, y) {
        if (!mixedStrip)
            return;
        mixedDropIndex = mixedStrip.dropIndex(item, x, y, entry => entry.appData?.isPinned === true && !["launcher", "overflow-toggle"].includes(entry.appData.type));
        mixedStrip.draggingIndex = mixedStrip.appSlot(draggedIndex);
        mixedStrip.targetIndex = mixedDropIndex;
    }
    function dropTarget(localTarget) {
        return mixedStrip?.model[mixedDropIndex]?.appIndex ?? localTarget;
    }
    readonly property var items: repeater.dockItems
    property int desktopRevision: 0
    readonly property var desktopEntries: {
        desktopRevision;
        const entries = {};
        for (const item of items) {
            if (item.isCoreApp || !item.appId || item.appId.startsWith("__") || item.appId in entries)
                continue;
            entries[item.appId] = DesktopEntries.heuristicLookup(item.appId);
        }
        return entries;
    }
    function refreshDesktopEntries() {
        desktopRevision++;
    }
    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.refreshDesktopEntries();
        }
    }
    readonly property real itemSpacing: layoutFlow.spacing
    readonly property int renderedCount: repeater.count
    function itemAt(index) {
        return repeater.itemAt(index);
    }
    readonly property bool barHosted: surfaceContext.kind === "bar"
    readonly property var pinnedApps: barHosted ? SessionData.barPinnedApps : SessionData.getDockPins(surfaceContext.configId)
    function setPinnedApps(apps) {
        if (barHosted)
            SessionData.setBarPinnedApps(apps);
        else
            SessionData.setDockPins(surfaceContext.configId, apps);
    }
    function isPinnedApp(id) {
        return pinnedApps.includes(id);
    }
    function addPinnedApp(id) {
        if (id && !isPinnedApp(id))
            setPinnedApps(pinnedApps.concat([id]));
    }
    function removePinnedApp(id) {
        setPinnedApps(pinnedApps.filter(app => app !== id));
    }
    function settleDrag(apply) {
        suppressShiftAnimation = true;
        apply();
        draggedIndex = -1;
        dropTargetIndex = -1;
        modelUpdate.schedule();
        modelUpdate.flush();
        Qt.callLater(() => root.suppressShiftAnimation = false);
    }
    property var contextMenu: null
    property var trashContextMenu: null
    property bool requestDockShow: false
    property int pinnedAppCount: 0
    property bool groupByApp: false
    property bool isVertical: false
    property var dockScreen: null
    property real iconSize: 40
    property bool usesOverlayLayer: false
    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property bool suppressShiftAnimation: false
    property int maxVisibleApps: root.options.maxVisibleApps
    property int maxVisibleRunningApps: root.options.maxVisibleRunningApps
    property bool overflowExpanded: false
    property int overflowItemCount: 0

    readonly property real targetSize: barHosted ? iconSize * (options.iconSizePercentage ?? 100) / 100 : iconSize
    readonly property real indicatorLane: root.barHosted && !root.options.hideIndicators ? DockConfig.indicatorLane(root.options) : 0
    readonly property real crossSize: {
        // The lane is mirrored so icons stay centered on the bar.
        const needed = root.targetSize + root.indicatorLane * 2;
        if (!root.barHosted)
            return needed;
        // A bar pill cannot grow past its widget thickness, so the lane yields there.
        return Math.min(needed, root.surfaceContext?.widgetThickness ?? needed);
    }
    readonly property var hoveredButton: {
        for (let i = 0; i < repeater.count; i++) {
            const button = repeater.itemAt(i)?.dockButton;
            if (button?.showTooltip)
                return button;
        }
        return null;
    }
    clip: false
    property bool _switchingPosition: false
    implicitWidth: appLayout.width
    implicitHeight: appLayout.height

    function focusFirst() {
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (!item?.activeFocusOnTab)
                continue;
            item.forceActiveFocus();
            return;
        }
    }
    function movePinnedApp(fromDockIndex, toDockIndex) {
        const next = ApplicationModel.movePin(pinnedApps, items, fromDockIndex, toDockIndex);
        if (next !== pinnedApps)
            setPinnedApps(next);
    }

    Item {
        id: appLayout
        width: layoutFlow.width
        height: layoutFlow.height

        Behavior on width {
            enabled: !root._switchingPosition
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            enabled: !root._switchingPosition
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Easing.OutCubic
            }
        }
        anchors.centerIn: parent

        Flow {
            id: layoutFlow
            layoutDirection: I18n.isRtl ? Qt.RightToLeft : Qt.LeftToRight
            flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: root.options.itemSpacing ?? Theme.spacingS

            Repeater {
                id: repeater

                property var dockItems: []

                model: ScriptModel {
                    values: root.renderItems ? repeater.dockItems : []
                    objectProp: "uniqueKey"
                }

                Component.onCompleted: updateModel()

                function isOnScreen(toplevel, screenName) {
                    if (!toplevel.screens)
                        return false;
                    for (let i = 0; i < toplevel.screens.length; i++) {
                        if (toplevel.screens[i]?.name === screenName)
                            return true;
                    }
                    return false;
                }

                function getCoreAppData(appId) {
                    if (typeof AppSearchService === "undefined")
                        return null;
                    return (AppSearchService.coreApps || []).find(app => app.builtInPluginId === appId) ?? null;
                }

                function buildBaseItems() {
                    const pinnedApps = [...(root.pinnedApps || [])];
                    const allToplevels = root.visibleWindows;
                    const sortedToplevels = (root.options.isolateDisplays && root.dockScreen) ? allToplevels.filter(t => isOnScreen(t, root.dockScreen.name)) : allToplevels;

                    if (root.groupByApp) {
                        return buildGroupedItems(pinnedApps, sortedToplevels);
                    }
                    return buildUngroupedItems(pinnedApps, sortedToplevels);
                }

                function buildGroupedItems(pinnedApps, sortedToplevels) {
                    const items = [];
                    const appGroups = new Map();
                    const separatePinnedAndRunning = root.options.separatePinnedAndRunningApps;

                    if (!separatePinnedAndRunning) {
                        pinnedApps.forEach(rawAppId => {
                            const appId = Paths.moddedAppId(rawAppId);
                            const coreAppData = getCoreAppData(appId);
                            appGroups.set(appId, {
                                appId: appId,
                                isPinned: true,
                                windows: [],
                                isCoreApp: coreAppData !== null,
                                coreAppData: coreAppData
                            });
                        });
                    }

                    sortedToplevels.forEach((toplevel, index) => {
                        const identity = ApplicationModel.windowIdentity(toplevel, Paths.moddedAppId(toplevel.appId || "unknown"), AppSearchService.coreApps || []);
                        const appId = identity.appId;
                        const coreAppData = identity.coreAppData;

                        if (!appGroups.has(appId)) {
                            appGroups.set(appId, {
                                appId: appId,
                                isPinned: false,
                                windows: [],
                                isCoreApp: coreAppData !== null,
                                coreAppData: coreAppData
                            });
                        }
                        appGroups.get(appId).windows.push({
                            toplevel: toplevel,
                            index: index
                        });
                    });

                    const pinnedGroups = [];
                    const unpinnedGroups = [];

                    appGroups.forEach((group, appId) => {
                        const firstWindow = group.windows.length > 0 ? group.windows[0] : null;
                        const item = {
                            uniqueKey: "grouped_" + appId,
                            type: "grouped",
                            appId: appId,
                            toplevel: firstWindow ? firstWindow.toplevel : null,
                            isPinned: group.isPinned,
                            isRunning: group.windows.length > 0,
                            windowCount: group.windows.length,
                            allWindows: group.windows,
                            isCoreApp: group.isCoreApp || false,
                            coreAppData: group.coreAppData || null,
                            isInOverflow: false
                        };
                        (group.isPinned ? pinnedGroups : unpinnedGroups).push(item);
                    });

                    if (separatePinnedAndRunning) {
                        pinnedApps.forEach(rawAppId => {
                            const appId = Paths.moddedAppId(rawAppId);
                            const coreAppData = getCoreAppData(appId);
                            pinnedGroups.push(ApplicationModel.pinnedItem(appId, coreAppData, false));
                        });
                    }

                    pinnedGroups.forEach(item => items.push(item));
                    insertLauncher(items);

                    if (pinnedGroups.length > 0 && unpinnedGroups.length > 0) {
                        items.push(ApplicationModel.separator("separator_grouped"));
                    }
                    unpinnedGroups.forEach(item => items.push(item));

                    root.pinnedAppCount = pinnedGroups.length + (root.options.launcherEnabled ? 1 : 0);
                    return {
                        items,
                        pinnedCount: pinnedGroups.length,
                        runningCount: unpinnedGroups.length
                    };
                }

                function buildUngroupedItems(pinnedApps, sortedToplevels) {
                    const items = [];
                    const runningAppIds = new Set();
                    const windowItems = [];
                    const separatePinnedAndRunning = root.options.separatePinnedAndRunningApps;

                    sortedToplevels.forEach((toplevel, index) => {
                        const uniqueKey = CompositorService.windowKey(toplevel);
                        const identity = ApplicationModel.windowIdentity(toplevel, Paths.moddedAppId(toplevel.appId || "unknown"), AppSearchService.coreApps || []);
                        const finalAppId = identity.appId;
                        const coreAppData = identity.coreAppData;
                        const isCoreApp = identity.isCoreApp;
                        windowItems.push({
                            uniqueKey: uniqueKey,
                            type: "window",
                            appId: finalAppId,
                            toplevel: toplevel,
                            isPinned: false,
                            isRunning: true,
                            isCoreApp: isCoreApp,
                            coreAppData: coreAppData,
                            isInOverflow: false
                        });
                        runningAppIds.add(finalAppId);
                    });

                    const remainingWindowItems = windowItems.slice();

                    pinnedApps.forEach(rawAppId => {
                        const appId = Paths.moddedAppId(rawAppId);
                        const coreAppData = getCoreAppData(appId);
                        if (separatePinnedAndRunning) {
                            items.push(ApplicationModel.pinnedItem(appId, coreAppData, false));
                            return;
                        }

                        const matchIndex = remainingWindowItems.findIndex(item => item.appId === appId);

                        if (matchIndex !== -1) {
                            const windowItem = remainingWindowItems.splice(matchIndex, 1)[0];
                            windowItem.isPinned = true;
                            windowItem.uniqueKey = "pinned_" + appId;
                            if (!windowItem.isCoreApp && coreAppData) {
                                windowItem.isCoreApp = true;
                                windowItem.coreAppData = coreAppData;
                            }
                            items.push(windowItem);
                        } else {
                            items.push(ApplicationModel.pinnedItem(appId, coreAppData, runningAppIds.has(appId)));
                        }
                    });

                    root.pinnedAppCount = pinnedApps.length + (root.options.launcherEnabled ? 1 : 0);
                    insertLauncher(items);

                    if (pinnedApps.length > 0 && remainingWindowItems.length > 0) {
                        items.push(ApplicationModel.separator("separator_ungrouped"));
                    }
                    remainingWindowItems.forEach(item => items.push(item));

                    return {
                        items,
                        pinnedCount: pinnedApps.length,
                        runningCount: remainingWindowItems.length
                    };
                }

                function insertLauncher(targetArray) {
                    if (!root.options.launcherEnabled)
                        return;
                    const launcherItem = {
                        uniqueKey: "launcher_button",
                        type: "launcher",
                        appId: "__LAUNCHER__",
                        toplevel: null,
                        isPinned: true,
                        isRunning: false
                    };
                    targetArray.unshift(launcherItem);
                }

                function updateModel() {
                    const baseResult = buildBaseItems();
                    const overflow = ApplicationModel.overflow(baseResult.items, root.maxVisibleApps, root.maxVisibleRunningApps);
                    root.overflowItemCount = overflow.count;
                    let finalItems = overflow.items;
                    if (root.options.showTrash) {
                        finalItems.push({
                            uniqueKey: "trash_button",
                            type: "trash",
                            appId: "__TRASH__",
                            toplevel: null,
                            isPinned: false,
                            isRunning: false,
                            isInOverflow: false
                        });
                    }
                    dockItems = finalItems;
                }

                delegate: ApplicationItem {
                    strip: root
                }
            }
        }
    }

    DTooltip {
        id: tooltip
        screen: root.dockScreen
    }
    onHoveredButtonChanged: {
        tooltip.hide();
        if (!barHosted || !hoveredButton || !surfaceContext.live)
            return;
        const position = surfaceContext.screenPoint(hoveredButton, hoveredButton.width / 2, hoveredButton.height / 2);
        if (!position)
            return;
        const edge = options.position;
        const bounds = SettingsData.getBarBounds(dockScreen, surfaceContext.thickness, edge, surfaceContext.config);
        const x = isVertical ? (edge === SettingsData.Position.Left ? bounds.x + bounds.width : bounds.x) : position.x;
        const y = isVertical ? position.y : (edge === SettingsData.Position.Top ? bounds.y + bounds.height + Theme.spacingS : bounds.y - Theme.listItemHeight);
        tooltip.show(hoveredButton.tooltipText, x, y, dockScreen, isVertical && edge === SettingsData.Position.Left, isVertical && edge === SettingsData.Position.Right);
    }
    onVisibleChanged: if (!visible)
        tooltip.hide()

    readonly property var settingsAppIdSubstitutions: SettingsData.appIdSubstitutions

    onSettingsAppIdSubstitutionsChanged: modelUpdate.schedule()

    onPinnedAppsChanged: modelUpdate.schedule()
    readonly property string modelOptions: JSON.stringify({
        separatePinnedAndRunningApps: options.separatePinnedAndRunningApps,
        isolateDisplays: options.isolateDisplays,
        launcherEnabled: options.launcherEnabled,
        showTrash: options.showTrash
    })
    onModelOptionsChanged: modelUpdate.schedule()
    onDockScreenChanged: modelUpdate.schedule()
    readonly property var visibleWindows: options.currentWorkspace && dockScreen ? CompositorService.filterCurrentWorkspace(CompositorService.sortedToplevels, dockScreen.name) : CompositorService.sortedToplevels
    onVisibleWindowsChanged: modelUpdate.schedule()
    readonly property string windowMetadata: JSON.stringify(visibleWindows.map(toplevel => [toplevel.appId, ["org.quickshell", "dev.duxlabs.shell", "com.danklinux.dms"].includes(toplevel.appId) ? toplevel.title : "", options.isolateDisplays ? (toplevel.screens || []).map(screen => screen.name) : null]))
    onWindowMetadataChanged: modelUpdate.schedule()
    readonly property var searchCoreApps: AppSearchService.coreApps

    onSearchCoreAppsChanged: modelUpdate.schedule()
    onGroupByAppChanged: modelUpdate.schedule()
    onMaxVisibleAppsChanged: modelUpdate.schedule()
    onMaxVisibleRunningAppsChanged: modelUpdate.schedule()
    DeferredAction {
        id: modelUpdate
        onTriggered: {
            if (root.draggedIndex >= 0)
                return;
            repeater.updateModel();
        }
    }
}
