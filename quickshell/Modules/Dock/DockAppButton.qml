import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services
import qs.DCommon.Widgets

Item {
    id: root
    required property var options

    clip: false
    property var appData
    property var contextMenu: null
    property var dockApps: null
    property int index: -1
    property var parentDockScreen: null
    property bool longPressing: false
    property bool dragging: false
    property point dragStartPos: Qt.point(0, 0)
    property real dragAxisOffset: 0
    property int targetIndex: -1
    property int originalIndex: -1
    property bool isVertical: root.options.position === SettingsData.Position.Left || root.options.position === SettingsData.Position.Right
    property bool showWindowTitle: false
    property string windowTitle: ""
    property bool isHovered: mouseArea.containsMouse && !dragging
    property bool showTooltip: mouseArea.containsMouse && !dragging
    property var cachedDesktopEntry: dockApps?.desktopEntries[appData?.appId] ?? null
    property real actualIconSize: 40
    readonly property real iconLoadScale: {
        const config = dockApps?.surfaceContext?.config;
        const magnified = config?.magnification ? config.magnificationScale / 100 : 1;
        const enlarged = options?.enlargeOnHover ? (options?.enlargePercentage ?? 125) / 100 : 1;
        return Math.max(1, magnified * enlarged);
    }
    readonly property bool indicatorAtFarEdge: root.options.position === SettingsData.Position.Bottom || root.options.position === SettingsData.Position.Right
    readonly property bool indicatorInPadding: !(root.dockApps?.barHosted ?? false)
    readonly property real indicatorThickness: indicatorInPadding ? root.options.spacing : Math.max(0, ((isVertical ? width : height) - actualIconSize) / 2)
    property bool shouldShowIndicator: {
        if (root.options.hideIndicators)
            return false;
        if (!appData)
            return false;
        if (appData.type === "window")
            return true;
        if (appData.type === "grouped")
            return appData.windowCount > 0;
        return appData.isRunning;
    }
    readonly property string coreIconColorOverride: root.options.launcherLogoColorOverride
    readonly property bool coreIconHasCustomColor: coreIconColorOverride !== "" && coreIconColorOverride !== "primary" && coreIconColorOverride !== "surface"
    readonly property color effectiveCoreIconColor: {
        if (coreIconColorOverride === "primary")
            return Theme.primary;
        if (coreIconColorOverride === "surface")
            return Theme.surfaceText;
        if (coreIconColorOverride !== "")
            return coreIconColorOverride;
        return Theme.surfaceText;
    }
    readonly property real effectiveCoreIconBrightness: coreIconHasCustomColor ? root.options.launcherLogoBrightness : 0.0
    readonly property real effectiveCoreIconContrast: coreIconHasCustomColor ? root.options.launcherLogoContrast : 0.0

    function updateDesktopEntry() {
        dockApps?.refreshDesktopEntries();
    }

    property bool isWindowFocused: {
        if (!appData) {
            return false;
        }

        if (appData.type === "window") {
            const toplevel = getToplevelObject();
            return isToplevelFocused(toplevel);
        }
        if (appData.type === "grouped")
            return getGroupedToplevels().some(toplevel => isToplevelFocused(toplevel));

        return false;
    }
    readonly property bool isMinimized: {
        if (!CompositorService.supportsMinimize || !appData) {
            return false;
        }

        switch (appData.type) {
        case "window":
            return getToplevelObject()?.minimized === true;
        case "grouped":
            {
                const toplevels = getGroupedToplevels();
                return toplevels.length > 0 && toplevels.every(t => t.minimized);
            }
        default:
            return false;
        }
    }
    property string tooltipText: {
        if (!appData || !appData.appId) {
            return "";
        }

        let appName;
        if (appData.isCoreApp && appData.coreAppData) {
            appName = appData.coreAppData.name || appData.appId;
        } else {
            appName = Paths.getAppName(appData.appId, cachedDesktopEntry);
        }

        if ((appData.type === "window" && showWindowTitle) || (appData.type === "grouped" && appData.windowTitle)) {
            const title = appData.type === "window" ? windowTitle : appData.windowTitle;
            return appName + (title ? " • " + title : "");
        }

        return appName;
    }

    function getToplevelObject() {
        return appData?.toplevel || null;
    }

    function getGroupedToplevels() {
        return appData?.allWindows?.map(w => w.toplevel).filter(t => t !== null) || [];
    }

    function isToplevelFocused(toplevel) {
        if (!toplevel)
            return false;
        if (toplevel.activated)
            return true;
        return CompositorService.overviewFocusedToplevel([toplevel]) !== null;
    }

    function restoreSpecialWorkspaceWindow(waylandToplevel) {
        if (!root.options.restoreSpecialWorkspaceOnClick || !waylandToplevel)
            return false;

        const specialName = CompositorService.specialWorkspaceName(waylandToplevel);
        if (!specialName)
            return false;

        HyprlandService.toggleSpecial(specialName);
        Qt.callLater(() => CompositorService.activateToplevel(waylandToplevel));
        return true;
    }

    function getActiveGroupedToplevelIndex(toplevels) {
        for (let i = 0; i < toplevels.length; i++) {
            if (isToplevelFocused(toplevels[i]))
                return i;
        }

        return -1;
    }

    function cycleGroupedToplevels() {
        const toplevels = getGroupedToplevels();
        if (toplevels.length === 0)
            return;

        const currentIndex = getActiveGroupedToplevelIndex(toplevels);
        const nextToplevel = toplevels[(currentIndex + 1) % toplevels.length];
        if (restoreSpecialWorkspaceWindow(nextToplevel))
            return;
        CompositorService.activateToplevel(nextToplevel);
    }

    function showContextMenu() {
        if (!contextMenu)
            return;
        const shouldHidePin = Paths.isDmsAppId(appData.appId);
        contextMenu.showForButton(root, appData, root.height, shouldHidePin, cachedDesktopEntry, parentDockScreen, dockApps);
    }
    function activate() {
        mouseArea.handleLeftClick();
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusS
        color: Theme.withAlpha(root.activeColor, Theme.stateLayerPressed)
        visible: root.options.colorizeActive && root.isWindowFocused
        z: -1
    }
    readonly property color activeColor: {
        switch (root.options.activeColorMode) {
        case "secondary":
            return Theme.secondary;
        case "primaryContainer":
            return Theme.primaryContainer;
        case "error":
            return Theme.error;
        case "success":
            return Theme.success;
        default:
            return Theme.primary;
        }
    }
    StyledText {
        visible: root.options.compact === false && !root.isVertical
        x: root.actualIconSize + Theme.spacingM
        width: Math.max(0, parent.width - x - Theme.spacingS)
        anchors.verticalCenter: parent.verticalCenter
        text: root.windowTitle || root.tooltipText
        elide: Text.ElideRight
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeSmall
    }

    Timer {
        id: longPressTimer

        interval: 500
        repeat: false
        onTriggered: {
            if (appData && appData.isPinned) {
                longPressing = true;
            }
        }
    }

    function cancelDrag() {
        longPressTimer.stop();
        longPressing = false;
        dragging = false;
        dragAxisOffset = 0;
        targetIndex = -1;
        originalIndex = -1;
        if (!dockApps)
            return;
        dockApps.draggedIndex = -1;
        dockApps.dropTargetIndex = -1;
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        enabled: true
        preventStealing: dragging || longPressing
        cursorShape: longPressing ? Qt.DragMoveCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: mouse => {
            if (mouse.button === Qt.LeftButton && appData && appData.isPinned) {
                dragStartPos = Qt.point(mouse.x, mouse.y);
                longPressTimer.start();
            }
        }
        onCanceled: root.cancelDrag()

        onReleased: mouse => {
            longPressTimer.stop();

            const wasDragging = dragging;
            const didReorder = wasDragging && targetIndex >= 0 && dockApps && (targetIndex !== originalIndex || dockApps.mixedDropIndex >= 0);

            if (didReorder) {
                const from = originalIndex;
                const to = dockApps.dropTarget(targetIndex);
                dockApps.settleDrag(() => dockApps.movePinnedApp(from, to));
            }

            root.cancelDrag();

            if (wasDragging || mouse.button !== Qt.LeftButton)
                return;

            handleLeftClick();
        }

        function handleLeftClick() {
            if (!appData)
                return;

            switch (appData.type) {
            case "pinned":
                if (!appData.appId)
                    return;
                if (appData.isCoreApp && appData.coreAppData) {
                    AppSearchService.executeCoreApp(appData.coreAppData);
                    return;
                }
                const pinnedEntry = cachedDesktopEntry;
                if (pinnedEntry) {
                    AppUsageHistoryData.addAppUsage({
                        "id": appData.appId,
                        "name": pinnedEntry.name || appData.appId,
                        "icon": pinnedEntry.icon ? String(pinnedEntry.icon) : "",
                        "exec": pinnedEntry.exec || "",
                        "comment": pinnedEntry.comment || ""
                    });
                }
                SessionService.launchDesktopEntry(pinnedEntry);
                break;
            case "window":
                const windowToplevel = getToplevelObject();
                if (windowToplevel) {
                    if (restoreSpecialWorkspaceWindow(windowToplevel))
                        return;
                    CompositorService.toggleToplevel(windowToplevel);
                }
                break;
            case "grouped":
                if (appData.windowCount === 0) {
                    if (!appData.appId)
                        return;
                    if (appData.isCoreApp && appData.coreAppData) {
                        AppSearchService.executeCoreApp(appData.coreAppData);
                        return;
                    }
                    const groupedEntry = cachedDesktopEntry;
                    if (groupedEntry) {
                        AppUsageHistoryData.addAppUsage({
                            "id": appData.appId,
                            "name": groupedEntry.name || appData.appId,
                            "icon": groupedEntry.icon ? String(groupedEntry.icon) : "",
                            "exec": groupedEntry.exec || "",
                            "comment": groupedEntry.comment || ""
                        });
                    }
                    SessionService.launchDesktopEntry(groupedEntry);
                } else if (appData.windowCount === 1) {
                    const groupedToplevel = getToplevelObject();
                    if (groupedToplevel) {
                        if (restoreSpecialWorkspaceWindow(groupedToplevel))
                            return;
                        CompositorService.toggleToplevel(groupedToplevel);
                    }
                } else {
                    root.cycleGroupedToplevels();
                }
                break;
            }
        }
        onPositionChanged: mouse => {
            if (longPressing && !dragging) {
                const distance = Math.sqrt(Math.pow(mouse.x - dragStartPos.x, 2) + Math.pow(mouse.y - dragStartPos.y, 2));
                if (distance > 5) {
                    dragging = true;
                    targetIndex = index;
                    originalIndex = index;
                    if (dockApps) {
                        dockApps.draggedIndex = index;
                        dockApps.dropTargetIndex = index;
                    }
                }
            }

            if (!dragging || !dockApps)
                return;

            const axisOffset = isVertical ? (mouse.y - dragStartPos.y) : (mouse.x - dragStartPos.x);
            dragAxisOffset = axisOffset;
            dockApps.updateMixedDrag(mouseArea, mouse.x, mouse.y);

            const slotOffset = Math.round(axisOffset / (dockApps.targetSize + dockApps.itemSpacing));
            const newTargetIndex = Math.max(0, Math.min(dockApps.pinnedAppCount - 1, originalIndex + slotOffset));

            if (newTargetIndex !== targetIndex) {
                targetIndex = newTargetIndex;
                dockApps.dropTargetIndex = newTargetIndex;
            }
        }
        onClicked: mouse => {
            if (!appData)
                return;

            if (mouse.button === Qt.MiddleButton) {
                switch (appData.type) {
                case "window":
                    appData.toplevel?.close();
                    break;
                case "grouped":
                    const groupedToplevels = getGroupedToplevels();
                    if (groupedToplevels.length === 0)
                        return;
                    const activeIndex = getActiveGroupedToplevelIndex(groupedToplevels);
                    const groupedToplevelToClose = groupedToplevels[activeIndex >= 0 ? activeIndex : 0];
                    groupedToplevelToClose?.close();
                    break;
                default:
                    if (!appData.appId)
                        return;
                    const desktopEntry = cachedDesktopEntry;
                    if (desktopEntry) {
                        AppUsageHistoryData.addAppUsage({
                            "id": appData.appId,
                            "name": desktopEntry.name || appData.appId,
                            "icon": desktopEntry.icon ? String(desktopEntry.icon) : "",
                            "exec": desktopEntry.exec || "",
                            "comment": desktopEntry.comment || ""
                        });
                    }
                    SessionService.launchDesktopEntry(desktopEntry);
                    break;
                }
            } else if (mouse.button === Qt.RightButton) {
                root.showContextMenu();
            }
        }
    }

    readonly property real hoverAnimOffset: hoverBounce.offset

    DockHoverBounce {
        id: hoverBounce
        hovered: root.isHovered
        suppressed: mouseArea.pressed || root.dragging
        barHosted: root.dockApps?.barHosted ?? false
        position: root.options.position
        distance: root.actualIconSize
    }

    Item {
        id: visualContent
        x: root.options.compact === false && !root.isVertical ? 0 : (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: root.options.compact === false && !root.isVertical ? root.actualIconSize + Theme.spacingS : parent.width
        height: parent.height

        transform: Translate {
            id: iconTransform
            x: {
                if (dragging && !isVertical)
                    return dragAxisOffset;
                if (!dragging && isVertical)
                    return hoverAnimOffset;
                return 0;
            }
            y: {
                if (dragging && isVertical)
                    return dragAxisOffset;
                if (!dragging && !isVertical)
                    return hoverAnimOffset;
                return 0;
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.primarySelected
            border.width: 2
            border.color: Theme.primary
            visible: dragging
            z: -1
        }

        Item {
            id: iconSlot

            anchors.fill: parent
            scale: root.options?.enlargeOnHover && root.isHovered ? (root.options?.enlargePercentage ?? 125) / 100 : 1

            AppIconRenderer {
                id: coreIcon

                anchors.centerIn: parent
                iconSize: actualIconSize
                iconValue: appData && appData.isCoreApp && appData.coreAppData ? (appData.coreAppData.icon || "") : ""
                colorOverride: effectiveCoreIconColor
                brightnessOverride: effectiveCoreIconBrightness
                contrastOverride: effectiveCoreIconContrast
                fallbackText: "?"
                visible: iconValue !== ""
            }

            Image {
                id: iconImg

                readonly property real displaySize: appData && Paths.isDmsAppId(appData.appId) ? actualIconSize * 0.85 : actualIconSize

                anchors.centerIn: parent
                width: displaySize
                height: displaySize
                fillMode: Image.PreserveAspectFit
                sourceSize: Qt.size(displaySize * root.iconLoadScale, displaySize * root.iconLoadScale)
                source: {
                    if (!appData || appData.appId === "__SEPARATOR__") {
                        return "";
                    }
                    if (appData.isCoreApp && appData.coreAppData) {
                        return "";
                    }
                    return Paths.getAppIcon(appData.appId, cachedDesktopEntry);
                }
                mipmap: true
                smooth: true
                asynchronous: true
                visible: status === Image.Ready && !coreIcon.visible
                opacity: root.isMinimized ? 0.4 : 1
                layer.enabled: appData && Paths.isDmsAppId(appData.appId)
                layer.smooth: true
                layer.mipmap: true
                layer.effect: MultiEffect {
                    saturation: 0
                    colorization: 1
                    colorizationColor: Theme.primary
                }
            }

            Rectangle {
                width: actualIconSize
                height: actualIconSize
                anchors.centerIn: parent
                visible: !coreIcon.visible && iconImg.status !== Image.Ready && appData && appData.appId && !Paths.isSteamApp(appData.appId)
                opacity: root.isMinimized ? 0.4 : 1
                color: Theme.surfaceLight
                radius: Theme.cornerRadius
                border.width: 1
                border.color: Theme.primarySelected

                StyledText {
                    anchors.centerIn: parent
                    text: {
                        if (!appData || !appData.appId) {
                            return "?";
                        }

                        let appName;
                        if (appData.isCoreApp && appData.coreAppData) {
                            appName = appData.coreAppData.name || appData.appId;
                        } else {
                            appName = Paths.getAppName(appData.appId, cachedDesktopEntry);
                        }
                        return appName.charAt(0).toUpperCase();
                    }
                    font.pixelSize: Math.max(8, parent.width * 0.35)
                    color: Theme.primary
                    font.weight: Theme.fontWeightMedium
                }
            }

            DIcon {
                anchors.centerIn: parent
                size: actualIconSize
                name: "sports_esports"
                color: Theme.surfaceText
                visible: !coreIcon.visible && iconImg.status !== Image.Ready && appData && appData.appId && Paths.isSteamApp(appData.appId)
                opacity: root.isMinimized ? 0.4 : 1
            }
        }

        Item {
            id: indicatorSlot

            readonly property real cellSize: root.isVertical ? parent.width : parent.height
            readonly property real crossStart: {
                if (root.indicatorAtFarEdge)
                    return root.indicatorInPadding ? cellSize : cellSize - root.indicatorThickness;
                return root.indicatorInPadding ? -root.indicatorThickness : 0;
            }

            x: root.isVertical ? crossStart : 0
            y: root.isVertical ? 0 : crossStart
            width: root.isVertical ? root.indicatorThickness : parent.width
            height: root.isVertical ? parent.height : root.indicatorThickness

            Loader {
                anchors.centerIn: parent
                width: item ? item.implicitWidth : 0
                height: item ? item.implicitHeight : 0
                sourceComponent: root.isVertical ? columnIndicator : rowIndicator
                visible: root.shouldShowIndicator
            }
        }
    }

    Component {
        id: rowIndicator

        Row {
            spacing: Theme.spacingXXS
            width: implicitWidth
            height: implicitHeight

            Repeater {
                model: {
                    if (!appData)
                        return 0;
                    if (appData.type === "grouped") {
                        return Math.min(appData.windowCount, 4);
                    } else if (appData.type === "window" || appData.isRunning) {
                        return 1;
                    }
                    return 0;
                }

                Rectangle {
                    readonly property bool dotFocused: {
                        if (!appData)
                            return false;
                        if (appData.type !== "grouped" || appData.windowCount === 1)
                            return isWindowFocused;
                        const groupToplevels = getGroupedToplevels();
                        return index < groupToplevels.length && isToplevelFocused(groupToplevels[index]);
                    }
                    readonly property real baseWidth: {
                        if (root.options.indicatorStyle === "circle")
                            return Math.max(4, actualIconSize * 0.1);
                        return appData && appData.type === "grouped" && appData.windowCount > 1 ? Math.max(3, actualIconSize * 0.1) : Math.max(6, actualIconSize * 0.2);
                    }
                    width: dotFocused ? baseWidth * 3 : baseWidth
                    height: {
                        if (root.options.indicatorStyle === "circle") {
                            return Math.max(4, actualIconSize * 0.1);
                        }
                        return Math.max(2, actualIconSize * 0.05);
                    }
                    radius: height / 2
                    color: !appData ? "transparent" : (dotFocused ? Theme.primary : Theme.surfaceTextSecondary)

                    Behavior on width {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                        }
                    }
                }
            }
        }
    }

    Component {
        id: columnIndicator

        Column {
            spacing: Theme.spacingXXS
            width: implicitWidth
            height: implicitHeight

            Repeater {
                model: {
                    if (!appData)
                        return 0;
                    if (appData.type === "grouped") {
                        return Math.min(appData.windowCount, 4);
                    } else if (appData.type === "window" || appData.isRunning) {
                        return 1;
                    }
                    return 0;
                }

                Rectangle {
                    readonly property bool dotFocused: {
                        if (!appData)
                            return false;
                        if (appData.type !== "grouped" || appData.windowCount === 1)
                            return isWindowFocused;
                        const groupToplevels = getGroupedToplevels();
                        return index < groupToplevels.length && isToplevelFocused(groupToplevels[index]);
                    }
                    readonly property real baseHeight: {
                        if (root.options.indicatorStyle === "circle")
                            return Math.max(4, actualIconSize * 0.1);
                        return appData && appData.type === "grouped" && appData.windowCount > 1 ? Math.max(3, actualIconSize * 0.1) : Math.max(6, actualIconSize * 0.2);
                    }
                    width: {
                        if (root.options.indicatorStyle === "circle") {
                            return Math.max(4, actualIconSize * 0.1);
                        }
                        return Math.max(2, actualIconSize * 0.05);
                    }
                    height: dotFocused ? baseHeight * 3 : baseHeight
                    radius: width / 2
                    color: !appData ? "transparent" : (dotFocused ? Theme.primary : Theme.surfaceTextSecondary)

                    Behavior on height {
                        NumberAnimation {
                            duration: Theme.shortDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.shortDuration
                        }
                    }
                }
            }
        }
    }
}
