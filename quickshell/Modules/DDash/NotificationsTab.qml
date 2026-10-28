import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Notifications
import qs.Modules.Notifications.Center

FocusScope {
    id: root

    property bool live: false
    property bool interactive: true
    property bool nested: false
    property string entryId: "notifications"
    property int currentTab: 0
    property var transientSurfaceTracker: null
    property real swipeBleed: 0
    readonly property var surfaces: transientSurfaceTracker ?? localSurfaces
    readonly property bool hasNotifications: list.count > 0
    readonly property Item focusTarget: root
    property bool blocksTabNavigation: false
    activeFocusOnTab: interactive

    function handleKeyEvent(event) {
        event.accepted = false;
        if (!interactive || !enabled || !activeFocus)
            return false;
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return focusNextControl(event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier));
        if (event.key === Qt.Key_Escape) {
            if (surfaces.active) {
                surfaces.closeAll();
                return true;
            }
            keyboard.reset();
            if (historyLoader.item)
                historyLoader.item.keyboardActive = false;
            return false;
        }
        if (currentTab === 1) {
            historyLoader.item?.handleKey(event);
            return event.accepted;
        }
        keyboard.handleKey(event);
        return event.accepted;
    }

    function focusNextControl(backwards) {
        const current = root.Window.window?.activeFocusItem ?? root;
        let next = current.nextItemInFocusChain(!backwards);
        while (next && next !== current) {
            let ancestor = next;
            while (ancestor && ancestor !== root)
                ancestor = ancestor.parent;
            if (!ancestor)
                return false;
            if (next.activeFocusOnTab && next.visible && next.enabled) {
                revealControl(next);
                next.forceActiveFocus(backwards ? Qt.BacktabFocusReason : Qt.TabFocusReason);
                return true;
            }
            next = next.nextItemInFocusChain(!backwards);
        }
        return false;
    }

    function revealControl(item) {
        let ancestor = item.parent;
        while (ancestor && ancestor !== root) {
            if (ancestor.contentItem && ancestor.contentY !== undefined && ancestor.contentHeight !== undefined)
                revealInViewport(item, ancestor);
            ancestor = ancestor.parent;
        }
    }

    function revealInViewport(item, viewport) {
        const point = item.mapToItem(viewport.contentItem, 0, 0);
        if (typeof viewport.revealRange === "function") {
            viewport.revealRange(point.y, point.y + item.height);
            return;
        }
        if (point.y < viewport.contentY) {
            viewport.contentY = Math.max(0, point.y);
            return;
        }
        const bottom = point.y + item.height - viewport.height;
        if (bottom > viewport.contentY)
            viewport.contentY = Math.max(0, Math.min(point.y, bottom));
    }

    implicitHeight: DashMetrics.tabMinHeight
    enabled: interactive
    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    Ref {
        service: NotificationService
        active: root.live
    }

    onLiveChanged: {
        if (!live) {
            keyboard.reset();
            surfaces.closeAll();
            return;
        }
        NotificationService.markNotificationsSeen();
        keyboard.rebuildFlatNavigation();
    }

    readonly property bool settingsNotificationHistoryEnabled: SettingsData.notificationHistoryEnabled

    onSettingsNotificationHistoryEnabledChanged: {
        if (!settingsNotificationHistoryEnabled)
            currentTab = 0;
    }

    TransientSurfaceTracker {
        id: localSurfaces
    }

    NotificationKeyboardController {
        id: keyboard
        listView: list
        isOpen: root.live
    }

    Keys.onPressed: event => event.accepted = handleKeyEvent(event)

    TapHandler {
        onPressedChanged: {
            if (pressed)
                root.forceActiveFocus(Qt.MouseFocusReason);
        }
    }

    KeyboardNavigatedNotificationList {
        id: list
        anchors.fill: parent
        anchors.leftMargin: -root.swipeBleed
        anchors.rightMargin: -root.swipeBleed
        nested: root.nested
        anchors.bottomMargin: footer.height + Theme.spacingM
        swipeBleed: root.swipeBleed
        visible: root.currentTab === 0
        showScrollBar: false
        keyboardController: keyboard
        focusAllowed: root.activeFocus
        transientSurfaceTracker: root.surfaces
        trackStableContentHeight: false
    }

    Loader {
        id: historyLoader
        anchors.fill: parent
        anchors.bottomMargin: footer.height + Theme.spacingM
        active: root.currentTab === 1
        visible: active
        sourceComponent: HistoryNotificationList {
            focusAllowed: root.activeFocus
            showScrollBar: false
            nested: root.nested
            swipeBleed: root.swipeBleed
        }
    }

    Row {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Theme.spacingS
        height: Theme.iconButtonSize

        DActionButton {
            id: historyButton
            visible: SettingsData.notificationHistoryEnabled
            buttonSize: Theme.iconButtonSize
            iconName: root.currentTab === 1 ? "inbox" : "history"
            backgroundColor: Theme.secondaryContainer
            iconColor: Theme.onSecondaryContainer
            tooltipText: root.currentTab === 1 ? I18n.tr("Current", "notification center tab") : I18n.tr("History", "notification center tab")
            onClicked: root.currentTab = root.currentTab === 0 ? 1 : 0
        }

        DButton {
            width: Math.max(0, footer.width - dndButton.width - (historyButton.visible ? historyButton.width + footer.spacing : 0) - footer.spacing)
            text: I18n.tr("Clear All")
            buttonHeight: Theme.iconButtonSize
            backgroundColor: Theme.secondaryContainer
            textColor: Theme.onSecondaryContainer
            enabled: root.currentTab === 0 ? NotificationService.notifications.length > 0 : NotificationService.historyList.length > 0
            onClicked: {
                if (root.currentTab === 0) {
                    NotificationService.clearAllNotifications();
                    return;
                }
                NotificationService.clearHistory();
            }
        }

        DActionButton {
            id: dndButton
            buttonSize: Theme.iconButtonSize
            iconName: SessionData.doNotDisturb ? "notifications_off" : "notifications"
            backgroundColor: SessionData.doNotDisturb ? Theme.primaryContainer : Theme.secondaryContainer
            iconColor: SessionData.doNotDisturb ? Theme.onPrimaryContainer : Theme.onSecondaryContainer
            tooltipText: I18n.tr("Do not disturb")
            onClicked: duration.showDropdownMenu()
        }
    }

    DDropdown {
        id: duration
        showTrigger: false
        popupAnchorItem: dndButton
        popupWidth: NotificationMetrics.menuWidth
        openUpwards: true
        transientSurfaceTracker: root.surfaces
        options: [I18n.tr("Off")].concat(DndPresets.presetOptions.map(option => option.label))
        onValueChanged: value => {
            if (value === I18n.tr("Off")) {
                SessionData.setDoNotDisturb(false);
                return;
            }
            const option = DndPresets.presetOptions.find(option => option.label === value);
            if (option)
                DndPresets.selectPreset(option);
        }
    }
}
