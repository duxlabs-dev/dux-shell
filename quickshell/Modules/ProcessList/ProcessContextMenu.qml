import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modals.Common

Popup {
    id: processContextMenu

    property var processData: null
    property int selectedIndex: -1
    property bool keyboardNavigation: false
    property var parentFocusItem: null
    property var transientSurfaceTracker: null

    readonly property bool confirmationOpen: confirmation.opened

    signal menuClosed
    signal processKilled

    onVisibleChanged: transientSurfaceTracker?.setActive(processContextMenu, visible || confirmationOpen, null)
    onConfirmationOpenChanged: transientSurfaceTracker?.setActive(processContextMenu, visible || confirmationOpen, null)
    Component.onDestruction: transientSurfaceTracker?.unregister(processContextMenu)

    Connections {
        target: processContextMenu.transientSurfaceTracker
        ignoreUnknownSignals: true

        function onCloseRequested() {
            processContextMenu.dismiss();
        }
    }

    property bool inSubmenu: false
    readonly property string endTitle: ProcessActions.restartKind(processData) === "reload" ? I18n.tr("Quit or reload", "process menu: opens the quit, force quit, end tree and reload actions") : I18n.tr("Quit or restart", "process menu: opens the quit, force quit, end tree and restart actions")

    readonly property var mainItems: [
        {
            text: I18n.tr("Copy PID"),
            icon: "tag",
            action: copyPid,
            enabled: true
        },
        {
            text: I18n.tr("Copy Name"),
            icon: "content_copy",
            action: copyName,
            enabled: true
        },
        {
            text: I18n.tr("Copy Full Command"),
            icon: "code",
            action: copyFullCommand,
            enabled: true
        },
        {
            type: "separator"
        },
        {
            text: endTitle,
            icon: "power_settings_new",
            action: () => Qt.callLater(setSubmenu, true),
            enabled: ProcessActions.canEnd(processData) || ProcessActions.canRestart(processData),
            submenu: true
        }
    ]

    readonly property var endItems: [
        {
            text: I18n.tr("Back"),
            icon: "arrow_back",
            action: () => Qt.callLater(setSubmenu, false),
            enabled: true
        },
        {
            type: "separator"
        },
        {
            text: I18n.tr("Quit", "process action: ask the process to exit (SIGTERM)"),
            icon: "close",
            action: () => requestAction("quit"),
            enabled: ProcessActions.canEnd(processData),
            dangerous: true
        },
        {
            text: I18n.tr("Force quit", "process action: kill the process immediately (SIGKILL)"),
            icon: "dangerous",
            action: () => requestAction("force"),
            enabled: ProcessActions.canEnd(processData),
            dangerous: true
        },
        {
            text: I18n.tr("End process tree", "process action: quit the process and every process it started"),
            icon: "account_tree",
            action: () => requestAction("tree"),
            enabled: ProcessActions.canEnd(processData),
            dangerous: true
        },
        {
            text: ProcessActions.title("restart", processData),
            icon: "restart_alt",
            action: () => requestAction("restart"),
            enabled: ProcessActions.canRestart(processData)
        }
    ]

    readonly property var menuItems: inSubmenu ? endItems : mainItems

    function setSubmenu(on) {
        inSubmenu = on;
        selectedIndex = keyboardNavigation ? (on ? 2 : menuItems.length - 1) : -1;
    }

    // The end actions list is taller than the main one; keep it inside the parent.
    onHeightChanged: {
        if (visible && parent)
            y = Math.max(0, Math.min(y, parent.height - height));
    }

    readonly property int visibleItemCount: {
        let count = 0;
        for (let i = 0; i < menuItems.length; i++) {
            if (menuItems[i].type !== "separator")
                count++;
        }
        return count;
    }

    function show(x, y, fromKeyboard) {
        let finalX = x;
        let finalY = y;

        if (processContextMenu.parent) {
            const parentWidth = processContextMenu.parent.width;
            const parentHeight = processContextMenu.parent.height;
            const menuWidth = processContextMenu.width;
            const menuHeight = processContextMenu.height;

            if (finalX + menuWidth > parentWidth)
                finalX = Math.max(0, parentWidth - menuWidth);
            if (finalY + menuHeight > parentHeight)
                finalY = Math.max(0, parentHeight - menuHeight);
        }

        processContextMenu.x = finalX;
        processContextMenu.y = finalY;
        inSubmenu = false;
        keyboardNavigation = fromKeyboard || false;
        selectedIndex = fromKeyboard ? 0 : -1;
        open();
    }

    function selectNext() {
        if (visibleItemCount === 0)
            return;
        let current = selectedIndex;
        let next = current;
        do {
            next = (next + 1) % menuItems.length;
        } while (menuItems[next].type === "separator" && next !== current)
        selectedIndex = next;
    }

    function selectPrevious() {
        if (visibleItemCount === 0)
            return;
        let current = selectedIndex;
        let prev = current;
        do {
            prev = (prev - 1 + menuItems.length) % menuItems.length;
        } while (menuItems[prev].type === "separator" && prev !== current)
        selectedIndex = prev;
    }

    function activateSelected() {
        if (selectedIndex < 0 || selectedIndex >= menuItems.length)
            return;
        const item = menuItems[selectedIndex];
        if (item.type === "separator" || !item.enabled)
            return;
        item.action();
    }

    function copyPid() {
        if (processData)
            Quickshell.execDetached(["dms", "cl", "copy", "--", processData.pid.toString()]);
        close();
    }

    function copyName() {
        if (processData) {
            const name = processData.command || "";
            Quickshell.execDetached(["dms", "cl", "copy", "--", name]);
        }
        close();
    }

    function copyFullCommand() {
        if (processData) {
            const fullCmd = processData.fullCommand || processData.command || "";
            Quickshell.execDetached(["dms", "cl", "copy", "--", fullCmd]);
        }
        close();
    }

    function requestAction(action) {
        if (!processData || !(action === "restart" ? ProcessActions.canRestart(processData) : ProcessActions.canEnd(processData)))
            return;
        const process = Object.assign({}, processData);
        close();
        confirmation.open(process, action, action !== "restart" && ProcessActions.isCritical(process));
    }

    function dismiss() {
        close();
        confirmation.close();
    }

    ProcessActionDialog {
        id: confirmation
        parent: processContextMenu.parent
        onChosen: (action, process) => {
            if ((process?.pid ?? 0) <= 0)
                return;
            ProcessActions.run(action, process);
            processContextMenu.processKilled();
        }
        onOpenedChanged: {
            if (!opened)
                focusRestore.restart();
        }
    }

    DeferredAction {
        id: focusRestore
        onTriggered: {
            if (!processContextMenu.confirmationOpen && processContextMenu.parentFocusItem?.visible)
                processContextMenu.parentFocusItem.forceActiveFocus();
        }
    }

    width: ProcessListMetrics.menuWidth
    height: menuColumn.implicitHeight
    padding: 0
    // Modal so the click that closes the menu doesn't also act on the row under it.
    modal: true
    dim: false
    closePolicy: Popup.CloseOnEscape

    onClosed: {
        closePolicy = Popup.CloseOnEscape;
        inSubmenu = false;
        keyboardNavigation = false;
        selectedIndex = -1;
        menuClosed();
        focusRestore.restart();
    }

    onOpened: {
        outsideClickTimer.start();
        if (keyboardNavigation)
            Qt.callLater(() => keyboardHandler.forceActiveFocus());
    }

    Timer {
        id: outsideClickTimer
        interval: 100
        onTriggered: processContextMenu.closePolicy = Popup.CloseOnEscape | Popup.CloseOnPressOutside
    }

    background: Rectangle {
        color: "transparent"
    }

    // Groups split at separators; each is its own card, so the end actions stand apart from the copy actions.
    readonly property var groups: {
        const out = [[]];
        menuItems.forEach((entry, index) => {
            if (entry.type === "separator")
                out.push([]);
            else
                out[out.length - 1].push({
                    "entry": entry,
                    "index": index
                });
        });
        return out.filter(g => g.length > 0);
    }

    contentItem: Item {
        Item {
            id: keyboardHandler
            anchors.fill: parent
            focus: keyboardNavigation

            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Down:
                case Qt.Key_J:
                    keyboardNavigation = true;
                    selectNext();
                    event.accepted = true;
                    return;
                case Qt.Key_Up:
                case Qt.Key_K:
                    keyboardNavigation = true;
                    selectPrevious();
                    event.accepted = true;
                    return;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    activateSelected();
                    event.accepted = true;
                    return;
                case Qt.Key_Right:
                case Qt.Key_L:
                    if (menuItems[selectedIndex]?.submenu && menuItems[selectedIndex].enabled)
                        setSubmenu(true);
                    event.accepted = true;
                    return;
                case Qt.Key_Escape:
                case Qt.Key_Left:
                case Qt.Key_H:
                    if (inSubmenu)
                        setSubmenu(false);
                    else
                        close();
                    event.accepted = true;
                    return;
                }
            }
        }

        Column {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Theme.spacingXS

            Repeater {
                model: processContextMenu.groups

                Rectangle {
                    id: groupCard
                    required property var modelData
                    width: menuColumn.width
                    height: groupColumn.implicitHeight + ProcessListMetrics.menuPadding * 2
                    color: Theme.foregroundColor(Theme.chipSurfaceNested, Theme.isFloatingWindow(processContextMenu))
                    radius: Theme.windowRadius
                    border.color: Theme.outlineMedium
                    border.width: Theme.layerOutlineWidth

                    Column {
                        id: groupColumn
                        anchors.fill: parent
                        anchors.margins: ProcessListMetrics.menuPadding
                        spacing: Theme.groupedListGap

                        Repeater {
                            model: groupCard.modelData

                            Item {
                                id: row
                                required property var modelData
                                readonly property var entry: modelData.entry
                                readonly property int itemIndex: modelData.index
                                width: groupColumn.width
                                height: ProcessListMetrics.menuRowHeight

                                Rectangle {
                                    id: menuItem
                                    width: parent.width
                                    height: ProcessListMetrics.menuRowHeight
                                    radius: Theme.cornerRadiusM
                                    color: {
                                        if (!row.entry.enabled)
                                            return "transparent";
                                        const isSelected = keyboardNavigation && selectedIndex === row.itemIndex;
                                        if (row.entry.dangerous) {
                                            if (isSelected)
                                                return Theme.errorPressed;
                                            return menuItemArea.containsMouse ? Theme.errorHover : Theme.withAlpha(Theme.errorHover, 0);
                                        }
                                        if (isSelected)
                                            return Theme.selectedContainer;
                                        return menuItemArea.pressed ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerPressed) : menuItemArea.containsMouse ? Theme.withAlpha(Theme.onSurface, Theme.stateLayerHover) : "transparent";
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Theme.spacingS
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.spacingS
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.spacingS

                                        DIcon {
                                            name: row.entry.icon || ""
                                            size: Theme.iconSizeSmall
                                            color: {
                                                if (!row.entry.enabled)
                                                    return Theme.onSurface_38;
                                                const isSelected = keyboardNavigation && selectedIndex === row.itemIndex;
                                                if (row.entry.dangerous && (menuItemArea.containsMouse || isSelected))
                                                    return Theme.error;
                                                return Theme.surfaceText;
                                            }
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: row.entry.text || ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.weight: Theme.fontWeight
                                            color: {
                                                if (!row.entry.enabled)
                                                    return Theme.onSurface_38;
                                                const isSelected = keyboardNavigation && selectedIndex === row.itemIndex;
                                                if (row.entry.dangerous && (menuItemArea.containsMouse || isSelected))
                                                    return Theme.error;
                                                return Theme.surfaceText;
                                            }
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            width: parent.width - Theme.iconSizeSmall * (row.entry.submenu ? 2 : 1) - Theme.spacingS * (row.entry.submenu ? 2 : 1)
                                        }

                                        DIcon {
                                            visible: row.entry.submenu ?? false
                                            name: "chevron_right"
                                            size: Theme.iconSizeSmall - 2
                                            color: row.entry.enabled ? Theme.surfaceText : Theme.onSurface_38
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    DRipple {
                                        id: menuItemRipple
                                        rippleColor: row.entry.dangerous ? Theme.error : Theme.surfaceText
                                        cornerRadius: menuItem.radius
                                    }

                                    MouseArea {
                                        id: menuItemArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: row.entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        enabled: row.entry.enabled ?? false
                                        onEntered: {
                                            keyboardNavigation = false;
                                            selectedIndex = row.itemIndex;
                                        }
                                        onPressed: mouse => menuItemRipple.trigger(mouse.x, mouse.y)
                                        onClicked: row.entry.action()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
