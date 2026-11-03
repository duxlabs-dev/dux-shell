import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Common
import qs.Modules.DBar
import qs.Modules.Plugins
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

BasePill {
    id: root

    enableBackgroundHover: false
    enableCursor: false
    section: "left"

    property var widgetData: null
    property var hoveredItem: null

    onHoveredItemChanged: {
        if (hoveredItem)
            return;
        hideTooltip();
    }

    function hideTooltip() {
        if (tooltipLoader.item)
            tooltipLoader.item.hide();
        tooltipLoader.active = false;
    }

    function edgeAnchor(item, popupHeight) {
        if (isVerticalOrientation) {
            const center = item.mapToItem(null, item.width / 2, item.height / 2);
            const x = axis?.edge === "left" ? (barThickness + barSpacing + Theme.spacingXS) : (parentScreen.width - barThickness - barSpacing - Theme.spacingXS);
            return Qt.point(x, center.y + minTooltipY);
        }
        const top = item.mapToItem(null, item.width / 2, 0);
        const screenHeight = parentScreen ? parentScreen.height : Screen.height;
        const y = axis?.edge === "bottom" ? (screenHeight - barThickness - barSpacing - Theme.spacingXS - popupHeight) : (barThickness + barSpacing + Theme.spacingXS);
        return Qt.point(top.x, y);
    }
    property var topBar: null
    property Item windowRoot: (Window.window ? Window.window.contentItem : null)

    readonly property real effectiveBarThickness: {
        if (barThickness > 0 && barSpacing > 0) {
            return barThickness + barSpacing;
        }
        return Theme.barThickness(barConfig?.innerPadding ?? SettingsData.barInnerPaddingDefault, CompositorService.getScreenScale(parentScreen)) + (barConfig?.spacing ?? 4);
    }

    readonly property var barBounds: {
        if (!parentScreen || !barConfig) {
            return {
                "x": 0,
                "y": 0,
                "width": 0,
                "height": 0,
                "wingSize": 0
            };
        }
        const barPosition = axis.edge === "left" ? 2 : (axis.edge === "right" ? 3 : (axis.edge === "top" ? 0 : 1));
        return SettingsData.getBarBounds(parentScreen, effectiveBarThickness, barPosition, barConfig);
    }

    readonly property real barY: barBounds.y

    property int _desktopEntriesUpdateTrigger: 0
    property int _toplevelsUpdateTrigger: 0
    property int _appIdSubstitutionsTrigger: 0

    readonly property bool _currentWorkspace: SettingsData.widgetOption("runningApps", widgetData, "runningAppsCurrentWorkspace")
    readonly property bool _currentMonitor: SettingsData.widgetOption("runningApps", widgetData, "runningAppsCurrentMonitor")
    readonly property bool _groupByApp: SettingsData.widgetOption("runningApps", widgetData, "runningAppsGroupByApp")
    readonly property string windowModelKey: _groupByApp ? "appId" : CompositorService.toplevelKey

    readonly property var sortedToplevels: {
        _toplevelsUpdateTrigger;
        let toplevels = CompositorService.sortedToplevels;
        if (!toplevels || toplevels.length === 0)
            return [];

        if (_currentWorkspace)
            toplevels = CompositorService.filterCurrentWorkspace(toplevels, parentScreen?.name) || [];
        if (_currentMonitor)
            toplevels = CompositorService.filterCurrentDisplay(toplevels, parentScreen?.name) || [];
        return toplevels;
    }

    Connections {
        target: CompositorService
        function onToplevelsChanged() {
            _toplevelsUpdateTrigger++;
        }
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            _desktopEntriesUpdateTrigger++;
        }
    }

    Connections {
        target: SettingsData
        function onAppIdSubstitutionsChanged() {
            _appIdSubstitutionsTrigger++;
        }
    }
    readonly property var groupedWindows: {
        if (!_groupByApp) {
            return [];
        }
        try {
            if (!sortedToplevels || sortedToplevels.length === 0) {
                return [];
            }
            const appGroups = new Map();
            sortedToplevels.forEach((toplevel, index) => {
                if (!toplevel)
                    return;
                const appId = toplevel?.appId || "unknown";
                if (!appGroups.has(appId)) {
                    appGroups.set(appId, {
                        "appId": appId,
                        "windows": []
                    });
                }
                appGroups.get(appId).windows.push({
                    "toplevel": toplevel,
                    "windowId": index,
                    "windowTitle": toplevel?.title || "(Unnamed)"
                });
            });
            return Array.from(appGroups.values());
        } catch (e) {
            return [];
        }
    }
    readonly property int windowCount: _groupByApp ? (groupedWindows?.length || 0) : (sortedToplevels?.length || 0)
    readonly property bool compactMode: SettingsData.widgetOption("runningApps", widgetData, "runningAppsCompactMode")
    readonly property real appIconSize: Theme.barIconSize(barThickness, undefined, barConfig?.maximizeWidgetIcons, barConfig?.iconScale)
    readonly property real iconCellSize: appIconSize + 6

    readonly property string focusedAppId: {
        if (!sortedToplevels || sortedToplevels.length === 0)
            return "";
        for (let i = 0; i < sortedToplevels.length; i++) {
            if (sortedToplevels[i].activated)
                return sortedToplevels[i].appId || "";
        }
        return "";
    }

    visible: windowCount > 0

    property real scrollAccumulator: 0
    property real touchpadThreshold: 500

    function activateNeighbor(windows, delta) {
        const currentIndex = windows.findIndex(w => w.activated);
        const nextIndex = delta < 0 ? (currentIndex === -1 ? 0 : Math.min(currentIndex + 1, windows.length - 1)) : (currentIndex === -1 ? windows.length - 1 : Math.max(currentIndex - 1, 0));
        const nextWindow = windows[nextIndex];
        if (nextWindow)
            CompositorService.activateToplevel(nextWindow);
    }

    onWheel: function (wheelEvent) {
        wheelEvent.accepted = true;
        const deltaY = wheelEvent.angleDelta.y;
        const isMouseWheel = Math.abs(deltaY) >= 120 && (Math.abs(deltaY) % 120) === 0;

        const windows = root.sortedToplevels.filter(w => !w.skipSwitcher);
        if (windows.length < 2)
            return;

        if (isMouseWheel) {
            activateNeighbor(windows, deltaY);
            return;
        }

        scrollAccumulator += deltaY;
        if (Math.abs(scrollAccumulator) < touchpadThreshold)
            return;
        activateNeighbor(windows, scrollAccumulator);
        scrollAccumulator = 0;
    }

    content: Component {
        Item {
            implicitWidth: layoutLoader.item ? layoutLoader.item.implicitWidth : 0
            implicitHeight: layoutLoader.item ? layoutLoader.item.implicitHeight : 0

            Loader {
                id: layoutLoader
                anchors.centerIn: parent
                sourceComponent: root.isVerticalOrientation ? columnLayout : rowLayout
            }
        }
    }

    ScriptModel {
        id: windowModel
        values: root._groupByApp ? root.groupedWindows : root.sortedToplevels
        objectProp: root.windowModelKey
    }

    Component {
        id: rowLayout
        Row {
            spacing: Theme.spacingXS

            Repeater {
                model: windowModel
                delegate: windowDelegate
            }
        }
    }

    Component {
        id: columnLayout
        Column {
            spacing: Theme.spacingXS

            Repeater {
                model: windowModel
                delegate: windowDelegate
            }
        }
    }

    Component {
        id: windowDelegate

        Item {
            id: delegateItem

            Component.onDestruction: {
                if (root.hoveredItem === delegateItem)
                    root.hoveredItem = null;
            }

            property bool isGrouped: root._groupByApp
            property var groupData: isGrouped ? modelData : null
            property var toplevelData: isGrouped ? (modelData.windows.length > 0 ? modelData.windows[0].toplevel : null) : modelData
            property bool isFocused: isGrouped ? (root.focusedAppId === appId) : (toplevelData ? toplevelData.activated : false)
            property string appId: isGrouped ? modelData.appId : (modelData.appId || "")
            readonly property string effectiveAppId: {
                root._appIdSubstitutionsTrigger;
                return Paths.moddedAppId(appId);
            }
            property string windowTitle: toplevelData ? (toplevelData.title || "(Unnamed)") : "(Unnamed)"
            property var toplevelObject: toplevelData
            property int windowCount: isGrouped ? modelData.windows.length : 1
            readonly property bool isMinimized: {
                if (!CompositorService.supportsMinimize)
                    return false;
                if (isGrouped)
                    return groupData.windows.length > 0 && groupData.windows.every(w => w.toplevel.minimized);
                return toplevelObject?.minimized === true;
            }
            property string tooltipText: {
                root._desktopEntriesUpdateTrigger;
                const desktopEntry = effectiveAppId ? DesktopEntries.heuristicLookup(effectiveAppId) : null;
                const appName = effectiveAppId ? Paths.getAppName(effectiveAppId, desktopEntry) : "Unknown";

                if (isGrouped && windowCount > 1) {
                    return appName + " (" + windowCount + " windows)";
                }
                return appName + (windowTitle ? " • " + windowTitle : "");
            }
            readonly property real visualWidth: root.compactMode ? root.iconCellSize : (root.iconCellSize + Theme.spacingXS + 120)

            width: root.isVerticalOrientation ? root.barThickness : visualWidth
            height: root.isVerticalOrientation ? root.iconCellSize : root.barThickness

            BarPillSurface {
                id: visualContent
                width: delegateItem.visualWidth
                height: root.iconCellSize
                anchors.centerIn: parent
                style: BarMetrics.widgetStyle(root.barConfig)
                pressed: mouseArea.pressed
                color: isFocused ? Theme.selectedContainer : "transparent"

                Rectangle {
                    anchors.fill: parent
                    radius: visualContent.radius
                    color: Theme.withAlpha(isFocused ? Theme.onSelectedContainer : Theme.onSurface, mouseArea.pressed ? Theme.stateLayerPressed : mouseArea.containsMouse ? Theme.stateLayerHover : 0)
                }

                IconImage {
                    id: iconImg
                    anchors.left: parent.left
                    anchors.leftMargin: root.compactMode ? Math.round((parent.width - root.appIconSize) / 2) : Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.appIconSize
                    height: root.appIconSize
                    source: {
                        root._desktopEntriesUpdateTrigger;
                        root._appIdSubstitutionsTrigger;
                        if (!effectiveAppId)
                            return "";
                        const desktopEntry = DesktopEntries.heuristicLookup(effectiveAppId);
                        return Paths.getAppIcon(effectiveAppId, desktopEntry);
                    }
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: status === Image.Ready
                    opacity: delegateItem.isMinimized ? 0.4 : 1
                    layer.enabled: Paths.isDmsAppId(appId)
                    layer.smooth: true
                    layer.mipmap: true
                    layer.effect: MultiEffect {
                        saturation: 0
                        colorization: 1
                        colorizationColor: Theme.primary
                    }
                }

                DIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: root.compactMode ? Math.round((parent.width - root.appIconSize) / 2) : Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    size: root.appIconSize
                    name: "sports_esports"
                    color: isFocused ? Theme.onSelectedContainer : Theme.widgetTextColor
                    visible: !iconImg.visible && Paths.isSteamApp(effectiveAppId)
                    opacity: delegateItem.isMinimized ? 0.4 : 1
                }

                StyledText {
                    anchors.horizontalCenter: iconImg.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !iconImg.visible && !Paths.isSteamApp(effectiveAppId)
                    text: {
                        root._desktopEntriesUpdateTrigger;
                        if (!effectiveAppId)
                            return "?";
                        const desktopEntry = DesktopEntries.heuristicLookup(effectiveAppId);
                        const appName = Paths.getAppName(effectiveAppId, desktopEntry);
                        return appName.charAt(0).toUpperCase();
                    }
                    font.pixelSize: 10
                    color: isFocused ? Theme.onSelectedContainer : Theme.widgetTextColor
                    opacity: delegateItem.isMinimized ? 0.4 : 1
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: root.compactMode ? -2 : 2
                    anchors.bottomMargin: -2
                    width: 14
                    height: 14
                    radius: Theme.fullRadius(width, height)
                    color: Theme.primary
                    visible: isGrouped && windowCount > 1
                    z: 10

                    StyledText {
                        anchors.centerIn: parent
                        text: windowCount > 9 ? "9+" : windowCount
                        font.pixelSize: 9
                        color: Theme.onPrimary
                    }
                }

                StyledText {
                    anchors.left: iconImg.right
                    anchors.leftMargin: Theme.spacingXS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.compactMode
                    text: windowTitle
                    font.pixelSize: Theme.barTextSize(barThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
                    color: isFocused ? Theme.onSelectedContainer : Theme.widgetTextColor
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                DRipple {
                    id: itemRipple
                    rippleColor: isFocused ? Theme.onSelectedContainer : Theme.onSurface
                    cornerRadius: visualContent.radius
                }
            }

            MouseArea {
                id: mouseArea
                y: root.isVerticalOrientation ? 0 : -root.topMargin
                x: root.isVerticalOrientation ? -root.leftMargin : 0
                width: parent.width + (root.isVerticalOrientation ? root.leftMargin + root.rightMargin : 0)
                height: parent.height + (root.isVerticalOrientation ? 0 : root.topMargin + root.bottomMargin)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => {
                    const pos = mapToItem(visualContent, mouse.x, mouse.y);
                    itemRipple.trigger(pos.x, pos.y);
                }
                onClicked: mouse => {
                    if (mouse.button === Qt.LeftButton) {
                        if (isGrouped && windowCount > 1) {
                            let currentIndex = -1;
                            for (var i = 0; i < groupData.windows.length; i++) {
                                if (groupData.windows[i].toplevel.activated) {
                                    currentIndex = i;
                                    break;
                                }
                            }
                            const nextIndex = (currentIndex + 1) % groupData.windows.length;
                            CompositorService.activateToplevel(groupData.windows[nextIndex].toplevel);
                        } else if (toplevelObject) {
                            CompositorService.toggleToplevel(toplevelObject);
                        }
                    } else if (mouse.button === Qt.RightButton) {
                        root.openContextMenu(toplevelObject, delegateItem);
                    } else if (mouse.button === Qt.MiddleButton) {
                        if (typeof toplevelObject?.close === "function")
                            toplevelObject.close();
                    }
                }
                onEntered: {
                    root.hoveredItem = delegateItem;
                    tooltipLoader.active = true;
                    if (!tooltipLoader.item)
                        return;
                    const anchor = root.edgeAnchor(delegateItem, 35);
                    const alignLeft = root.isVerticalOrientation && root.axis?.edge === "left";
                    const alignRight = root.isVerticalOrientation && root.axis?.edge !== "left";
                    tooltipLoader.item.show(delegateItem.tooltipText, anchor.x, anchor.y, root.parentScreen, alignLeft, alignRight);
                }
                onExited: {
                    if (root.hoveredItem === delegateItem)
                        root.hoveredItem = null;
                }
            }
        }
    }

    Loader {
        id: tooltipLoader

        active: false

        sourceComponent: DTooltip {}
    }

    function menuAnchorFor(item) {
        const anchor = root.contextMenuAnchor();
        const center = item.mapToGlobal(item.width / 2, item.height / 2);
        if (anchor.isVertical)
            anchor.y = center.y - (anchor.screen.y || 0) + root.minTooltipY;
        else
            anchor.x = center.x - (anchor.screen.x || 0);
        return anchor;
    }

    function openContextMenu(toplevelObject, item) {
        root.hideTooltip();
        windowContextMenu.currentWindow = toplevelObject ?? null;
        windowContextMenu.openFromBar(item ? root.menuAnchorFor(item) : root.contextMenuAnchor());
    }

    DContextMenu {
        id: windowContextMenu

        property var currentWindow: null

        layerNamespace: "dms:running-apps-context-menu"
        menuItems: {
            const items = [];
            if (CompositorService.canMinimize(currentWindow))
                items.push({
                    type: "item",
                    icon: currentWindow?.minimized ? "open_in_full" : "minimize",
                    text: currentWindow?.minimized ? I18n.tr("Restore") : I18n.tr("Minimize"),
                    action: () => {
                        const targetWindow = windowContextMenu.currentWindow;
                        if (!targetWindow)
                            return;
                        if (targetWindow.minimized)
                            CompositorService.activateToplevel(targetWindow);
                        else
                            targetWindow.minimized = true;
                    }
                });
            const scratchpad = CompositorService.windowScratchpadName(currentWindow);
            if (scratchpad)
                items.push({
                    type: "item",
                    icon: "outbox",
                    text: I18n.tr("Move out of scratchpad", "window context menu action, brings the window back from the special workspace"),
                    action: () => CompositorService.moveWindowOutOfSpecial(windowContextMenu.currentWindow)
                });
            for (const name of scratchpad ? [] : CompositorService.specialWorkspaceNames) {
                items.push({
                    type: "item",
                    icon: "inbox",
                    text: name === "special" ? I18n.tr("Move to scratchpad", "window context menu action, sends the window to the unnamed special workspace") : I18n.tr("Move to scratchpad: %1", "%1 is the named special workspace").arg(name),
                    action: () => CompositorService.moveWindowToSpecial(windowContextMenu.currentWindow, name)
                });
            }
            items.push({
                type: "item",
                icon: "close",
                text: I18n.tr("Close"),
                isDestructive: true,
                action: () => windowContextMenu.currentWindow?.close()
            });
            return items;
        }
        onOpenStateChanged: {
            const screenName = root.parentScreen?.name;
            if (!screenName)
                return;
            if (openState)
                TrayMenuManager.registerMenu(screenName, windowContextMenu.contextWindow);
            else
                TrayMenuManager.unregisterMenu(screenName);
        }
        Component.onDestruction: {
            if (openState && root.parentScreen?.name)
                TrayMenuManager.unregisterMenu(root.parentScreen.name);
        }
    }
}
