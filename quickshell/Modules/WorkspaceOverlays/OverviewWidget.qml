import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: root
    readonly property var log: Log.scoped("OverviewWidget")
    required property var panelWindow
    required property bool overviewOpen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property real dpr: CompositorService.getScreenScale(panelWindow.screen)
    readonly property int workspacesShown: SettingsData.overviewRows * SettingsData.overviewColumns
    readonly property alias windowMenuWindow: windowMenu.contextWindow

    function openWindowMenu(item, x, y) {
        const address = item.windowData?.address;
        if (!address || CompositorService.specialWorkspaceNames.length === 0)
            return;
        windowMenu.targetWindow = address;
        const pos = item.mapToGlobal(x, y);
        windowMenu.open(panelWindow.screen, pos.x - (panelWindow.screen?.x || 0), pos.y - (panelWindow.screen?.y || 0), false);
    }

    // scratchpad windows are not in the grid, so the menu only ever offers a move in
    DContextMenu {
        id: windowMenu

        property string targetWindow: ""

        layerNamespace: "dms:overview-window-context-menu"
        menuItems: CompositorService.specialWorkspaceNames.map(name => ({
                    type: "item",
                    icon: "inbox",
                    text: name === "special" ? I18n.tr("Move to scratchpad", "window context menu action, sends the window to the unnamed special workspace") : I18n.tr("Move to scratchpad: %1", "%1 is the named special workspace").arg(name),
                    action: () => {
                        CompositorService.moveWindowToSpecial(windowMenu.targetWindow, name);
                        Qt.callLater(() => {
                            Hyprland.refreshToplevels();
                            Hyprland.refreshWorkspaces();
                        });
                    }
                }))
    }

    readonly property var allWorkspaces: Hyprland.workspaces?.values || []
    readonly property var allWorkspaceIds: {
        const workspaces = allWorkspaces;
        if (!workspaces || workspaces.length === 0)
            return [];
        try {
            const ids = workspaces.map(ws => ws?.id).filter(id => id > 0);
            return ids.sort((a, b) => a - b);
        } catch (e) {
            return [];
        }
    }

    readonly property var thisMonitorWorkspaceIds: {
        const workspaces = allWorkspaces;
        const mon = monitor;
        if (!workspaces || workspaces.length === 0 || !mon)
            return [];
        try {
            const filtered = workspaces.filter(ws => ws?.monitor?.name === mon.name);
            return filtered.map(ws => ws?.id).filter(id => id > 0).sort((a, b) => a - b);
        } catch (e) {
            return [];
        }
    }

    readonly property var displayedWorkspaceIds: {
        if (!allWorkspaceIds || allWorkspaceIds.length === 0) {
            const result = [];
            for (let i = 1; i <= workspacesShown; i++) {
                result.push(i);
            }
            return result;
        }

        try {
            const maxExisting = Math.max(...allWorkspaceIds);
            const totalNeeded = Math.max(workspacesShown, allWorkspaceIds.length);
            const result = [];

            for (let i = 1; i <= maxExisting; i++) {
                result.push(i);
            }

            let nextId = maxExisting + 1;
            while (result.length < totalNeeded) {
                result.push(nextId);
                nextId++;
            }

            return result;
        } catch (e) {
            const result = [];
            for (let i = 1; i <= workspacesShown; i++) {
                result.push(i);
            }
            return result;
        }
    }

    readonly property int minWorkspaceId: displayedWorkspaceIds.length > 0 ? displayedWorkspaceIds[0] : 1
    readonly property int maxWorkspaceId: displayedWorkspaceIds.length > 0 ? displayedWorkspaceIds[displayedWorkspaceIds.length - 1] : workspacesShown
    readonly property int displayWorkspaceCount: displayedWorkspaceIds.length

    readonly property int effectiveColumns: SettingsData.overviewColumns

    function getWorkspaceMonitorName(workspaceId) {
        if (!allWorkspaces || !workspaceId)
            return "";
        try {
            const ws = allWorkspaces.find(w => w?.id === workspaceId);
            return ws?.monitor?.name ?? "";
        } catch (e) {
            return "";
        }
    }

    function workspaceHasWindows(workspaceId) {
        if (!workspaceId)
            return false;
        try {
            const workspace = allWorkspaces.find(ws => ws?.id === workspaceId);
            if (!workspace)
                return false;
            const toplevels = workspace?.toplevels?.values || [];
            return toplevels.length > 0;
        } catch (e) {
            return false;
        }
    }

    function monitorIpcForWorkspace(workspaceId) {
        const workspace = allWorkspaces?.find(ws => ws?.id === workspaceId);
        return workspace?.monitor?.lastIpcObject ?? monitor?.lastIpcObject ?? null;
    }

    function monitorLogicalSize(ipc) {
        if (!ipc || !ipc.width || !ipc.height)
            return {
                "width": monitorPhysicalWidth,
                "height": monitorPhysicalHeight
            };

        const monScale = ipc.scale > 0 ? ipc.scale : 1;
        const rotated = ((ipc.transform ?? 0) % 2) === 1;
        return {
            "width": (rotated ? ipc.height : ipc.width) / monScale,
            "height": (rotated ? ipc.width : ipc.height) / monScale
        };
    }

    function cellForWorkspace(workspaceId) {
        const cell = gridLayout.cells.find(c => c.id === workspaceId);
        if (cell)
            return cell;
        return {
            "id": workspaceId,
            "x": 0,
            "y": 0,
            "width": workspaceImplicitWidth,
            "height": workspaceImplicitHeight
        };
    }

    function getWorkspaceViewportBounds(workspaceId, cellWidth, cellHeight) {
        const ipc = monitorIpcForWorkspace(workspaceId) ?? {};
        const logical = monitorLogicalSize(ipc);
        const reserved = ipc.reserved || [0, 0, 0, 0];

        const x = (ipc.x ?? 0) + (reserved[0] ?? 0);
        const y = (ipc.y ?? 0) + (reserved[1] ?? 0);
        const width = Math.max(logical.width - (reserved[0] ?? 0) - (reserved[2] ?? 0), 1);
        const height = Math.max(logical.height - (reserved[1] ?? 0) - (reserved[3] ?? 0), 1);

        return {
            "x": x,
            "y": y,
            "scale": Math.min(cellWidth / width, cellHeight / height)
        };
    }

    property bool monitorIsFocused: monitor?.focused ?? false
    property real scale: SettingsData.overviewScale
    property color activeBorderColor: Theme.primary

    readonly property real monitorPhysicalWidth: panelWindow.screen ? (panelWindow.screen.width / root.dpr) : (monitor?.width ?? 1920)
    readonly property real monitorPhysicalHeight: panelWindow.screen ? (panelWindow.screen.height / root.dpr) : (monitor?.height ?? 1080)
    property real workspaceImplicitWidth: monitorPhysicalWidth * root.scale
    property real workspaceImplicitHeight: monitorPhysicalHeight * root.scale

    property int workspaceZ: 0
    property int windowZ: 1
    property int monitorLabelZ: 2
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 5
    readonly property int workspaceBorderWidth: 2

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    readonly property var gridLayout: {
        const ids = displayedWorkspaceIds;
        const columns = effectiveColumns;
        if (!ids || ids.length === 0 || columns < 1)
            return {
                "cells": [],
                "width": 0,
                "height": 0
            };

        const rows = [];
        for (let i = 0; i < ids.length; i += columns) {
            rows.push(ids.slice(i, i + columns).map(id => {
                const logical = monitorLogicalSize(monitorIpcForWorkspace(id));
                return {
                    "id": id,
                    "width": logical.width * scale,
                    "height": logical.height * scale
                };
            }));
        }

        const rowWidth = row => row.reduce((acc, cell) => acc + cell.width, 0) + workspaceSpacing * (row.length - 1);
        const totalWidth = rows.reduce((acc, row) => Math.max(acc, rowWidth(row)), 0);

        const cells = [];
        let cursorY = 0;
        for (const row of rows) {
            const rowHeight = row.reduce((acc, cell) => Math.max(acc, cell.height), 0);
            let cursorX = (totalWidth - rowWidth(row)) / 2;
            for (const cell of row) {
                cells.push({
                    "id": cell.id,
                    "x": cursorX,
                    "y": cursorY + (rowHeight - cell.height) / 2,
                    "width": cell.width,
                    "height": cell.height
                });
                cursorX += cell.width + workspaceSpacing;
            }
            cursorY += rowHeight + workspaceSpacing;
        }

        return {
            "cells": cells,
            "width": totalWidth,
            "height": cursorY - workspaceSpacing
        };
    }

    implicitWidth: overviewBackground.implicitWidth + Theme.spacingL * 2
    implicitHeight: overviewBackground.implicitHeight + Theme.spacingL * 2

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
    }

    onOverviewOpenChanged: {
        if (overviewOpen) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshMonitors();
        }
    }

    Rectangle {
        id: overviewBackground
        property real padding: 10
        anchors.fill: parent
        anchors.margins: Theme.spacingL

        implicitWidth: workspaceGrid.implicitWidth + padding * 2
        implicitHeight: workspaceGrid.implicitHeight + padding * 2
        radius: Theme.cornerRadius
        color: Theme.hostSurface

        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel2
            fallbackOffset: 4
            targetRadius: Theme.cornerRadius
            targetColor: Theme.hostSurface
            shadowOpacity: Theme.elevationLevel2 && Theme.elevationLevel2.alpha !== undefined ? Theme.elevationLevel2.alpha : 0.25
            shadowEnabled: Theme.elevationEnabled
        }

        Item {
            id: workspaceGrid

            z: root.workspaceZ
            anchors.centerIn: parent
            implicitWidth: root.gridLayout.width
            implicitHeight: root.gridLayout.height

            Repeater {
                model: root.gridLayout.cells.length

                Rectangle {
                    id: workspace
                    required property int index
                    readonly property var cell: root.gridLayout.cells[index] ?? null
                    property int workspaceValue: cell?.id ?? -1
                    property bool workspaceExists: (root.allWorkspaceIds && workspaceValue > 0) ? root.allWorkspaceIds.includes(workspaceValue) : false
                    property var workspaceObj: (workspaceExists && Hyprland.workspaces?.values) ? Hyprland.workspaces.values.find(ws => ws?.id === workspaceValue) : null
                    property bool isActive: workspaceObj?.active ?? false
                    property bool isOnThisMonitor: (workspaceObj && root.monitor) ? (workspaceObj.monitor?.name === root.monitor.name) : true
                    property bool hasWindows: (workspaceValue > 0) ? root.workspaceHasWindows(workspaceValue) : false
                    property color defaultWorkspaceColor: workspaceExists ? Theme.cardSurface : Theme.withAlpha(Theme.cardSurface, 0.3)
                    property color hoveredWorkspaceColor: Theme.hoverTint(defaultWorkspaceColor)
                    property color hoveredBorderColor: Theme.surfaceVariant
                    property bool hoveredWhileDragging: false
                    property bool shouldShowActiveIndicator: isActive && isOnThisMonitor && hasWindows

                    visible: workspaceValue !== -1

                    x: cell?.x ?? 0
                    y: cell?.y ?? 0
                    width: cell?.width ?? 0
                    height: cell?.height ?? 0
                    color: hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor
                    radius: Theme.cornerRadius
                    border.width: root.workspaceBorderWidth
                    border.color: hoveredWhileDragging ? hoveredBorderColor : (shouldShowActiveIndicator ? root.activeBorderColor : Theme.withAlpha(root.activeBorderColor, 0))

                    StyledText {
                        anchors.centerIn: parent
                        text: workspace.workspaceValue
                        font.pixelSize: Theme.fontSizeXLarge * 6
                        font.weight: Theme.fontWeightMedium
                        color: Theme.withAlpha(Theme.surfaceText, workspace.workspaceExists ? 0.2 : 0.1)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        id: workspaceArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            if (root.draggingTargetWorkspace === -1) {
                                root.overviewOpen = false;
                                HyprlandService.focusWorkspace(workspace.workspaceValue);
                            }
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        onEntered: {
                            root.draggingTargetWorkspace = workspace.workspaceValue;
                            if (root.draggingFromWorkspace == root.draggingTargetWorkspace)
                                return;
                            workspace.hoveredWhileDragging = true;
                        }
                        onExited: {
                            workspace.hoveredWhileDragging = false;
                            if (root.draggingTargetWorkspace == workspace.workspaceValue)
                                root.draggingTargetWorkspace = -1;
                        }
                    }
                }
            }
        }

        Item {
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceGrid.implicitWidth
            implicitHeight: workspaceGrid.implicitHeight

            Repeater {
                model: ScriptModel {
                    values: {
                        const workspaces = root.allWorkspaces;
                        const minId = root.minWorkspaceId;
                        const maxId = root.maxWorkspaceId;

                        if (!workspaces || workspaces.length === 0)
                            return [];

                        try {
                            const result = [];
                            for (const workspace of workspaces) {
                                const wsId = workspace?.id ?? -1;
                                if (wsId >= minId && wsId <= maxId) {
                                    const toplevels = workspace?.toplevels?.values || [];
                                    for (const toplevel of toplevels) {
                                        result.push(toplevel);
                                    }
                                }
                            }
                            return result;
                        } catch (e) {
                            log.error("OverviewWidget filter error:", e);
                            return [];
                        }
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData

                    overviewOpen: root.overviewOpen
                    readonly property int windowWorkspaceId: modelData?.workspace?.id ?? -1
                    readonly property var workspaceCell: root.cellForWorkspace(windowWorkspaceId)
                    readonly property real contentWidth: workspaceCell.width - root.workspaceBorderWidth * 2
                    readonly property real contentHeight: workspaceCell.height - root.workspaceBorderWidth * 2
                    readonly property var workspaceBounds: root.getWorkspaceViewportBounds(windowWorkspaceId, contentWidth, contentHeight)

                    toplevel: modelData
                    scale: root.scale
                    monitorDpr: root.dpr
                    availableWorkspaceWidth: contentWidth
                    availableWorkspaceHeight: contentHeight
                    contentOriginX: workspaceBounds.x
                    contentOriginY: workspaceBounds.y
                    contentScale: workspaceBounds.scale
                    widgetMonitorId: root.monitor.id

                    xOffset: workspaceCell.x + root.workspaceBorderWidth
                    yOffset: workspaceCell.y + root.workspaceBorderWidth

                    z: atInitPosition ? root.windowZ : root.windowDraggingZ
                    property bool atInitPosition: (initX == x && initY == y)

                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: window.hovered = true
                        onExited: window.hovered = false
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent

                        onPressed: mouse => {
                            root.draggingFromWorkspace = windowData?.workspace.id;
                            window.pressed = true;
                            window.Drag.active = true;
                            window.Drag.source = window;
                            window.Drag.hotSpot.x = mouse.x;
                            window.Drag.hotSpot.y = mouse.y;
                        }

                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace;
                            window.pressed = false;
                            window.Drag.active = false;
                            root.draggingFromWorkspace = -1;
                            root.draggingTargetWorkspace = -1;

                            if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                                HyprlandService.moveToWorkspace(targetWorkspace, windowData?.address, false);
                                Qt.callLater(() => {
                                    Hyprland.refreshToplevels();
                                    Hyprland.refreshWorkspaces();
                                    Qt.callLater(() => {
                                        window.x = window.initX;
                                        window.y = window.initY;
                                    });
                                });
                            } else {
                                window.x = window.initX;
                                window.y = window.initY;
                            }
                        }

                        onClicked: event => {
                            if (!windowData || !windowData.address)
                                return;
                            if (event.button === Qt.LeftButton) {
                                root.overviewOpen = false;
                                HyprlandService.focusWindow(windowData.address);
                                event.accepted = true;
                            } else if (event.button === Qt.MiddleButton) {
                                HyprlandService.closeWindow(windowData.address);
                                event.accepted = true;
                            }
                        }
                    }

                    // on top of dragArea so a right press never starts a drag
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: mouse => root.openWindowMenu(window, mouse.x, mouse.y)
                    }
                }
            }
        }

        Item {
            id: monitorLabelSpace
            anchors.centerIn: parent
            implicitWidth: workspaceGrid.implicitWidth
            implicitHeight: workspaceGrid.implicitHeight
            z: root.monitorLabelZ

            Repeater {
                model: root.gridLayout.cells.length
                delegate: Item {
                    id: labelItem
                    required property int index
                    readonly property var cell: root.gridLayout.cells[index] ?? null
                    property int workspaceValue: cell?.id ?? -1
                    property bool workspaceExists: (root.allWorkspaceIds && workspaceValue > 0) ? root.allWorkspaceIds.includes(workspaceValue) : false
                    property string workspaceMonitorName: (workspaceValue > 0) ? root.getWorkspaceMonitorName(workspaceValue) : ""

                    x: cell?.x ?? 0
                    y: cell?.y ?? 0
                    width: cell?.width ?? 0
                    height: cell?.height ?? 0

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingS
                        width: monitorNameText.contentWidth + Theme.spacingS * 2
                        height: monitorNameText.contentHeight + Theme.spacingXS * 2
                        radius: Theme.cornerRadius
                        color: Theme.chipSurface
                        visible: labelItem.workspaceExists && labelItem.workspaceMonitorName !== ""

                        StyledText {
                            id: monitorNameText
                            anchors.centerIn: parent
                            text: labelItem.workspaceMonitorName
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Theme.fontWeightMedium
                            color: Theme.surfaceText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
