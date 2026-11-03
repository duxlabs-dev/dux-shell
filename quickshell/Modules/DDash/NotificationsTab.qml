import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Notifications
import qs.Modules.Notifications.Center
import "../Notifications/NotificationShortcuts.js" as Shortcuts

FocusScope {
    id: root

    property bool live: false
    property bool interactive: true
    property bool nested: false
    property string entryId: "notifications"
    property int currentTab: 0
    property var transientSurfaceTracker: null
    property real swipeBleed: 0
    property bool sizeToContent: false
    property bool settingsAction: false
    readonly property var surfaces: transientSurfaceTracker ?? localSurfaces
    readonly property bool hasNotifications: list.count > 0
    readonly property Item focusTarget: root
    readonly property bool showKeyboardHints: currentTab === 1 ? (historyLoader.item?.showKeyboardHints ?? false) : keyboard.showKeyboardHints
    readonly property real contentHeight: {
        let listHeight = NotificationMetrics.emptyHeight;
        if (currentTab === 0) {
            if (NotificationService.groupedNotifications.length > 0)
                listHeight = live && list.stableContentHeight > 0 ? list.stableContentHeight : list.listContentHeight;
        } else if (NotificationService.historyList.length > 0) {
            listHeight = Math.max(NotificationMetrics.emptyHeight, NotificationService.historyList.length * NotificationMetrics.estimatedCardHeight);
        }
        return listHeight + footer.height + Theme.spacingM;
    }
    readonly property bool blocksTabNavigation: shortcutSheet.opened
    activeFocusOnTab: interactive

    signal settingsRequested

    function forceLayout() {
        list.forceLayout();
    }

    function slotAction(action) {
        return Shortcuts.isAvailable(action, SettingsData.notificationHistoryEnabled) ? action : "";
    }

    function triggerShortcut(slot) {
        switch (slot.shortcut) {
        case "dnd":
            duration.popupAnchorItem = slot;
            duration.showDropdownMenu();
            return;
        case "history":
            currentTab = currentTab === 0 ? 1 : 0;
            return;
        case "hints":
            if (currentTab === 1) {
                if (historyLoader.item)
                    historyLoader.item.showKeyboardHints = !historyLoader.item.showKeyboardHints;
                return;
            }
            keyboard.showKeyboardHints = !keyboard.showKeyboardHints;
            return;
        case "settings":
            if (settingsAction) {
                settingsRequested();
                return;
            }
            PopoutService.openSettingsWithTab("notifications");
            return;
        }
        editShortcut(slot, slot.visualFocus);
    }

    function editShortcut(slot, keyboardOpened) {
        const other = slot === leadingSlot ? trailingSlot : leadingSlot;
        const choices = Shortcuts.choices(slot.shortcut, other.shortcut, SettingsData.notificationHistoryEnabled);
        shortcutSheet.open(slot, choices, !slot.empty, slot === trailingSlot, keyboardOpened);
    }

    function assignShortcut(action) {
        const slot = shortcutSheet.slot;
        shortcutSheet.close();
        if (slot)
            SettingsData.set(slot.settingKey, action === "remove" ? "" : action);
        if (leadingSlot.shortcut !== "history" && trailingSlot.shortcut !== "history")
            currentTab = 0;
    }

    function handleKeyEvent(event) {
        event.accepted = false;
        if (shortcutSheet.opened)
            return shortcutSheet.handleKeyEvent(event);
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
            shortcutSheet.close();
            return;
        }
        NotificationService.markNotificationsSeen();
        keyboard.rebuildFlatNavigation();
    }

    onVisibleChanged: {
        if (!visible)
            shortcutSheet.close();
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
        enabled: !shortcutSheet.opened
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
        trackStableContentHeight: root.sizeToContent
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

        NotificationShortcutSlot {
            id: leadingSlot
            settingKey: "notificationLeadingShortcut"
            shortcut: root.slotAction(SettingsData.notificationLeadingShortcut)
            live: root.live
            squeezed: clearButton.pressed
            historyActive: root.currentTab === 1
            hintsActive: root.showKeyboardHints
            restColor: Theme.foregroundColor(root.nested ? Theme.chipSurface : Theme.cardSurface, Theme.isFloatingWindow(root))
            onClicked: root.triggerShortcut(leadingSlot)
            onEditRequested: root.editShortcut(leadingSlot, leadingSlot.visualFocus)
        }

        DButton {
            id: clearButton
            width: Math.max(0, footer.width - leadingSlot.width - trailingSlot.width - footer.spacing * 2)
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

        NotificationShortcutSlot {
            id: trailingSlot
            settingKey: "notificationTrailingShortcut"
            shortcut: root.slotAction(SettingsData.notificationTrailingShortcut)
            live: root.live
            squeezed: clearButton.pressed
            historyActive: root.currentTab === 1
            hintsActive: root.showKeyboardHints
            restColor: Theme.foregroundColor(root.nested ? Theme.chipSurface : Theme.cardSurface, Theme.isFloatingWindow(root))
            onClicked: root.triggerShortcut(trailingSlot)
            onEditRequested: root.editShortcut(trailingSlot, trailingSlot.visualFocus)
        }
    }

    NotificationKeyboardHints {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Theme.spacingM
        showHints: root.showKeyboardHints
        historyTab: root.currentTab === 1
    }

    NotificationShortcutSheet {
        id: shortcutSheet
        anchors.fill: parent
        bottomInset: footer.height + Theme.spacingS
        onChosen: action => root.assignShortcut(action)
    }

    DDropdown {
        id: duration
        showTrigger: false
        popupAnchorItem: leadingSlot
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
