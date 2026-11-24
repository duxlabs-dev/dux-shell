import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Modules.Dock
import qs.Widgets
import "../../Common/settings/DockConfig.js" as DockConfig
import "../../Common/settings/DockPins.js" as DockPins
import "../../Common/settings/AppFolders.js" as AppFolders
import "ApplicationModel.js" as ApplicationModel

Item {
    id: root

    required property var surfaceContext
    required property var options
    property bool renderItems: true
    property var mixedStrip: null
    property int mixedDropIndex: -1
    property int folderDropIndex: -1
    property int folderCandidate: -1
    property string pendingFolderRename: ""
    onDraggedIndexChanged: {
        if (draggedIndex >= 0)
            return;
        mixedDropIndex = -1;
        folderDropIndex = -1;
        folderCandidate = -1;
        folderDwell.stop();
        contextMenu?.clearFolderDrop();
        mixedStrip?.cancelDrag();
        modelUpdate.schedule();
    }
    function updateMixedDrag(item, x, y) {
        if (!mixedStrip)
            return;
        const source = items[draggedIndex]?.folderDropItem;
        const openFolderId = source?.type === "app" ? contextMenu?.updateFolderDrop(item, x, y) : "";
        let candidate = -1;
        if (openFolderId) {
            folderDwell.stop();
            folderCandidate = -1;
            folderDropIndex = items.findIndex(entry => entry.folderDropItem?.id === openFolderId);
        } else {
            if (source?.type === "app") {
                const center = mixedStrip.centerDropIndex(item, x, y, entry => {
                    const action = AppFolders.dropAction(source, entry.appData?.folderDropItem);
                    return action === "add" || action === "create";
                });
                candidate = mixedStrip.model[center]?.appIndex ?? -1;
            }
            // Grouping waits for a short hover so sweeping across pins still reorders.
            if (candidate !== folderCandidate) {
                folderCandidate = candidate;
                folderDropIndex = -1;
                if (candidate >= 0)
                    folderDwell.restart();
                else
                    folderDwell.stop();
            }
        }
        // Over a pin's center the order holds still, so the pin stays under the pointer.
        if (folderDropIndex < 0 && candidate < 0)
            mixedDropIndex = mixedStrip.dropIndex(item, x, y, entry => DockConfig.isPinnedApp(entry.appData ?? {}));
        mixedStrip.draggingIndex = mixedStrip.appSlot(draggedIndex);
        mixedStrip.targetIndex = mixedDropIndex;
    }
    function finishDrag(from, to) {
        const sourceId = items[from]?.folderDropItem?.id;
        const targetId = items[folderDropIndex]?.folderDropItem?.id;
        if (sourceId && targetId) {
            // Applying a folder drop can destroy the button delivering the release.
            folderDrop.sourceId = sourceId;
            folderDrop.targetId = targetId;
            folderDrop.schedule();
            return;
        }
        if (from !== to && to >= 0)
            settleDrag(() => movePinnedApp(from, to));
    }
    // Cleared after the folder button reacts, not inside its change handler.
    readonly property DeferredAction renameHandoff: DeferredAction {
        onTriggered: root.pendingFolderRename = ""
    }
    Timer {
        id: folderDwell
        interval: Timing.settle
        onTriggered: {
            if (root.draggedIndex >= 0)
                root.folderDropIndex = root.folderCandidate;
        }
    }
    DeferredAction {
        id: folderDrop
        property string sourceId
        property string targetId
        onTriggered: root.applyFolderDrop(sourceId, targetId)
    }
    function applyFolderDrop(sourceId, targetId) {
        const pins = pinnedApps;
        const next = DockPins.drop(pins, sourceId, targetId, I18n.tr("Folder"));
        if (next === pins)
            return;
        const target = pins.find(pin => DockPins.id(pin) === targetId);
        const folder = DockPins.isFolder(target) ? target : AppFolders.folderForApp(next, targetId);
        updateFolderPins(next, targetId, [folder], sourceId);
    }
    function updateFolderPins(next, replacedId, replacement, removedId = "") {
        const config = surfaceContext.config;
        if (config.order?.length) {
            const slots = items.filter(DockConfig.isPinnedApp);
            const replaced = slots.find(item => item.folderDropItem?.id === replacedId);
            const removed = slots.find(item => item.folderDropItem?.id === removedId);
            if (replaced) {
                const order = DockConfig.replacePinSlot(config.widgets, slots, config.order, replaced, removed, replacement.map(pin => {
                    const id = DockPins.id(pin);
                    return DockPins.isFolder(pin) ? id : Paths.moddedAppId(id);
                }));
                SettingsData.updateDockConfig(config.id, { order });
            }
        }
        setPinnedApps(next);
    }
    function folderForApp(appId) {
        return AppFolders.folderForApp(pinnedApps, dockPinForApp(appId));
    }
    function createFolderFor(appId) {
        const pin = dockPinForApp(appId) || appId;
        const pins = pinnedApps;
        const next = DockPins.create(pins, pin, I18n.tr("Folder"));
        if (next === pins)
            return;
        const folder = AppFolders.folderForApp(next, pin);
        pendingFolderRename = folder.id;
        if (pins.includes(pin))
            updateFolderPins(next, pin, [folder]);
        else
            setPinnedApps(next);
    }
    function addAppToFolder(folderId, appId) {
        const pin = dockPinForApp(appId) || appId;
        if (pinnedApps.includes(pin)) {
            applyFolderDrop(pin, "folder:" + folderId);
            return;
        }
        const pins = pinnedApps;
        const next = AppFolders.addApp(pins, folderId, pin);
        if (next !== pins)
            setPinnedApps(next);
    }
    function removeAppFromFolder(appId) {
        const pin = dockPinForApp(appId);
        const folder = AppFolders.folderForApp(pinnedApps, pin);
        if (folder)
            extractFolderApp(folder.id, pin);
    }
    function extractFolderApp(folderId, appId) {
        const pins = pinnedApps;
        const next = DockPins.extract(pins, folderId, appId);
        if (next === pins)
            return;
        const folder = AppFolders.folderById(next, folderId);
        updateFolderPins(next, "folder:" + folderId, folder ? [folder, appId] : [appId]);
    }
    function dissolveFolder(folderId) {
        const pins = pinnedApps;
        const folder = AppFolders.folderById(pins, folderId);
        if (folder)
            updateFolderPins(DockPins.dissolve(pins, folderId), DockPins.id(folder), folder.apps);
    }
    function renameFolder(folderId, name) {
        const pins = pinnedApps;
        const next = AppFolders.renameFolder(pins, folderId, name);
        if (next !== pins)
            setPinnedApps(next);
    }
    function moveFolderApp(folderId, sourceId, targetId) {
        const pins = pinnedApps;
        const next = AppFolders.moveAppById(pins, folderId, sourceId, targetId);
        if (next !== pins)
            setPinnedApps(next);
    }
    function dropTarget(localTarget) {
        return mixedStrip ? (mixedStrip.model[mixedDropIndex]?.appIndex ?? -1) : localTarget;
    }
    readonly property var items: repeater.dockItems
    property int desktopRevision: 0
    readonly property var desktopEntries: {
        desktopRevision;
        const entries = {};
        for (const item of items) {
            if (item.isCoreApp || item.type === "folder" || !item.appId || item.appId.startsWith("__") || item.appId in entries)
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
        return barHosted ? pinnedApps.includes(id) : dockPinForApp(id) !== "";
    }
    function dockPinForApp(id) {
        if (DockPins.contains(pinnedApps, id))
            return id;
        for (const pin of pinnedApps) {
            const apps = DockPins.isFolder(pin) ? pin.apps : [pin];
            const match = apps.find(app => Paths.moddedAppId(app) === id);
            if (match)
                return match;
        }
        return "";
    }
    function addPinnedApp(id) {
        if (id && !isPinnedApp(id))
            setPinnedApps(pinnedApps.concat([id]));
    }
    function removePinnedApp(id) {
        if (barHosted)
            setPinnedApps(pinnedApps.filter(app => app !== id));
        else
            SessionData.setDockAppPinned(surfaceContext.configId, dockPinForApp(id), false);
    }
    function folderMembers(folder, limit = folder.apps.length) {
        desktopRevision;
        return folder.apps.slice(0, limit).map(id => {
            const appId = Paths.moddedAppId(id);
            const core = searchCoreApps.find(app => app.builtInPluginId === appId);
            const entry = core ? null : DesktopEntries.heuristicLookup(appId);
            return {
                id,
                appId,
                name: core?.name ?? Paths.getAppName(appId, entry),
                icon: core?.icon ?? "",
                iconSource: core ? "" : Paths.getAppIcon(appId, entry),
                core,
                entry
            };
        });
    }
    function launchApp(appId, core, entry) {
        if (core) {
            AppSearchService.executeCoreApp(core);
            return;
        }
        if (!entry)
            return;
        AppUsageHistoryData.addAppUsage({
            id: appId,
            name: entry.name || appId,
            icon: entry.icon ? String(entry.icon) : "",
            exec: entry.exec || "",
            comment: entry.comment || ""
        });
        SessionService.launchDesktopEntry(entry);
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
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
            }
        }

        Behavior on height {
            enabled: !root._switchingPosition
            NumberAnimation {
                duration: Theme.expressiveDurations.expressiveDefaultSpatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.expressiveCurves.expressiveDefaultSpatial
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
                    const showRunning = root.options.showRunningApps !== false;
                    const separatePinnedAndRunning = root.options.separatePinnedAndRunningApps && showRunning;
                    const folderOwners = separatePinnedAndRunning ? new Map() : ApplicationModel.folderOwners(pinnedApps, Paths.moddedAppId);

                    if (!separatePinnedAndRunning) {
                        pinnedApps.forEach(rawAppId => {
                            if (DockPins.isFolder(rawAppId)) {
                                appGroups.set(DockPins.id(rawAppId), {
                                    folder: rawAppId,
                                    windows: []
                                });
                                return;
                            }
                            const appId = Paths.moddedAppId(rawAppId);
                            const coreAppData = getCoreAppData(appId);
                            appGroups.set(appId, {
                                appId: appId,
                                isPinned: true,
                                pinId: rawAppId,
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
                        const folderKey = folderOwners.get(appId);
                        if (folderKey) {
                            appGroups.get(folderKey).windows.push({
                                toplevel,
                                appId
                            });
                            return;
                        }

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
                        if (group.folder) {
                            pinnedGroups.push(ApplicationModel.folderItem(appId, group.folder, group.windows));
                            return;
                        }
                        const firstWindow = group.windows.length > 0 ? group.windows[0] : null;
                        const item = {
                            uniqueKey: "grouped_" + appId,
                            type: "grouped",
                            appId: appId,
                            toplevel: firstWindow ? firstWindow.toplevel : null,
                            isPinned: group.isPinned,
                            folderDropItem: group.pinId ? { id: group.pinId, type: "app" } : null,
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
                            if (DockPins.isFolder(rawAppId)) {
                                pinnedGroups.push(ApplicationModel.folderItem(DockPins.id(rawAppId), rawAppId));
                                return;
                            }
                            const appId = Paths.moddedAppId(rawAppId);
                            const coreAppData = getCoreAppData(appId);
                            pinnedGroups.push(ApplicationModel.pinnedItem(appId, coreAppData, false, rawAppId));
                        });
                    }

                    // pinned-only dock: running apps keep their indicator on the pinned icon
                    if (!showRunning)
                        unpinnedGroups.length = 0;

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
                    const showRunning = root.options.showRunningApps !== false;
                    const separatePinnedAndRunning = root.options.separatePinnedAndRunningApps && showRunning;

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

                    let remainingWindowItems = windowItems.slice();

                    pinnedApps.forEach(rawAppId => {
                        if (DockPins.isFolder(rawAppId)) {
                            const folderId = DockPins.id(rawAppId);
                            if (separatePinnedAndRunning) {
                                items.push(ApplicationModel.folderItem(folderId, rawAppId));
                                return;
                            }
                            const owners = ApplicationModel.folderOwners([rawAppId], Paths.moddedAppId);
                            const windows = remainingWindowItems.filter(item => owners.has(item.appId));
                            remainingWindowItems = remainingWindowItems.filter(item => !owners.has(item.appId));
                            items.push(ApplicationModel.folderItem(folderId, rawAppId, windows));
                            return;
                        }
                        const appId = Paths.moddedAppId(rawAppId);
                        const coreAppData = getCoreAppData(appId);
                        if (separatePinnedAndRunning) {
                            items.push(ApplicationModel.pinnedItem(appId, coreAppData, false, rawAppId));
                            return;
                        }

                        const matchIndex = remainingWindowItems.findIndex(item => item.appId === appId);

                        if (matchIndex !== -1) {
                            const windowItem = remainingWindowItems.splice(matchIndex, 1)[0];
                            windowItem.isPinned = true;
                            windowItem.folderDropItem = { id: rawAppId, type: "app" };
                            windowItem.uniqueKey = "pinned_" + appId;
                            if (!windowItem.isCoreApp && coreAppData) {
                                windowItem.isCoreApp = true;
                                windowItem.coreAppData = coreAppData;
                            }
                            items.push(windowItem);
                        } else {
                            items.push(ApplicationModel.pinnedItem(appId, coreAppData, runningAppIds.has(appId), rawAppId));
                        }
                    });

                    if (!showRunning)
                        remainingWindowItems.length = 0;

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
    // A dock renders the app buttons in its own strip, so the hover comes from there.
    readonly property var pointerButton: mixedStrip?.hoveredButton ?? hoveredButton
    property Item previewButton: null
    readonly property bool previewOpen: previewButton !== null
    readonly property bool previewAllowed: surfaceContext.live && !surfaceContext.editMode && draggedIndex < 0 && !(contextMenu?.visible ?? false)
    readonly property Item previewTarget: {
        if (!previewAllowed)
            return null;
        if (pointerButton?.showsWindowPreview)
            return pointerButton;
        const lingering = previewButton?.showsWindowPreview && (previewLoader.item?.containsMouse ?? false);
        return lingering ? previewButton : null;
    }
    onPointerButtonChanged: {
        if (!pointerButton || pointerButton.showsWindowPreview)
            return;
        previewSettle.stop();
        previewButton = null;
    }
    onPreviewTargetChanged: {
        if (previewTarget === previewButton) {
            previewSettle.stop();
            return;
        }
        const immediate = previewButton && (previewTarget || !previewAllowed || !previewButton.showsWindowPreview);
        if (!immediate) {
            previewSettle.restart();
            return;
        }
        previewSettle.stop();
        previewButton = previewTarget;
    }
    Timer {
        id: previewSettle
        interval: Theme.tooltipDelay
        onTriggered: root.previewButton = root.previewTarget
    }
    // The window stays loaded once used: creating and destroying one per hover retained ~2MB each.
    property bool previewLoaded: false
    onPreviewOpenChanged: {
        if (previewOpen)
            previewLoaded = true;
    }
    LazyLoader {
        id: previewLoader
        active: root.previewLoaded

        DockWindowPreview {
            screen: root.dockScreen
            anchorButton: root.previewButton
            surfaceContext: root.surfaceContext
            options: root.options
            onDismissed: Qt.callLater(() => root.previewButton = null)
        }
    }
    onHoveredButtonChanged: {
        tooltip.hide();
        if (!barHosted || !hoveredButton || hoveredButton.showsWindowPreview || !surfaceContext.live)
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
    onVisibleChanged: {
        if (visible)
            return;
        tooltip.hide();
        previewSettle.stop();
        previewButton = null;
    }

    readonly property var settingsAppIdSubstitutions: SettingsData.appIdSubstitutions

    onSettingsAppIdSubstitutionsChanged: modelUpdate.schedule()

    onPinnedAppsChanged: modelUpdate.schedule()
    readonly property string modelOptions: JSON.stringify({
        separatePinnedAndRunningApps: options.separatePinnedAndRunningApps,
        showRunningApps: options.showRunningApps,
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
