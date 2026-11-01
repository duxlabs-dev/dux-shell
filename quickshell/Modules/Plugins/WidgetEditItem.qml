import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var instanceData
    required property var screen
    required property var hostLayer
    property var lockHost: null
    property bool editMode: false

    readonly property string instanceId: instanceData?.id ?? ""
    readonly property string widgetType: instanceData?.widgetType ?? ""
    readonly property bool lockScreen: hostLayer.lockScreen
    readonly property bool removable: widgetType !== "lockAuth" && widgetType !== "greeterSession"
    readonly property bool selected: hostLayer.selectedInstanceId === instanceId
    readonly property bool interacting: editChrome.item?.interacting ?? false
    readonly property var contrastColors: content.item?.contrastColors ?? []
    readonly property real bottomOverflow: content.item?.bottomOverflow ?? 0
    readonly property bool hasSavedPosition: geometry.hasSavedPosition
    readonly property bool automaticPlacement: lockScreen && widgetType === "desktopClock" && (instanceData?.config?.autoPosition ?? true) && !hasSavedPosition
    readonly property bool dragging: editChrome.item?.dragging ?? false
    readonly property real chromeOutset: editChrome.item?.chromeOutset ?? 0
    readonly property var stock: hostLayer.stockRect(widgetType, root)
    // Stock-placed lock widgets grow around their stock anchor; everything else keeps its top-left corner.
    readonly property bool keepsCornerOnResize: !lockScreen || hasSavedPosition
    property bool snappedCenterX: false
    property bool snappedCenterY: false

    signal removeRequested
    signal optionsRequested

    readonly property bool loaded: content.item !== null
    onLoadedChanged: {
        if (loaded)
            Qt.callLater(() => hostLayer.placeIfPending(root));
    }

    x: geometry.widgetX
    y: geometry.widgetY
    width: geometry.widgetWidth
    height: geometry.widgetHeight
    activeFocusOnTab: editMode
    Accessible.name: instanceData?.name || I18n.tr("Widget", "fallback accessible name for an unnamed plugin widget")
    Accessible.role: Accessible.Button
    onActiveFocusChanged: {
        if (editMode && activeFocus)
            hostLayer.selectedInstanceId = instanceId;
    }
    Keys.onReturnPressed: {
        if (editMode)
            optionsRequested();
    }
    Keys.onSpacePressed: {
        if (editMode)
            optionsRequested();
    }

    function guideFor(value, guides) {
        const threshold = geometry.gridEnabled ? geometry.gridSize : Theme.spacingXL;
        let best;
        let bestDistance = threshold;
        for (const guide of guides) {
            const distance = Math.abs(value - guide);
            if (distance > bestDistance)
                continue;
            best = guide;
            bestDistance = distance;
        }
        return best;
    }

    function guidedPosition(startX, startY, dx, dy) {
        const rawX = Math.max(0, Math.min(startX + dx, geometry.screenWidth - width));
        const rawY = Math.max(0, Math.min(startY + dy, geometry.screenHeight - height));
        const snapped = geometry.dragMoveTo(startX, startY, dx, dy);
        const centerX = (hostLayer.width - width) / 2;
        const centerY = (hostLayer.height - height) / 2;
        const guidesX = [centerX, Theme.spacingXL, hostLayer.width - Theme.spacingXL - width];
        const guidesY = [centerY, Theme.spacingXL, hostLayer.height - Theme.spacingXL - height];
        if (stock) {
            guidesX.push(stock.x);
            guidesY.push(stock.y);
        }
        const guideX = guideFor(rawX, guidesX);
        const guideY = guideFor(rawY, guidesY);
        snappedCenterX = guideX === centerX;
        snappedCenterY = guideY === centerY;
        return Qt.point(guideX ?? snapped.x, guideY ?? snapped.y);
    }

    function pinPosition() {
        geometry.savePosition(geometry.widgetX, geometry.widgetY);
        SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
            autoPosition: false
        });
    }

    function commitPosition(finalX, finalY) {
        if (stock && finalX === stock.x && finalY === stock.y) {
            SessionData.resetDesktopWidgetInstanceGeometry(instanceId, ["x", "y"]);
            return;
        }
        geometry.savePosition(finalX, finalY);
        if (lockScreen && widgetType === "desktopClock" && (instanceData?.config?.autoPosition ?? true))
            SettingsData.updateDesktopWidgetInstanceConfig(instanceId, {
                autoPosition: false
            });
    }

    DesktopWidgetGeometry {
        id: geometry
        instanceId: root.instanceId
        instanceData: root.instanceData
        screen: root.screen
        lockScreen: root.lockScreen
        minWidth: content.contentMinWidth
        minHeight: content.contentMinHeight
        forceSquare: content.contentForceSquare
        defaultWidth: content.contentDefaultWidth
        defaultHeight: content.contentDefaultHeight
        defaultX: root.stock ? root.stock.x : screenWidth / 2 - savedWidth / 2
        defaultY: root.stock ? root.stock.y : screenHeight / 2 - savedHeight / 2
    }

    DesktopWidgetContent {
        id: content
        anchors.fill: parent
        active: root.visible
        focus: root.widgetType === "lockAuth"
        pluginId: root.widgetType
        instanceId: root.instanceId
        instanceData: root.instanceData
        screen: root.screen
        geometry: geometry
        lockScreen: root.lockScreen
        lockHost: root.lockHost
        persistDefaults: false
    }

    Loader {
        id: editChrome
        anchors.fill: parent
        active: root.editMode

        sourceComponent: Item {
            readonly property bool interacting: dragArea.pressed || chrome.resizing
            readonly property bool dragging: dragArea.pressed
            readonly property real chromeOutset: chrome.contentInset + Theme.spacingL

            TapHandler {
                acceptedButtons: Qt.RightButton
                gesturePolicy: TapHandler.WithinBounds
                onTapped: {
                    root.forceActiveFocus();
                    root.optionsRequested();
                }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property point startPos
                property real startX
                property real startY
                property bool moved: false

                onPressed: mouse => {
                    root.hostLayer.selectedInstanceId = root.instanceId;
                    root.forceActiveFocus();
                    moved = false;
                    startPos = mapToItem(root.parent, mouse.x, mouse.y);
                    startX = geometry.widgetX;
                    startY = geometry.widgetY;
                    geometry.dragOverrideX = startX;
                    geometry.dragOverrideY = startY;
                }

                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const current = mapToItem(root.parent, mouse.x, mouse.y);
                    if (!moved && Math.hypot(current.x - startPos.x, current.y - startPos.y) < Qt.styleHints.startDragDistance)
                        return;
                    moved = true;
                    const next = root.guidedPosition(startX, startY, current.x - startPos.x, current.y - startPos.y);
                    geometry.dragOverrideX = next.x;
                    geometry.dragOverrideY = next.y;
                }

                onReleased: {
                    const finalX = geometry.dragOverrideX;
                    const finalY = geometry.dragOverrideY;
                    geometry.clearDragOverrides();
                    root.snappedCenterX = false;
                    root.snappedCenterY = false;
                    if (moved)
                        root.commitPosition(finalX, finalY);
                }

                onCanceled: {
                    geometry.clearDragOverrides();
                    root.snappedCenterX = false;
                    root.snappedCenterY = false;
                }
            }

            DGridEditChrome {
                id: chrome

                property real startWidth
                property real startHeight
                property point startPos

                anchors.fill: parent
                anchors.margins: -parent.chromeOutset
                visible: root.selected
                cornerRadius: Theme.cornerRadius
                dragging: dragArea.pressed
                removable: root.removable
                hasOptions: true
                cornerResize: content.contentResizable
                sizeText: Math.round(root.width) + "×" + Math.round(root.height)
                snapped: geometry.squareSnapped
                onRemoveRequested: root.removeRequested()
                onOptionsRequested: root.optionsRequested()
                // The chrome moves with the widget, so pointer deltas are taken in the layer's frame.
                onResizeStarted: (px, py) => {
                    startPos = chrome.mapToItem(root.hostLayer, px, py);
                    startWidth = geometry.widgetWidth;
                    startHeight = geometry.widgetHeight;
                    geometry.dragOverrideW = startWidth;
                    geometry.dragOverrideH = startHeight;
                    if (root.keepsCornerOnResize) {
                        geometry.dragOverrideX = geometry.widgetX;
                        geometry.dragOverrideY = geometry.widgetY;
                    }
                    resizing = true;
                }
                onResizeMoved: (px, py, modifiers) => {
                    const current = chrome.mapToItem(root.hostLayer, px, py);
                    const next = geometry.dragResizeTo(startWidth, startHeight, current.x - startPos.x, current.y - startPos.y, !!(modifiers & Qt.ShiftModifier));
                    geometry.dragOverrideW = next.width;
                    geometry.dragOverrideH = next.height;
                }
                onResizeEnded: {
                    geometry.saveSize(geometry.dragOverrideW, geometry.dragOverrideH);
                    if (root.automaticPlacement)
                        root.pinPosition();
                    else if (root.keepsCornerOnResize)
                        geometry.savePosition(geometry.widgetX, geometry.widgetY);
                    resizing = false;
                    geometry.clearDragOverrides();
                }
                onResizeCanceled: {
                    resizing = false;
                    geometry.clearDragOverrides();
                }
            }
        }
    }
}
