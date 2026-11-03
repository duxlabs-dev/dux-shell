import QtQuick
import qs.Services
import qs.Modules.Notifications

QtObject {
    id: controller

    property var listView: null
    property bool isOpen: false
    property var onClose: null

    property int selectionVersion: 0

    property bool keyboardNavigationActive: false
    property int selectedFlatIndex: 0
    property var flatNavigation: []
    property bool showKeyboardHints: false

    property string selectedNotificationId: ""
    property string selectedGroupKey: ""
    property string selectedItemType: ""
    property bool isTogglingGroup: false
    property bool isRebuilding: false

    function rebuildFlatNavigation() {
        isRebuilding = true;

        const nav = [];
        const groups = NotificationService.groupedNotifications;

        for (var i = 0; i < groups.length; i++) {
            const group = groups[i];
            const isExpanded = NotificationService.expandedGroups[group.key] || false;

            nav.push({
                "type": "group",
                "groupIndex": i,
                "notificationIndex": -1,
                "groupKey": group.key,
                "notificationId": ""
            });

            if (isExpanded) {
                const notifications = group.notifications || [];
                const maxNotifications = Math.min(notifications.length, NotificationMetrics.expandedLimit);
                for (var j = 0; j < maxNotifications; j++) {
                    const notifId = String(notifications[j] && notifications[j].notification && notifications[j].notification.id ? notifications[j].notification.id : "");
                    nav.push({
                        "type": "notification",
                        "groupIndex": i,
                        "notificationIndex": j,
                        "groupKey": group.key,
                        "notificationId": notifId
                    });
                }
            }
        }

        flatNavigation = nav;
        updateSelectedIndexFromId();
        isRebuilding = false;
    }

    function updateSelectedIndexFromId() {
        if (!keyboardNavigationActive) {
            return;
        }

        for (var i = 0; i < flatNavigation.length; i++) {
            const item = flatNavigation[i];

            if (selectedItemType === "group" && item.type === "group" && item.groupKey === selectedGroupKey) {
                selectedFlatIndex = i;
                selectionVersion++;
                return;
            } else if (selectedItemType === "notification" && item.type === "notification" && String(item.notificationId) === String(selectedNotificationId)) {
                selectedFlatIndex = i;
                selectionVersion++;
                return;
            }
        }
        if (selectedItemType === "notification") {
            for (var j = 0; j < flatNavigation.length; j++) {
                const groupItem = flatNavigation[j];
                if (groupItem.type === "group" && groupItem.groupKey === selectedGroupKey) {
                    selectedFlatIndex = j;
                    selectedItemType = "group";
                    selectedNotificationId = "";
                    selectionVersion++;
                    return;
                }
            }
        }
        if (flatNavigation.length > 0) {
            selectedFlatIndex = Math.min(selectedFlatIndex, flatNavigation.length - 1);
            selectedFlatIndex = Math.max(selectedFlatIndex, 0);
            updateSelectedIdFromIndex();
            selectionVersion++;
        }
    }

    function updateSelectedIdFromIndex() {
        if (selectedFlatIndex >= 0 && selectedFlatIndex < flatNavigation.length) {
            const item = flatNavigation[selectedFlatIndex];
            selectedItemType = item.type;
            selectedGroupKey = item.groupKey;
            selectedNotificationId = item.notificationId;
        }
    }

    function reset() {
        selectedFlatIndex = 0;
        keyboardNavigationActive = false;
        showKeyboardHints = false;
        if (listView) {
            listView.keyboardActive = false;
        }
        rebuildFlatNavigation();
    }

    function selectNext() {
        keyboardNavigationActive = true;
        if (flatNavigation.length === 0)
            return;
        if (listView && listView.enableAutoScroll) {
            listView.enableAutoScroll();
        }

        selectedFlatIndex = Math.min(selectedFlatIndex + 1, flatNavigation.length - 1);
        updateSelectedIdFromIndex();
        selectionVersion++;
        ensureVisible();
    }

    function selectNextWrapping() {
        keyboardNavigationActive = true;
        if (flatNavigation.length === 0)
            return;
        if (listView && listView.enableAutoScroll) {
            listView.enableAutoScroll();
        }

        selectedFlatIndex = (selectedFlatIndex + 1) % flatNavigation.length;
        updateSelectedIdFromIndex();
        selectionVersion++;
        ensureVisible();
    }

    function selectPrevious() {
        keyboardNavigationActive = true;
        if (flatNavigation.length === 0)
            return;
        if (listView && listView.enableAutoScroll) {
            listView.enableAutoScroll();
        }

        selectedFlatIndex = Math.max(selectedFlatIndex - 1, 0);
        updateSelectedIdFromIndex();
        selectionVersion++;
        ensureVisible();
    }

    function toggleGroupExpanded() {
        if (flatNavigation.length === 0 || selectedFlatIndex >= flatNavigation.length)
            return;
        const currentItem = flatNavigation[selectedFlatIndex];
        const groups = NotificationService.groupedNotifications;
        const group = groups[currentItem.groupIndex];
        if (!group)
            return;
        const notificationCount = group.notifications ? group.notifications.length : 0;
        if (notificationCount < 2)
            return;
        const wasExpanded = NotificationService.expandedGroups[group.key] || false;
        const groupIndex = currentItem.groupIndex;

        isTogglingGroup = true;
        NotificationService.toggleGroupExpansion(group.key);
        rebuildFlatNavigation();
        const type = wasExpanded ? "group" : "notification";
        const index = flatNavigation.findIndex(item => item.type === type && item.groupIndex === groupIndex);
        if (index >= 0)
            selectedFlatIndex = index;
        updateSelectedIdFromIndex();
        selectionVersion++;
        ensureVisible();

        isTogglingGroup = false;
    }

    function handleEnterKey() {
        const selection = getCurrentSelection();
        const group = NotificationService.groupedNotifications[selection.groupIndex];
        if (!group)
            return;
        const notification = selection.type === "notification" ? group.notifications[selection.notificationIndex] : group.latestNotification;
        const actions = notification?.actions || [];
        const index = actions.findIndex(action => action.identifier === "default");
        executeAction(index < 0 ? 0 : index);
    }

    function toggleTextExpanded() {
        if (flatNavigation.length === 0 || selectedFlatIndex >= flatNavigation.length)
            return;
        const currentItem = flatNavigation[selectedFlatIndex];
        const groups = NotificationService.groupedNotifications;
        const group = groups[currentItem.groupIndex];
        if (!group)
            return;
        let messageId = "";

        if (currentItem.type === "group") {
            messageId = group.latestNotification?.notification?.id + "_desc";
        } else if (currentItem.type === "notification" && currentItem.notificationIndex >= 0 && currentItem.notificationIndex < group.notifications.length) {
            messageId = group.notifications[currentItem.notificationIndex]?.notification?.id + "_desc";
        }

        if (messageId) {
            NotificationService.toggleMessageExpansion(messageId);
        }
    }

    function executeAction(actionIndex) {
        if (flatNavigation.length === 0 || selectedFlatIndex >= flatNavigation.length)
            return;
        const currentItem = flatNavigation[selectedFlatIndex];
        const groups = NotificationService.groupedNotifications;
        const group = groups[currentItem.groupIndex];
        if (!group)
            return;
        let actions = [];

        if (currentItem.type === "group") {
            actions = group.latestNotification?.actions || [];
        } else if (currentItem.type === "notification" && currentItem.notificationIndex >= 0 && currentItem.notificationIndex < group.notifications.length) {
            actions = group.notifications[currentItem.notificationIndex]?.actions || [];
        }

        if (actionIndex >= 0 && actionIndex < actions.length) {
            const action = actions[actionIndex];
            if (action.invoke) {
                action.invoke();
                if (onClose)
                    onClose();
            }
        }
    }

    function clearSelected() {
        if (flatNavigation.length === 0 || selectedFlatIndex >= flatNavigation.length)
            return;
        const currentItem = flatNavigation[selectedFlatIndex];
        const groups = NotificationService.groupedNotifications;
        const group = groups[currentItem.groupIndex];
        if (!group)
            return;
        if (currentItem.type === "group") {
            NotificationService.dismissGroup(group.key);
        } else if (currentItem.type === "notification") {
            const notification = group.notifications[currentItem.notificationIndex];
            NotificationService.dismissNotification(notification);
        }

        rebuildFlatNavigation();

        if (flatNavigation.length === 0) {
            keyboardNavigationActive = false;
            if (listView) {
                listView.keyboardActive = false;
            }
        } else {
            selectedFlatIndex = Math.min(selectedFlatIndex, flatNavigation.length - 1);
            updateSelectedIdFromIndex();
            ensureVisible();
        }
    }

    function findRepeater(parent) {
        if (!parent || !parent.children) {
            return null;
        }
        for (var i = 0; i < parent.children.length; i++) {
            const child = parent.children[i];
            if (child.objectName === "notificationRepeater") {
                return child;
            }
            const found = findRepeater(child);
            if (found) {
                return found;
            }
        }
        return null;
    }

    function ensureVisible() {
        if (flatNavigation.length === 0 || selectedFlatIndex >= flatNavigation.length || !listView)
            return;
        const currentItem = flatNavigation[selectedFlatIndex];

        if (keyboardNavigationActive && currentItem && currentItem.groupIndex >= 0) {
            if (currentItem.type === "notification") {
                const groupDelegate = listView.itemAtIndex(currentItem.groupIndex);
                if (groupDelegate && groupDelegate.children && groupDelegate.children.length > 0) {
                    const notificationCard = groupDelegate.children[0];
                    const repeater = findRepeater(notificationCard);

                    if (repeater && currentItem.notificationIndex < repeater.count) {
                        const notificationItem = repeater.itemAt(currentItem.notificationIndex);
                        if (notificationItem) {
                            const itemPos = notificationItem.mapToItem(listView.contentItem, 0, 0);
                            const itemY = itemPos.y;
                            const itemHeight = notificationItem.height;

                            const viewportTop = listView.contentY;
                            const viewportBottom = listView.contentY + listView.height;

                            if (itemY < viewportTop) {
                                listView.contentY = itemY - NotificationMetrics.cardPadding;
                            } else if (itemY + itemHeight > viewportBottom) {
                                listView.contentY = itemY + itemHeight - listView.height + NotificationMetrics.cardPadding;
                            }
                        }
                    }
                }
            } else {
                listView.revealIndex(currentItem.groupIndex);
            }

            listView.forceLayout();
        }
    }

    function handleKey(event) {
        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && (event.modifiers & Qt.ShiftModifier)) {
            NotificationService.clearAllNotifications();
            rebuildFlatNavigation();
            if (flatNavigation.length === 0) {
                keyboardNavigationActive = false;
                if (listView) {
                    listView.keyboardActive = false;
                }
            } else {
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
            }
            selectionVersion++;
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            if (keyboardNavigationActive) {
                keyboardNavigationActive = false;
                event.accepted = true;
            } else {
                if (onClose)
                    onClose();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Down || event.key === 16777237) {
            if (!keyboardNavigationActive) {
                keyboardNavigationActive = true;
                rebuildFlatNavigation();
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
                if (listView) {
                    listView.keyboardActive = true;
                }
                selectionVersion++;
                ensureVisible();
                event.accepted = true;
            } else {
                selectNext();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_Up || event.key === 16777235) {
            if (!keyboardNavigationActive) {
                keyboardNavigationActive = true;
                rebuildFlatNavigation();
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
                if (listView) {
                    listView.keyboardActive = true;
                }
                selectionVersion++;
                ensureVisible();
                event.accepted = true;
            } else if (selectedFlatIndex === 0) {
                keyboardNavigationActive = false;
                if (listView) {
                    listView.keyboardActive = false;
                }
                selectionVersion++;
                event.accepted = true;
                return;
            } else {
                selectPrevious();
                event.accepted = true;
            }
        } else if (event.key === Qt.Key_N && event.modifiers & Qt.ControlModifier) {
            if (!keyboardNavigationActive) {
                keyboardNavigationActive = true;
                rebuildFlatNavigation();
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
                if (listView) {
                    listView.keyboardActive = true;
                }
                selectionVersion++;
                ensureVisible();
            } else {
                selectNext();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_P && event.modifiers & Qt.ControlModifier) {
            if (!keyboardNavigationActive) {
                keyboardNavigationActive = true;
                rebuildFlatNavigation();
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
                if (listView) {
                    listView.keyboardActive = true;
                }
                selectionVersion++;
                ensureVisible();
            } else if (selectedFlatIndex === 0) {
                keyboardNavigationActive = false;
                if (listView) {
                    listView.keyboardActive = false;
                }
                selectionVersion++;
            } else {
                selectPrevious();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier) {
            if (!keyboardNavigationActive) {
                keyboardNavigationActive = true;
                rebuildFlatNavigation();
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
                if (listView) {
                    listView.keyboardActive = true;
                }
                selectionVersion++;
                ensureVisible();
            } else {
                selectNext();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier) {
            if (!keyboardNavigationActive) {
                keyboardNavigationActive = true;
                rebuildFlatNavigation();
                selectedFlatIndex = 0;
                updateSelectedIdFromIndex();
                if (listView) {
                    listView.keyboardActive = true;
                }
                selectionVersion++;
                ensureVisible();
            } else if (selectedFlatIndex === 0) {
                keyboardNavigationActive = false;
                if (listView) {
                    listView.keyboardActive = false;
                }
                selectionVersion++;
            } else {
                selectPrevious();
            }
            event.accepted = true;
        } else if (keyboardNavigationActive) {
            if (event.key === Qt.Key_Space) {
                toggleGroupExpanded();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                handleEnterKey();
                event.accepted = true;
            } else if (event.key === Qt.Key_E) {
                toggleTextExpanded();
                event.accepted = true;
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                clearSelected();
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                selectNext();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab) {
                selectPrevious();
                event.accepted = true;
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const actionIndex = event.key - Qt.Key_1;
                executeAction(actionIndex);
                event.accepted = true;
            }
        }

        if (event.key === Qt.Key_F10) {
            showKeyboardHints = !showKeyboardHints;
            event.accepted = true;
        }
    }
    function getCurrentSelection() {
        if (!keyboardNavigationActive || selectedFlatIndex < 0 || selectedFlatIndex >= flatNavigation.length) {
            return {
                "type": "",
                "groupIndex": -1,
                "notificationIndex": -1
            };
        }
        const result = flatNavigation[selectedFlatIndex] || {
            "type": "",
            "groupIndex": -1,
            "notificationIndex": -1
        };
        return result;
    }
}
