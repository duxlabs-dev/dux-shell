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

    readonly property alias confirmationOpen: confirmation.visible

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

    readonly property var menuItems: [
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
            text: I18n.tr("Kill Process"),
            icon: "close",
            action: killProcess,
            enabled: true,
            dangerous: true
        },
        {
            text: I18n.tr("Force Kill (SIGKILL)"),
            icon: "dangerous",
            action: forceKillProcess,
            enabled: processData && processData.pid > 1000,
            dangerous: true
        }
    ]

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
            Quickshell.execDetached(["dms", "cl", "copy", processData.pid.toString()]);
        close();
    }

    function copyName() {
        if (processData) {
            const name = processData.command || "";
            Quickshell.execDetached(["dms", "cl", "copy", name]);
        }
        close();
    }

    function copyFullCommand() {
        if (processData) {
            const fullCmd = processData.fullCommand || processData.command || "";
            Quickshell.execDetached(["dms", "cl", "copy", fullCmd]);
        }
        close();
    }

    function killProcess() {
        requestKill(false);
    }

    function forceKillProcess() {
        requestKill(true);
    }

    function requestKill(force) {
        if (!processData || processData.pid <= 0 || (force && processData.pid <= 1000))
            return;
        confirmation.process = Object.assign({}, processData);
        confirmation.forceKill = force;
        close();
        confirmation.open();
    }

    function dismiss() {
        close();
        confirmation.close();
    }

    Popup {
        id: confirmation
        property var process: null
        property bool forceKill: false
        parent: processContextMenu.parent
        width: Math.min(ProcessListMetrics.dialogWidth, parent.width - Theme.spacingL * 2)
        height: confirmationContent.implicitHeight + Theme.spacingL * 2
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        padding: Theme.spacingL
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            confirmationContent.reset();
            confirmationContent.selectedButton = 0;
            confirmationContent.keyboardNavigation = true;
            confirmationContent.forceActiveFocus();
        }
        onClosed: focusRestore.restart()

        background: Rectangle {
            color: Theme.isFloatingWindow(processContextMenu) ? Theme.floatingWindowSurface : Theme.readableSurface
            border.width: Theme.layerOutlineWidth
            border.color: Theme.outlineMedium
            radius: Theme.windowRadius
        }

        contentItem: ConfirmDialogContent {
            id: confirmationContent
            confirmTitle: confirmation.forceKill ? I18n.tr("Force Kill (SIGKILL)") : I18n.tr("Kill Process")
            confirmMessage: (confirmation.process?.command ?? "") + " (" + I18n.tr("PID %1", "%1 is a process id").arg(confirmation.process?.pid ?? 0) + ")"
            confirmButtonText: I18n.tr("Kill Process")
            confirmButtonColor: Theme.error
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Backtab) {
                    keyboardNavigation = true;
                    selectedButton = selectedButton === 0 ? 1 : 0;
                    event.accepted = true;
                    return;
                }
                handleKey(event);
            }
            onCancelled: confirmation.close()
            onButtonActivated: button => {
                const pid = confirmation.process?.pid ?? 0;
                const force = confirmation.forceKill;
                confirmation.close();
                if (button !== 1 || pid <= 0)
                    return;
                const args = force ? ["kill", "-9", pid.toString()] : ["kill", pid.toString()];
                Quickshell.execDetached(args);
                processContextMenu.processKilled();
            }
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
    height: menuColumn.implicitHeight + ProcessListMetrics.menuPadding * 2
    padding: 0
    modal: false
    closePolicy: Popup.CloseOnEscape

    onClosed: {
        closePolicy = Popup.CloseOnEscape;
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

    contentItem: Rectangle {
        color: Theme.foregroundColor(Theme.chipSurfaceNested, Theme.isFloatingWindow(processContextMenu))
        radius: Theme.windowRadius
        border.color: Theme.outlineMedium
        border.width: Theme.layerOutlineWidth

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
                case Qt.Key_Escape:
                case Qt.Key_Left:
                case Qt.Key_H:
                    close();
                    event.accepted = true;
                    return;
                }
            }
        }

        Column {
            id: menuColumn
            anchors.fill: parent
            anchors.margins: ProcessListMetrics.menuPadding
            spacing: Theme.groupedListGap

            Repeater {
                model: menuItems

                Item {
                    width: parent.width
                    height: modelData.type === "separator" ? Theme.spacingS : ProcessListMetrics.menuRowHeight
                    visible: modelData.type !== "separator" || index > 0

                    property int itemVisibleIndex: {
                        let count = 0;
                        for (let i = 0; i < index; i++) {
                            if (menuItems[i].type !== "separator")
                                count++;
                        }
                        return count;
                    }

                    Rectangle {
                        visible: modelData.type === "separator"
                        width: parent.width - Theme.spacingS * 2
                        height: Theme.dividerWidth
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.outlineStrong
                    }

                    Rectangle {
                        id: menuItem
                        visible: modelData.type !== "separator"
                        width: parent.width
                        height: ProcessListMetrics.menuRowHeight
                        radius: Theme.cornerRadiusM
                        color: {
                            if (!modelData.enabled)
                                return "transparent";
                            const isSelected = keyboardNavigation && selectedIndex === index;
                            if (modelData.dangerous) {
                                if (isSelected)
                                    return Theme.errorPressed;
                                return menuItemArea.containsMouse ? Theme.errorHover : Theme.withAlpha(Theme.errorHover, 0);
                            }
                            if (isSelected)
                                return Theme.primaryPressed;
                            return menuItemArea.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : Theme.withAlpha(BlurService.hoverColor(Theme.widgetBaseHoverColor), 0);
                        }

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DIcon {
                                name: modelData.icon || ""
                                size: Theme.iconSizeSmall
                                color: {
                                    if (!modelData.enabled)
                                        return Theme.onSurface_38;
                                    const isSelected = keyboardNavigation && selectedIndex === index;
                                    if (modelData.dangerous && (menuItemArea.containsMouse || isSelected))
                                        return Theme.error;
                                    return Theme.surfaceText;
                                }
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: modelData.text || ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Theme.fontWeight
                                color: {
                                    if (!modelData.enabled)
                                        return Theme.onSurface_38;
                                    const isSelected = keyboardNavigation && selectedIndex === index;
                                    if (modelData.dangerous && (menuItemArea.containsMouse || isSelected))
                                        return Theme.error;
                                    return Theme.surfaceText;
                                }
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - Theme.iconSizeSmall - Theme.spacingS
                            }
                        }

                        DRipple {
                            id: menuItemRipple
                            rippleColor: modelData.dangerous ? Theme.error : Theme.surfaceText
                            cornerRadius: menuItem.radius
                        }

                        MouseArea {
                            id: menuItemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: modelData.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: modelData.enabled ?? false
                            onEntered: {
                                keyboardNavigation = false;
                                selectedIndex = index;
                            }
                            onPressed: mouse => menuItemRipple.trigger(mouse.x, mouse.y)
                            onClicked: modelData.action()
                        }
                    }
                }
            }
        }
    }
}
